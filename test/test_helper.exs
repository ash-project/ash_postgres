# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

ExUnit.start(capture_log: true)

Logger.configure(level: :debug)

# A `@tag :postgres_<n>` marks a test as requiring PostgreSQL >= n. Exclude any whose required
# version is newer than the version under test. Read from `TestRepo.min_pg_version/0` so the two
# cannot disagree about what an unset `PG_VERSION` means.
default_pg_version = AshPostgres.TestRepo.min_pg_version().major

pg_version =
  case System.get_env("PG_VERSION") do
    nil ->
      default_pg_version

    version ->
      case Integer.parse(version) do
        {major, _} -> major
        :error -> default_pg_version
      end
  end

exclude_tags =
  for n <- [14, 15, 16, 17, 18, 19], n > pg_version, do: :"postgres_#{n}"

ExUnit.configure(stacktrace_depth: 100, exclude: exclude_tags)

AshPostgres.TestRepo.start_link()
AshPostgres.DevTestRepo.start_link()
AshPostgres.TestNoSandboxRepo.start_link()

format_sql_query =
  try do
    case System.shell("which pg_format") do
      {_, 0} ->
        fn query ->
          try do
            case System.shell("echo $SQL_QUERY | pg_format -",
                   env: [{"SQL_QUERY", query}],
                   stderr_to_stdout: true
                 ) do
              {formatted_query, 0} -> String.trim_trailing(formatted_query)
              _ -> query
            end
          rescue
            _ -> query
          end
        end

      _ ->
        & &1
    end
  rescue
    _ ->
      & &1
  end

Ecto.DevLogger.install(AshPostgres.TestRepo, before_inline_callback: format_sql_query)
Ecto.DevLogger.install(AshPostgres.DevTestRepo, before_inline_callback: format_sql_query)
Ecto.DevLogger.install(AshPostgres.TestNoSandboxRepo, before_inline_callback: format_sql_query)
