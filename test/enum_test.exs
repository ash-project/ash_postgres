defmodule AshPostgres.EnumTest do
  @moduledoc false
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Post

  require Ash.Query

  test "valid values are properly inserted" do
    Post
    |> Ash.Changeset.new(%{title: "title", status: :open})
    |> Ash.create!()
  end
end
