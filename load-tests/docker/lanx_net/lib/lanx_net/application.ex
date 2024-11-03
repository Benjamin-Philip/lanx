defmodule LanxNet.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    {:ok, resnet} = Bumblebee.load_model({:hf, "microsoft/resnet-50"})
    {:ok, featurizer} = Bumblebee.load_featurizer({:hf, "microsoft/resnet-50"})

    serving = Bumblebee.Vision.image_classification(resnet, featurizer)

    children = [
      LanxNetWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:lanx_net, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: LanxNet.PubSub},
      # Start a worker by calling: LanxNet.Worker.start_link(arg)
      # {LanxNet.Worker, arg},
      # Start to serve requests, typically the last entry
      LanxNetWeb.Endpoint,
      {Nx.Serving,
       serving: serving,
       name: LanxNet.Serving,
       batch_size: 10,
       batch_timeout: 100,
       partitions: true}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LanxNet.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LanxNetWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
