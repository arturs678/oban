defmodule Oban.Plugins.GossipTest do
  use Oban.Case

  alias Oban.Plugins.Gossip
  alias Oban.{Notifier, PluginTelemetryHandler, Registry}

  @moduletag :integration

  defmodule SlowFakeProducer do
    @moduledoc false

    use GenServer

    def start_link(opts) do
      GenServer.start_link(__MODULE__, [], name: opts[:name])
    end

    @impl GenServer
    def init(_), do: {:ok, []}

    @impl GenServer
    def handle_call(:check, _, _) do
      Process.sleep(100)

      {:reply, :ok, []}
    end
  end

  test "queue producers periodically emit check meta as gossip" do
    PluginTelemetryHandler.attach_plugin_events("plugin-gossip-handler")

    name =
      start_supervised_oban!(
        plugins: [{Gossip, interval: 10}],
        queues: [alpha: 2, omega: 3]
      )

    :ok = Notifier.listen(name, [:gossip])

    assert_receive {:notification, :gossip, %{"queue" => "alpha", "limit" => 2}}
    assert_receive {:notification, :gossip, %{"queue" => "omega", "limit" => 3}}

    assert_receive {:event, :start, %{system_time: _}, %{conf: _, plugin: Gossip}}
    assert_receive {:event, :stop, %{duration: _}, %{conf: _, plugin: Gossip, gossip_count: 2}}
  after
    :telemetry.detach("plugin-gossip-handler")
  end

  test "slow producer calls don't crash gossip checks" do
    PluginTelemetryHandler.attach_plugin_events("plugin-gossip-handler")

    name = start_supervised_oban!(plugins: [{Gossip, interval: 25}])

    prod_name = Registry.via(name, {:producer, :slow_fake})
    start_supervised!({SlowFakeProducer, name: prod_name})

    refute_receive {:notification, :gossip, _}
  after
    :telemetry.detach("plugin-gossip-handler")
  end
end
