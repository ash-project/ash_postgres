import Config

if Mix.env() == :dev do
  config :git_ops,
    mix_project: AshPostgres.MixProject,
    changelog_file: "CHANGELOG.md",
    repository_url: "https://github.com/ash-project/ash_postgres",
    # Instructs the tool to manage your mix version in your `mix.exs` file
    # See below for more information
    manage_mix_version?: true,
    # Instructs the tool to manage the version in your README.md
    # Pass in `true` to use `"README.md"` or a string to customize
    manage_readme_version: ["README.md", "documentation/tutorials/get-started-with-postgres.md"],
    version_tag_prefix: "v"
end

if Mix.env() == :test do
  config :ash, :validate_domain_resource_inclusion?, false
  config :ash, :validate_domain_config_inclusion?, false

  config :ash_postgres, AshPostgres.TestRepo,
    username: "postgres",
    database: "ash_postgres_test",
    hostname: "localhost",
    pool: Ecto.Adapters.SQL.Sandbox

  # sobelow_skip ["Config.Secrets"]
  config :ash_postgres, AshPostgres.TestRepo, password: "postgres"

  config :ash_postgres, AshPostgres.TestRepo, migration_primary_key: [name: :id, type: :binary_id]

  config :ash_postgres, AshPostgres.TestNoSandboxRepo,
    username: "postgres",
    database: "ash_postgres_test",
    hostname: "localhost"

  # sobelow_skip ["Config.Secrets"]
  config :ash_postgres, AshPostgres.TestNoSandboxRepo, password: "postgres"

  config :ash_postgres, AshPostgres.TestNoSandboxRepo,
    migration_primary_key: [name: :id, type: :binary_id]

  config :ash_postgres,
    ecto_repos: [AshPostgres.TestRepo, AshPostgres.TestNoSandboxRepo],
    ash_domains: [
      AshPostgres.Test.Domain,
      AshPostgres.MultitenancyTest.Domain,
      AshPostgres.Test.ComplexCalculations.Domain
    ]

  config :logger, level: :warning
end
