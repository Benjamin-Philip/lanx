defmodule Lanx.MixProject do
  use Mix.Project

  def project do
    [
      app: :lanx,
      version: "0.1.0",
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Docs
      name: "Lanx",
      source_url: "https://github.com/Benjamin-Philip/lanx",
      homepage_url: "https://benjamin-philip.github.io/lanx/",
      docs: [
        # The main page in the docs
        main: "Lanx",
        extras: ["README.md", "LICENSE"]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Lanx.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ~w(lib test test/support)
  defp elixirc_paths(_), do: ~w(lib)

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:flame, "~> 0.1.12"},
      {:telemetry, "~> 1.2.1"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
