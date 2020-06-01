defmodule AshPostgres.MixProject do
  use Mix.Project

  @description """
  A postgres data layer for `Ash` resources. Leverages Ecto's postgres
  support, and delegates to a configured repo.
  """

  @version "0.1.2"

  def project do
    [
      app: :ash_postgres,
      version: @version,
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: @description,
      package: package(),
      source_url: "https://github.com/ash-project/ash_postgres",
      homepage_url: "https://github.com/ash-project/ash_postgres"
    ]
  end

  defp package do
    [
      name: :ash_postgres,
      licenses: ["MIT"],
      links: %{
        GitHub: "https://github.com/ash-project/ash_postgres"
      }
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto_sql, "~> 3.0"},
      {:postgrex, ">= 0.0.0"},
      {:ash, "~> 0.1.2"},
      {:git_ops, "~> 2.0.0", only: :dev},
      {:ex_doc, "~> 0.21", only: :dev, runtime: false}
    ]
  end
end
