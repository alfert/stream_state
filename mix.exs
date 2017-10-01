defmodule StreamState.Mixfile do
  use Mix.Project

  def project do
    [
      app: :stream_state,
      version: "0.1.0",
      elixir: "~> 1.5",
      start_permanent: Mix.env == :prod,
      test_coverage: [tool: Coverex.Task, console_log: true],
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {StreamState.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"},
      {:stream_data, "~> 0.3", only: :test},
      # {:dialyxir, "~> 0.5.1", only: [:dev, :test]},
      {:coverex, "~> 1.4", only: :test}
    ]
  end
end
