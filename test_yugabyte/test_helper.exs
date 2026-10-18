# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

ExUnit.start(capture_log: true)

{:ok, _} = AshPostgres.Yugabyte.Repo.start_link()

%{rows: [[version]]} = AshPostgres.Yugabyte.Repo.query!("SELECT version()")

if !String.contains?(version, "YB-") do
  raise "The YugabyteDB integration suite requires YugabyteDB, got: #{version}"
end

IO.puts("Testing against #{version}")

Ecto.Migrator.up(
  AshPostgres.Yugabyte.Repo,
  20_261_018_000_000,
  AshPostgres.Yugabyte.CreateItems
)
