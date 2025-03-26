defmodule AshPostgres.UnionTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Author, Comment, Organization, Post, PostLink}
  alias AshPostgres.Test.ComplexCalculations.{Channel, ChannelMember}

  require Ash.Query
  import Ash.Expr

  test "with no data" do
    Post
    |> Ash.Query.for_read(:first_and_last_post)
    |> Ash.read!()
  end

  test "with data" do
    Post
    |> Ash.Changeset.for_create(:create, %{title: "title1"})
    |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{title: "title2"})
    |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{title: "title3"})
    |> Ash.create!()

    assert [%{title: "title1"}, %{title: "title3"}] =
             Post
             |> Ash.Query.for_read(:first_and_last_post)
             |> Ash.read!()
  end

  test "with data and sort" do
    Post
    |> Ash.Changeset.for_create(:create, %{title: "title1"})
    |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{title: "title2"})
    |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{title: "title3"})
    |> Ash.create!()

    assert [%{title: "title3"}, %{title: "title1"}] =
             Post
             |> Ash.Query.for_read(:first_and_last_post)
             |> Ash.Query.sort(title: :desc)
             |> Ash.read!()
  end
end
