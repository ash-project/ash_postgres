defmodule AshPostgres.EnumTest do
  @moduledoc false
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Api, Post}

  require Ash.Query

  test "valid values are properly inserted" do
    Post
    |> Ash.Changeset.new(%{title: "title", status: :open})
    |> Api.create!()
  end
end
