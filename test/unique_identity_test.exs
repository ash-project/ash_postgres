# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.UniqueIdentityTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Organization
  alias AshPostgres.Test.Post
  alias AshPostgres.Test.Rating

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

  test "unique constraint field names are set when the index is renamed" do
    attrs = %{name: "Acme", external_id: "ext-1"}

    Organization
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create!()

    assert {:error, %Ash.Error.Invalid{errors: [invalid_attribute]}} =
             Organization
             |> Ash.Changeset.for_create(:create, attrs)
             |> Ash.create()

    assert %Ash.Error.Changes.InvalidAttribute{
             field: :external_id,
             private_vars: private_vars
           } = invalid_attribute

    assert private_vars[:constraint] == "orgs_name_external_id_index"
  end

  test "unique constraint field names are set when the repo matches the index by regex" do
    Organization
    |> Ash.Changeset.for_create(:create, %{name: "Acme", external_ref: "ref-1"})
    |> Ash.create!()

    assert {:error, %Ash.Error.Invalid{errors: [invalid_attribute]}} =
             Organization
             |> Ash.Changeset.for_create(:create, %{name: "Acme", external_ref: "ref-1"})
             |> Ash.create()

    assert %Ash.Error.Changes.InvalidAttribute{
             field: :external_ref,
             private_vars: private_vars
           } = invalid_attribute

    assert private_vars[:constraint] == "orgs_unique_external_ref_index"
  end

  test "unique constraint field names are set on a polymorphic resource's table" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title"})
      |> Ash.create!()

    create_rating = fn ->
      Rating
      |> Ash.Changeset.for_create(:create, %{score: 5, resource_id: post.id, external_id: "ext-1"})
      |> Ash.Changeset.set_context(%{data_layer: %{table: "post_ratings"}})
      |> Ash.create()
    end

    assert {:ok, _} = create_rating.()
    assert {:error, %Ash.Error.Invalid{errors: [invalid_attribute]}} = create_rating.()

    assert %Ash.Error.Changes.InvalidAttribute{
             field: :external_id,
             private_vars: private_vars
           } = invalid_attribute

    assert private_vars[:constraint] == "post_ratings_unique_external_id_index"
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

  test "upsert on a calculation-backed identity matches via the calculation expression" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title", uniq_on_upper: "foo"})
      |> Ash.create!()

    upserted =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title2", uniq_on_upper: "FOO"})
      |> Ash.create!(upsert?: true, upsert_identity: :uniq_on_upper, upsert_fields: [:title])

    # "foo" and "FOO" collide under UPPER(...), so this updates the existing row rather than inserting.
    assert upserted.id == post.id
    assert upserted.title == "title2"
    assert Ash.Resource.get_metadata(upserted, :upsert_action) == :update
  end
end
