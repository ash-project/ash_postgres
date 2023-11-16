defmodule AshPostgres.MixProject do
  use Mix.Project

  @description """
  A postgres data layer for `Ash` resources. Leverages Ecto's postgres
  support, and delegates to a configured repo.
  """

  @version "1.3.62"

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
      docs: docs(),
      aliases: aliases(),
      package: package(),
      source_url: "https://github.com/ash-project/ash_postgres/",
      homepage_url: "https://ash-hq.org",
      consolidate_protocols: true
    ]
  end

  if Mix.env() == :test do
    def application() do
      [
        applications: [:ecto, :ecto_sql, :jason, :ash, :postgrex, :tools, :benchee],
        mod: {AshPostgres.TestApp, []}
      ]
    end
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      name: :ash_postgres,
      licenses: ["MIT"],
      files: ~w(lib .formatter.exs mix.exs README* LICENSE*
      CHANGELOG* documentation),
      links: %{
        GitHub: "https://github.com/ash-project/ash_postgres"
      }
    ]
  end

  defp extras() do
    "documentation/**/*.{md,livemd,cheatmd}"
    |> Path.wildcard()
    |> Enum.map(fn path ->
      title =
        path
        |> Path.basename(".md")
        |> Path.basename(".livemd")
        |> Path.basename(".cheatmd")
        |> String.split(~r/[-_]/)
        |> Enum.map_join(" ", &capitalize/1)
        |> case do
          "F A Q" ->
            "FAQ"

          other ->
            other
        end

      {String.to_atom(path),
       [
         title: title
       ]}
    end)
  end

  defp capitalize(string) do
    string
    |> String.split(" ")
    |> Enum.map(fn string ->
      [hd | tail] = String.graphemes(string)
      String.capitalize(hd) <> Enum.join(tail)
    end)
  end

  defp groups_for_extras() do
    [
      Tutorials: [
        ~r'documentation/tutorials'
      ],
      "How To": ~r'documentation/how_to',
      Topics: ~r'documentation/topics',
      DSLs: ~r'documentation/dsls'
    ]
  end

  defp docs do
    [
      main: "get-started-with-postgres",
      source_ref: "v#{@version}",
      logo: "logos/small-logo.png",
      extras: extras(),
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
      spark: [
        mix_tasks: [
          Postgres: [
            Mix.Tasks.AshPostgres.GenerateMigrations,
            Mix.Tasks.AshPostgres.Create,
            Mix.Tasks.AshPostgres.Drop,
            Mix.Tasks.AshPostgres.Migrate,
            Mix.Tasks.AshPostgres.Rollback
          ]
        ],
        extensions: [
          %{
            module: AshPostgres.DataLayer,
            name: "AshPostgres",
            target: "Ash.Resource",
            type: "DataLayer"
          }
        ]
      ],
      groups_for_extras: groups_for_extras(),
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
          AshPostgres.Type,
          AshPostgres.Tsquery,
          AshPostgres.Tsvector
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
          AshPostgres.Functions.Fragment,
          AshPostgres.Functions.TrigramSimilarity,
          AshPostgres.Functions.ILike,
          AshPostgres.Functions.Like,
          AshPostgres.Functions.VectorCosineDistance
        ],
        Internals: ~r/.*/
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto_sql, "~> 3.9"},
      {:ecto, "~> 3.9"},
      {:jason, "~> 1.0"},
      {:postgrex, ">= 0.0.0"},
      {:ash, ash_version("~> 2.17 and >= 2.17.3")},
      {:benchee, "~> 1.1", only: [:dev, :test]},
      {:git_ops, "~> 2.5", only: [:dev, :test]},
      {:ex_doc, github: "elixir-lang/ex_doc", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.14", only: [:dev, :test]},
      {:credo, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:dialyxir, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:sobelow, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.14", only: [:dev, :test]}
    ]
  end

  defp ash_version(default_version) do
    case System.get_env("ASH_VERSION") do
      nil ->
        default_version

      "local" ->
        [path: "../ash"]

      "main" ->
        [git: "https://github.com/ash-project/ash.git"]

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
        # "spark.cheat_sheets",
        "docs",
        "spark.replace_doc_links",
        "spark.cheat_sheets_in_search"
      ],
      "spark.formatter": "spark.formatter --extensions AshPostgres.DataLayer",
      "spark.cheat_sheets": "spark.cheat_sheets --extensions AshPostgres.DataLayer",
      "spark.cheat_sheets_in_search":
        "spark.cheat_sheets_in_search --extensions AshPostgres.DataLayer",
      "test.generate_migrations": "ash_postgres.generate_migrations",
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
