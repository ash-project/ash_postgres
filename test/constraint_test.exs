defmodule AshPostgres.ConstraintTest do
  @moduledoc false
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Api, Post}

  require Ash.Query

  test "constraint messages are properly raised" do
    assert_raise Ash.Error.Invalid, ~r/yo, bad price/, fn ->
      Post
      |> Ash.Changeset.new(%{title: "title", price: -1})
      |> Api.create!()
    end
  end
end
