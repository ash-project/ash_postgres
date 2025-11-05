# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.MixProject do
  use Mix.Project

  @description """
  The PostgreSQL data layer for Ash Framework
  """

  @version "2.6.25"

  def project do
    [
      app: :ash_postgres,
      version: @version,
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: @description,
      elixirc_paths: elixirc_paths(Mix.env()),
      consolidate_protocols: Mix.env() == :prod,
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.github": :test,
        "test.create": :test,
        "test.migrate": :test,
        "test.rollback": :test,
        "test.migrate_tenants": :test,
        "test.check_migrations": :test,
        "test.drop": :test,
        "test.generate_migrations": :test,
        "test.reset": :test
      ],
      dialyzer: [
        plt_add_apps: [:ecto, :ash, :mix]
      ],
      docs: &docs/0,
      aliases: aliases(),
      package: package(),
      source_url: "https://github.com/ash-project/ash_postgres/",
      homepage_url: "https://ash-hq.org",
      consolidate_protocols: Mix.env() == :prod
    ]
  end

  if Mix.env() == :test do
    def application() do
      [
        mod: {AshPostgres.TestApp, []}
      ]
    end
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      maintainers: [
        "Zach Daniel <zach@zachdaniel.dev>"
      ],
      licenses: ["MIT"],
      files: ~w(lib .formatter.exs mix.exs README* LICENSE*
      CHANGELOG* documentation usage-rules.md),
      links: %{
        "GitHub" => "https://github.com/ash-project/ash_postgres",
        "Changelog" => "https://github.com/ash-project/ash_postgres/blob/main/CHANGELOG.md",
        "Discord" => "https://discord.gg/HTHRaaVPUc",
        "Website" => "https://ash-hq.org",
        "Forum" => "https://elixirforum.com/c/elixir-framework-forums/ash-framework-forum",
        "REUSE Compliance" =>
          "https://api.reuse.software/info/github.com/ash-project/ash_postgres"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      logo: "logos/small-logo.png",
      before_closing_head_tag: fn type ->
        if type == :html do
          """
          <script>
            if (location.hostname === "hexdocs.pm") {
              var script = document.createElement("script");
              script.src = "https://plausible.io/js/script.js";
              script.setAttribute("defer", "defer")
              script.setAttribute("data-domain", "ashhexdocs")
              document.head.appendChild(script);
            }
          </script>
          """
        end
      end,
      extras: [
        {"README.md", title: "Home"},
        "documentation/tutorials/get-started-with-ash-postgres.md",
        "documentation/tutorials/set-up-with-existing-database.md",
        "documentation/topics/about-ash-postgres/what-is-ash-postgres.md",
        "documentation/topics/resources/references.md",
        "documentation/topics/resources/polymorphic-resources.md",
        "documentation/topics/development/migrations-and-tasks.md",
        "documentation/topics/development/testing.md",
        "documentation/topics/development/upgrading-to-2.0.md",
        "documentation/topics/advanced/expressions.md",
        "documentation/topics/advanced/schema-based-multitenancy.md",
        "documentation/topics/advanced/using-multiple-repos.md",
        "documentation/topics/advanced/manual-relationships.md",
        {"documentation/dsls/DSL-AshPostgres.DataLayer.md",
         search_data: Spark.Docs.search_data_for(AshPostgres.DataLayer)},
        "CHANGELOG.md"
      ],
      groups_for_extras: [
        Tutorials: ~r"documentation/tutorials",
        Resources: ~r"documentation/topics",
        Development: ~r"documentation/topics/development",
        "About AshPostgres": ["CHANGELOG.md"],
        Advanced: ~r"documentation/topics/advanced",
        Reference: ~r"documentation/topics/dsls"
      ],
      skip_undefined_reference_warnings_on: [
        "CHANGELOG.md",
        "documentation/development/upgrading-to-2.0.md"
      ],
      nest_modules_by_prefix: [
        AshPostgres.Functions
      ],
      groups_for_modules: [
        AshPostgres: [
          AshPostgres,
          AshPostgres.Repo,
          AshPostgres.DataLayer
        ],
        Utilities: [
          AshPostgres.ManualRelationship
        ],
        Introspection: [
          AshPostgres.DataLayer.Info,
          AshPostgres.CheckConstraint,
          AshPostgres.CustomExtension,
          AshPostgres.CustomIndex,
          AshPostgres.Reference,
          AshPostgres.Statement
        ],
        Types: [
          AshPostgres.Ltree,
          AshPostgres.Type,
          AshPostgres.Tsquery,
          AshPostgres.Tsvector,
          AshPostgres.Timestamptz,
          AshPostgres.TimestamptzUsec
        ],
        Extensions: [
          AshPostgres.Extensions.Vector
        ],
        "Custom Aggregates": [
          AshPostgres.CustomAggregate
        ],
        "Postgres Migrations": [
          AshPostgres.Migration,
          EctoMigrationDefault
        ],
        Expressions: [
          AshPostgres.Functions.TrigramSimilarity,
          AshPostgres.Functions.ILike,
          AshPostgres.Functions.Like,
          AshPostgres.Functions.VectorCosineDistance
        ]
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ash, ash_version("~> 3.7 and >= 3.7.5")},
      {:spark, "~> 2.3 and >= 2.3.4"},
      {:ash_sql, ash_sql_version("~> 0.3 and >= 0.3.7")},
      {:igniter, "~> 0.6 and >= 0.6.29", optional: true},
      {:ecto_sql, "~> 3.13"},
      {:ecto, "~> 3.13"},
      {:jason, "~> 1.0"},
      {:postgrex, ">= 0.0.0"},
      # dev/test dependencies
      {:tz, "~> 0.28.1", only: [:dev, :test]},
      {:ecto_dev_logger, "~> 0.14", only: :test},
      {:eflame, "~> 1.0", only: [:dev, :test]},
      {:simple_sat, "~> 0.1", only: [:dev, :test]},
      {:benchee, "~> 1.1", only: [:dev, :test]},
      {:git_ops, "~> 2.5", only: [:dev, :test]},
      {:ex_doc, "~> 0.37-rc", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.14", only: [:dev, :test]},
      {:credo, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:mix_audit, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:dialyxir, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:sobelow, ">= 0.0.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp ash_version(default_version) do
    case System.get_env("ASH_VERSION") do
      nil ->
        default_version

      "local" ->
        [path: "../ash", override: true]

      "main" ->
        [git: "https://github.com/ash-project/ash.git", override: true]

      version when is_binary(version) ->
        "~> #{version}"

      version ->
        version
    end
  end

  defp ash_sql_version(default_version) do
    case System.get_env("ASH_SQL_VERSION") do
      nil ->
        default_version

      "local" ->
        [path: "../ash_sql", override: true]

      "main" ->
        [git: "https://github.com/ash-project/ash_sql.git"]

      version when is_binary(version) ->
        "~> #{version}"

      version ->
        version
    end
  end

  defp aliases do
    [
      sobelow:
        "sobelow --skip -i Config.Secrets --ignore-files lib/migration_generator/migration_generator.ex",
      credo: "credo --strict",
      docs: [
        "spark.cheat_sheets",
        "docs",
        "spark.replace_doc_links"
      ],
      format: "format --migrate",
      "spark.formatter": "spark.formatter --extensions AshPostgres.DataLayer",
      "spark.cheat_sheets": "spark.cheat_sheets --extensions AshPostgres.DataLayer",
      "test.generate_migrations": "ash_postgres.generate_migrations --auto-name",
      "test.check_migrations": "ash_postgres.generate_migrations --check",
      "test.migrate_tenants": "ash_postgres.migrate --tenants",
      "test.migrate": "ash_postgres.migrate",
      "test.rollback": "ash_postgres.rollback",
      "test.create": "ash_postgres.create",
      "test.reset": ["test.drop", "test.create", "test.migrate", "ash_postgres.migrate --tenants"],
      "test.drop": "ash_postgres.drop"
    ]
  end
end
