ExUnit.start(capture_log: true)

Logger.configure(level: :debug)

exclude_tags =
  case System.get_env("PG_VERSION") do
    "13" ->
      [:postgres_14, :postgres_15, :postgres_16]

    "14" ->
      [:postgres_15, :postgres_16]

    "15" ->
      [:postgres_16]

    _ ->
      []
  end

ExUnit.configure(stacktrace_depth: 100, exclude: exclude_tags)

AshPostgres.TestRepo.start_link()
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
Ecto.DevLogger.install(AshPostgres.TestNoSandboxRepo, before_inline_callback: format_sql_query)
