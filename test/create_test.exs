defmodule AshPostgres.CreateTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Post

  test "seeding data works" do
    Ash.Seed.seed!(%Post{title: "fred"})
  end

  test "creates insert" do
    assert {:ok, %Post{}} =
             Post
             |> Ash.Changeset.for_create(:create, %{title: "fred"})
             |> Ash.create()

    assert [%{title: "fred"}] =
             Post
             |> Ash.Query.sort(:title)
             |> Ash.read!()
  end

  test "upserts entry" do
    assert {:ok, %Post{id: id}} =
             Post
             |> Ash.Changeset.for_create(:create, %{
               title: "fredfoo",
               uniq_if_contains_foo: "foo",
               price: 10
             })
             |> Ash.create()

    assert {:ok, %Post{id: ^id, price: 20}} =
             Post
             |> Ash.Changeset.for_create(:upsert_with_filter, %{
               title: "fredfoo",
               uniq_if_contains_foo: "foo",
               price: 20
             })
             |> Ash.create()
  end

  test "skips upsert with filter" do
    assert {:ok, %Post{id: id}} =
             Post
             |> Ash.Changeset.for_create(:create, %{
               title: "fredfoo",
               uniq_if_contains_foo: "foo",
               price: 10
             })
             |> Ash.create()

    assert {:ok, %Post{id: ^id} = post} =
             Post
             |> Ash.Changeset.for_create(:upsert_with_filter, %{
               title: "fredfoo",
               uniq_if_contains_foo: "foo",
               price: 10
             })
             |> Ash.create(return_skipped_upsert?: true)

    assert Ash.Resource.get_metadata(post, :upsert_skipped)
  end
end
