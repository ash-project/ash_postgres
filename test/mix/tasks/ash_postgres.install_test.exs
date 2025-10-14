# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshPostgres.InstallTest do
  use ExUnit.Case

  import Igniter.Test

  # This is a simple test to ensure that the installation doesnt have
  # any errors. We should add better tests here, though.
  test "installation does not fail" do
    test_project()
    |> Igniter.compose_task("ash_postgres.install", ["--yes"])
    |> assert_creates("lib/test/repo.ex")
  end
end
