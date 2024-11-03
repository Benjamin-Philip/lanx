{:lanx, [path: "../../../"]}
{:lanx, [path: "../../../"]}

defmodule LanxNet.MixProject do
  {:lanx, [path: "../../../"]}
  use Mix.Project

  def project do
    [
      app: :lanx_net,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {LanxNet.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    lanx =
      case System.fetch_env("DOCKER_BUILD") do
        {:ok, _} -> {:lanx, path: "./lanx"}
        :error -> {:lanx, path: "../../../"}
      end

    [
      {:bumblebee, "~> 0.6.0"},
      {:exla, "~> 0.9.1"},
      {:stb_image, "~> 0.6.9"},
      lanx,
      {:phoenix, "~> 1.7.14"},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.1.1"},
      {:bandit, "~> 1.5"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get"]
    ]
  end
end
