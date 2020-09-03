use Mix.Config

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
    manage_readme_version: "README.md",
    version_tag_prefix: "v"
end

if Mix.env() == :test do
  # Configure your database
  #
  # The MIX_TEST_PARTITION environment variable can be used
  # to provide built-in test partitioning in CI environment.
  # Run `mix help test` for more information.
  config :ash_postgres, AshPostgres.TestRepo,
    username: "postgres",
    password: "postgres",
    database: "ash_postgres_test#{System.get_env("MIX_TEST_PARTITION")}",
    hostname: "localhost",
    pool: Ecto.Adapters.SQL.Sandbox

  config :ash_postgres, ecto_repos: [AshPostgres.TestRepo]

  config :ash_postgres, AshPostgres.TestRepo, migration_primary_key: [name: :id, type: :binary_id]

  config :logger, level: :warn
end
