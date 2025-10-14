# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.ConstraintTest do
  @moduledoc false
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Post

  require Ash.Query

  test "constraint messages are properly raised" do
    assert_raise Ash.Error.Invalid, ~r/yo, bad price/, fn ->
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title", price: -1})
      |> Ash.create!()
    end
  end
end
