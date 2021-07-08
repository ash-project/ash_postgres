defmodule AshPostgres.MixProject do
  use Mix.Project

  @description """
  A postgres data layer for `Ash` resources. Leverages Ecto's postgres
  support, and delegates to a configured repo.
  """

  @version "0.40.6"

  def project do
    [
      app: :ash_postgres,
      version: @version,
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: @description,
      test_coverage: [tool: ExCoveralls],
      elixirc_paths: elixirc_paths(Mix.env()),
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.github": :test,
        "test.create": :test,
        "test.migrate": :test,
        "test.migrate_tenants": :test,
        "test.drop": :test,
        "test.generate_migrations": :test,
        "test.reset": :test
      ],
      dialyzer: [
        plt_add_apps: [:ecto, :ash, :mix]
      ],
      docs: docs(),
      aliases: aliases(),
      package: package(),
      source_url: "https://github.com/ash-project/ash_postgres",
      homepage_url: "https://github.com/ash-project/ash_postgres"
    ]
  end

  if Mix.env() == :test do
    def application() do
      [applications: [:ecto, :ecto_sql, :jason, :ash, :postgrex], mod: {AshPostgres.TestApp, []}]
    end
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      name: :ash_postgres,
      licenses: ["MIT"],
      links: %{
        GitHub: "https://github.com/ash-project/ash_postgres"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      logo: "logos/small-logo.png",
      extras: [
        "README.md",
        "documentation/migrations_and_tasks.md",
        "documentation/multitenancy.md",
        "documentation/polymorphic_resources.md"
      ],
      groups_for_extras: [
        guides: [
          "documentation/multitenancy.md",
          "documentation/migrations_and_tasks.md",
          "documentation/polymorphic_resources.md"
        ]
      ],
      groups_for_modules: [
        "entry point": [AshPostgres],
        "data layer and dsl": ~r/AshPostgres.DataLayer/,
        functions: [AshPostgres.Functions.TrigramSimilarity],
        repo: [AshPostgres.Repo],
        migrations: [AshPostgres.MigrationGenerator],
        utilities: [AsPostgres.MultiTenancy],
        "filter predicates": ~r/AshPostgres.Predicates/,
        "DSL Transformers": ~r/AshPostgres.Transformers/
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto_sql, "~> 3.5"},
      {:jason, "~> 1.0"},
      {:postgrex, ">= 0.0.0"},
      {:ash, ash_version("~> 1.46 and >= 1.46.3")},
      {:git_ops, "~> 2.4.3", only: :dev},
      {:ex_doc, "~> 0.22", only: :dev, runtime: false},
      {:ex_check, "~> 0.11.0", only: :dev},
      {:credo, ">= 0.0.0", only: :dev, runtime: false},
      {:dialyxir, ">= 0.0.0", only: :dev, runtime: false},
      {:sobelow, ">= 0.0.0", only: :dev, runtime: false},
      {:excoveralls, "~> 0.13.0", only: [:dev, :test]}
    ]
  end

  defp ash_version(default_version) do
    case System.get_env("ASH_VERSION") do
      nil -> default_version
      "local" -> [path: "../ash"]
      "master" -> [git: "https://github.com/ash-project/ash.git"]
      version -> "~> #{version}"
    end
  end

  defp aliases do
    [
      sobelow:
        "sobelow --skip -i Config.Secrets --ignore-files lib/migration_generator/migration_generator.ex",
      credo: "credo --strict",
      "ash.formatter": "ash.formatter --extensions AshPostgres.DataLayer",
      "test.generate_migrations": "ash_postgres.generate_migrations",
      "test.migrate_tenants": "ash_postgres.migrate --tenants",
      "test.migrate": "ash_postgres.migrate",
      "test.create": "ash_postgres.create",
      "test.reset": ["test.drop", "test.create", "test.migrate"],
      "test.drop": "ash_postgres.drop"
    ]
  end
end
