# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

import Config

config :ash, :default_string_length_count, :codepoints

config :ash_postgres,
  ecto_repos: [AshPostgres.Yugabyte.Repo],
  ash_domains: [AshPostgres.Yugabyte.Domain]

config :ash_postgres, AshPostgres.Yugabyte.Repo,
  hostname: System.get_env("YUGABYTE_HOST", "127.0.0.1"),
  port: String.to_integer(System.get_env("YUGABYTE_PORT", "5433")),
  username: System.get_env("YUGABYTE_USER", "yugabyte"),
  password: System.get_env("YUGABYTE_PASSWORD"),
  database: "ash_postgres_yugabyte_test",
  pool_size: 2,
  migration_lock: false,
  log: false

config :logger, level: :warning
