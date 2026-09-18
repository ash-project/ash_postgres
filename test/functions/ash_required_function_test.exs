# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.AshRequiredFunctionTest do
  use AshPostgres.RepoCase, async: true

  import Ash.Expr

  alias AshPostgres.MigrationGenerator.AshFunctions
  alias AshPostgres.Test.Post
  alias AshPostgres.TestRepo

  # Regression for https://github.com/ash-project/ash_postgres/issues/857
  #
  # `ash_required/2` is created with `SET search_path = ''`, so any unqualified
  # function call inside its body fails to resolve at call time even though the
  # migration itself succeeds. It backs `required!/2`, which core emits for atomic
  # updates of `allow_nil?: false` attributes.

  test "atomic updates use ash_required/2 to raise when the value is only null in SQL" do
    Ash.create!(Post, %{title: "foo"})

    # `score` is nullable and unset, so only the database can tell that the new
    # value for `version` (allow_nil?: false) is null.
    assert %Ash.BulkResult{
             error_count: 1,
             errors: [
               %Ash.Error.Invalid{errors: [%Ash.Error.Changes.Required{field: :version}]}
             ]
           } =
             Ash.bulk_update(Post, :update, %{},
               atomic_update: %{version: expr(score)},
               strategy: :atomic,
               return_records?: true,
               return_errors?: true,
               authorize?: false
             )
  end

  test "ash_required/2 raises the ash_error payload when the value is null" do
    error =
      assert_raise Postgrex.Error, fn ->
        TestRepo.query!(~s|SELECT ash_required(NULL::text, '{"field":"value"}'::jsonb)|)
      end

    assert error.postgres.message == ~s|ash_error: {"field": "value"}|
  end

  test "ash_required/2 returns the value when it is not null" do
    assert %{rows: [["hello"]]} =
             TestRepo.query!(~s|SELECT ash_required('hello'::text, '{}'::jsonb)|)
  end

  test "no install path defines ash_required/2 in terms of an unqualified function call" do
    for version <- [nil | Enum.to_list(0..(AshFunctions.latest_version() - 1))] do
      sql = AshFunctions.install(version)

      refute sql =~ "ash_raise_error(payload",
             "ash_required/2 generated for version #{inspect(version)} calls ash_raise_error/2, " <>
               "which cannot resolve under SET search_path = ''"
    end
  end
end
