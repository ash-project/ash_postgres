defmodule AshPostgres.EnumTest do
  @moduledoc false
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Post

  require Ash.Query

  test "valid values are properly inserted" do
    Post
    |> Ash.Changeset.for_create(:create, %{title: "title", status: :open})
    |> Ash.create!()
  end
end
