# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshPostgres.SetupProbe do
  @moduledoc false
  use Mix.Task

  @impl true
  def run(args) do
    send(:ash_postgres_setup_probe, {:ash_postgres_setup_probe, args})
    :ok
  end
end

defmodule AshPostgres.DataLayerSetupTest do
  @moduledoc false
  use ExUnit.Case, async: false

  describe "has_tenant_migrations?/1" do
    test "TestRepo has tenant migration files, so setup takes the tenant pass" do
      files =
        []
        |> AshPostgres.Mix.Helpers.tenant_migrations_path(AshPostgres.TestRepo)
        |> Path.join("**/*.exs")
        |> Path.wildcard()

      refute Enum.empty?(files)
    end
  end

  describe "ash_postgres.migrate switches" do
    test "rejects --tenant (singular), which is what setup used to pass" do
      assert_raise Mix.Error, fn ->
        Mix.Task.rerun("ash_postgres.migrate", ["--tenant"])
      end
    end
  end

  describe "Mix.Task.run/2 vs Mix.Task.rerun/2" do
    setup do
      Process.register(self(), :ash_postgres_setup_probe)
      Mix.Task.reenable("ash_postgres.setup_probe")

      on_exit(fn ->
        if Process.whereis(:ash_postgres_setup_probe) == self() do
          Process.unregister(:ash_postgres_setup_probe)
        end
      end)

      :ok
    end

    test "a second Mix.Task.run of the same task is a no-op; Mix.Task.rerun is not" do
      Mix.Task.run("ash_postgres.setup_probe", ["first"])
      Mix.Task.run("ash_postgres.setup_probe", ["second"])
      Mix.Task.rerun("ash_postgres.setup_probe", ["third"])

      assert_received {:ash_postgres_setup_probe, ["first"]}
      refute_received {:ash_postgres_setup_probe, ["second"]}
      assert_received {:ash_postgres_setup_probe, ["third"]}
    end
  end
end
