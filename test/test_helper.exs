ExUnit.start(capture_log: true)

exclude_tags =
  case System.get_env("PG_VERSION") do
    "13" ->
      [:postgres_14, :postgres_15, :postgres_16]

    "14" ->
      [:postgres_15, :postgres_16]

    "15" ->
      [:postgres_16]

    "16" ->
      []

    _ ->
      []
  end

ExUnit.configure(stacktrace_depth: 100, exclude: exclude_tags)

AshPostgres.TestRepo.start_link()
AshPostgres.TestNoSandboxRepo.start_link()
