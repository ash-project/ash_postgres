# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.RefCastTypmodTest do
  @moduledoc """
  `:utc_datetime` columns are migrated as `timestamp(0)`, but ref casts used
  to render as bare `::timestamp`. That typmod-changing cast survives
  postgres' parser, so predicates like `(col)::timestamp IS NULL` could not
  be matched against partial indexes declared with `WHERE col IS NULL`.

  Refs must cast to the typmod-accurate type (`::timestamp(0)`), which the
  parser deletes as an identity cast, leaving the bare column in the parse
  tree.
  """
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.Message

  require Ash.Query

  defp to_sql(query) do
    {sql, _vars} =
      query
      |> Ash.data_layer_query!()
      |> Map.get(:query)
      |> then(&AshPostgres.TestRepo.to_sql(:all, &1))

    sql
  end

  defp explain(query) do
    query
    |> Ash.data_layer_query!()
    |> Map.get(:query)
    |> then(&AshPostgres.TestRepo.explain(:all, &1))
  end

  test "is_nil on a utc_datetime ref casts with the column's typmod" do
    sql =
      Message
      |> Ash.Query.filter(is_nil(read_at))
      |> to_sql()

    assert sql =~ ~s[m0."read_at"::timestamp(0)]
    refute sql =~ ~r/"read_at"::timestamp(?!\()/
  end

  test "comparisons on a utc_datetime ref cast with the column's typmod" do
    sql =
      Message
      |> Ash.Query.filter(read_at > ^DateTime.utc_now())
      |> to_sql()

    assert sql =~ ~s[m0."read_at"::timestamp(0)]
    refute sql =~ ~r/"read_at"::timestamp(?!\()/
  end

  test "the identity cast is deleted by the parser, leaving the bare column" do
    # The plan must show the bare column (`read_at IS NULL`), not a coercion
    # (`(read_at)::timestamp ...`) — the bare column is what partial-index
    # predicate proving and expression-index matching operate on.
    plan =
      Message
      |> Ash.Query.filter(is_nil(read_at))
      |> explain()

    assert plan =~ "read_at IS NULL"
    refute plan =~ "::timestamp"
  end
end
