ExUnit.start(capture_log: true)
ExUnit.configure(stacktrace_depth: 100)

AshPostgres.TestRepo.start_link()
AshPostgres.TestNoSandboxRepo.start_link()
