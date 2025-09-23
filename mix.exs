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
      {:reactor, "~> 0.16"},
      {:soap, "~> 1.0"},
      {:saxy, "~> 1.6"},
      #
      # Ecto
      #
      {:ecto, "~> 3.0"},
      {:ecto_sql, "~> 3.0"},
      #
      #
      #
      {:jason, "~> 1.0"},
      {:postgrex, "~> 0.21"},
      #
      # Cloak
      #
      {:cloak, "~> 1.1"},
      {:cloak_ecto, "~> 1.2"},
      #
      # AWS
      #
      {:ex_aws, "~> 2.1"},
      {:ex_aws_dynamo, "~> 4.0"},
      {:ex_aws_sts, "~> 2.0"},
      {:configparser_ex, "~> 4.0"},
      # Needed for ex_aws.STS
      {:sweet_xml, "~> 0.6"}
    ]
  end
end
