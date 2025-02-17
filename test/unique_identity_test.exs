defmodule AshPostgres.Test.UniqueIdentityTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Organization
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

  test "unique constraint field names are property set" do
    Organization
    |> Ash.Changeset.for_create(:create, %{name: "Acme", department: "Sales"})
    |> Ash.create!()

    assert {:error, %Ash.Error.Invalid{errors: [invalid_attribute]}} =
             Organization
             |> Ash.Changeset.for_create(:create, %{name: "Acme", department: "SALES"})
             |> Ash.create()

    assert %Ash.Error.Changes.InvalidAttribute{field: :department_slug} = invalid_attribute
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

  test "a unique constraint can be used to upsert when backed by a calculation" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{
        title: "title",
        uniq_if_contains_foo: "abcfoodef",
        price: 10
      })
      |> Ash.create!()

    new_post =
      Post
      |> Ash.Changeset.for_create(:create, %{
        title: "title2",
        uniq_if_contains_foo: "abcfoodef"
      })
      |> Ash.create!(upsert?: true, upsert_identity: :uniq_if_contains_foo)

    assert new_post.id == post.id
    assert new_post.price == 10
  end
end
