defmodule Asher.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :asher,
      version: @version,
      elixir: "~> 1.20-rc",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      escript: escript(),
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # The standalone `asher` command. Built with `mix escript.build`, installed
  # with `mix escript.install github <you>/asher`. Escripts bundle their runtime
  # dependencies, so this works as a global command with no Mix project — unlike
  # an archive, which cannot host igniter-based mix tasks.
  defp escript do
    [main_module: Asher.CLI, app: nil]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:igniter, "~> 0.8", only: [:dev, :test]},
      {:jason, "~> 1.4"}
    ]
  end
end
