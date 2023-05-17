ExUnit.start()
ExUnit.configure(stacktrace_depth: 100)

AshPostgres.TestRepo.start_link()
AshPostgres.TestNoSandboxRepo.start_link()
