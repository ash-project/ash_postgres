defmodule AshPostgres.Test.UniqueIdentityTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Post

  require Ash.Query

  test "unique constraint errors are properly caught" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title"})
      |> Ash.create!()

    assert_raise Ash.Error.Invalid,
                 ~r/Invalid value provided for id: has already been taken/,
                 fn ->
                   Post
                   |> Ash.Changeset.for_create(:create, %{id: post.id})
                   |> Ash.create!()
                 end
  end

  test "a unique constraint can be used to upsert when the resource has a base filter" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{
        title: "title",
        uniq_one: "fred",
        uniq_two: "astair",
        price: 10
      })
      |> Ash.create!()

    new_post =
      Post
      |> Ash.Changeset.for_create(:create, %{
        title: "title2",
        uniq_one: "fred",
        uniq_two: "astair"
      })
      |> Ash.create!(upsert?: true, upsert_identity: :uniq_one_and_two)

    assert new_post.id == post.id
    assert new_post.price == 10
  end
end
