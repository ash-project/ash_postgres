# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.ErrorExprTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Post

  require Ash.Query
  import Ash.Expr

  test "exceptions in filters are treated as regular Ash exceptions" do
    Post
    |> Ash.Changeset.for_create(:create, %{title: "title"})
    |> Ash.create!()

    assert_raise Ash.Error.Invalid, ~r/this is bad!/, fn ->
      Post
      |> Ash.Query.filter(
        error(Ash.Error.Query.InvalidFilterValue, message: "this is bad!", value: 10)
      )
      |> Ash.read!()
    end
  end

  test "exceptions in calculations are treated as regular Ash exceptions" do
    Post
    |> Ash.Changeset.for_create(:create, %{title: "title"})
    |> Ash.create!()

    assert_raise Ash.Error.Invalid, ~r/this is bad!/, fn ->
      Post
      |> Ash.Query.calculate(
        :test,
        :string,
        expr(error(Ash.Error.Query.InvalidFilterValue, message: "this is bad!", value: 10))
      )
      |> Ash.read!()
      |> Enum.map(& &1.calculations)
    end
  end

  test "exceptions in calculations are treated as regular Ash exceptions in transactions" do
    Post
    |> Ash.Changeset.for_create(:create, %{title: "title"})
    |> Ash.create!()

    assert_raise Ash.Error.Invalid, ~r/this is bad!/, fn ->
      AshPostgres.TestRepo.transaction!(fn ->
        Post
        |> Ash.Query.calculate(
          :test,
          :string,
          expr(error(Ash.Error.Query.InvalidFilterValue, message: "this is bad!", value: 10))
        )
        |> Ash.read!()
        |> Enum.map(& &1.calculations)
      end)
    end
  end

  # On PostgreSQL 17+ upserts run as a MERGE whose WHEN MATCHED condition is rendered from a
  # query separate from the SET clause. The savepoint that turns a raised expression into a
  # regular Ash error (rather than a raw Postgrex error that aborts the transaction) must
  # account for that condition query too, not just the SET clause.
  @tag :postgres_17
  test "exceptions raised by an upsert condition are treated as regular Ash exceptions" do
    id = Ash.UUID.generate()

    Post
    |> Ash.Changeset.for_create(:create, %{id: id, title: "title"})
    |> Ash.create!()

    result =
      Ash.bulk_create(
        [%{id: id, title: "title2"}],
        Post,
        :create,
        upsert?: true,
        upsert_fields: [:title],
        upsert_condition:
          expr(error(Ash.Error.Query.InvalidFilterValue, message: "this is bad!", value: 10)),
        return_errors?: true
      )

    assert %Ash.BulkResult{status: :error, errors: [error]} = result
    assert Exception.message(error) =~ "this is bad!"

    # The connection is still usable afterwards rather than left in an aborted-transaction state.
    assert Ash.count!(Post) == 1
  end
end
