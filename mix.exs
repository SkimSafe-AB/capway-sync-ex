defmodule CapwaySync.MixProject do
  use Mix.Project

  def project do
    [
      app: :capway_sync,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :reactor, :soap],
      mod: {CapwaySync.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:reactor, "~> 0.16.0"},
      {:soap, "~> 1.0"},
      {:sweet_xml, "~> 0.7.0"},
      {:saxy, "~> 1.6"},
      #
      # Ecto
      #
      {:ecto, "~> 3.0"},
      #
      # Cloak
      #
      {:cloak, "~> 1.1"},
      {:cloak_ecto, "~> 1.2"}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
