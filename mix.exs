defmodule Lanx.MixProject do
  use Mix.Project

  def project do
    [
      app: :lanx,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Docs
      name: "Lanx",
      source_url: "https://github.com/Benjamin-Philip/lanx",
      homepage_url: "https://benjamin-philip.github.io/lanx/",
      docs: [
        # The main page in the docs
        main: "MyApp",
        extras: ["README.md"]
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

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
