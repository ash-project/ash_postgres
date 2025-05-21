defmodule AshPostgres.Test.TupleTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Post

  require Ash.Query

  test "tuple type can be created with correct values" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{
        title: "Tuple Test",
        person_detail: {"John", "Doe"}
      })
      |> Ash.create!()

    assert post.person_detail == {"John", "Doe"}
    assert elem(post.person_detail, 0) == "John"
    assert elem(post.person_detail, 1) == "Doe"
  end

  test "tuple type with force_attribute_change can be updated" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{
        title: "Tuple Test",
        score: 1
      })
      |> Ash.create!()

    post = AshPostgres.Test.Domain.review!(post)

    assert post.model == {1.0, 2.0, 3.0}
  end

  test "tuple type can be filtered by exact match" do
    # Create first post
    Post
    |> Ash.Changeset.for_create(:create, %{
      title: "First Post",
      person_detail: {"John", "Doe"}
    })
    |> Ash.create!()

    # Create second post
    Post
    |> Ash.Changeset.for_create(:create, %{
      title: "Second Post",
      person_detail: {"Jane", "Smith"}
    })
    |> Ash.create!()

    # Find post with exact tuple match
    results =
      Post
      |> Ash.Query.filter(person_detail == ^{"John", "Doe"})
      |> Ash.read!()

    assert length(results) == 1
    assert hd(results).title == "First Post"
  end

  test "tuple type can be filtered by individual fields" do
    # Create posts
    Post
    |> Ash.Changeset.for_create(:create, %{
      title: "John Post 1",
      person_detail: {"John", "Doe"}
    })
    |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{
      title: "John Post 2",
      person_detail: {"John", "Smith"}
    })
    |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{
      title: "Jane Post",
      person_detail: {"Jane", "Doe"}
    })
    |> Ash.create!()

    # Filter by equality
    results =
      Post
      |> Ash.Query.filter(person_detail == {"John", "Doe"})
      |> Ash.read!()

    assert length(results) == 1

    # Filter by first_name
    results =
      Post
      |> Ash.Query.filter(person_detail["first_name"] == "John")
      |> Ash.read!()

    assert length(results) == 2
    assert Enum.all?(results, fn post -> elem(post.person_detail, 0) == "John" end)
  end

  test "tuple type can be updated" do
    # Create post
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{
        title: "Original Post",
        person_detail: {"Original", "Name"}
      })
      |> Ash.create!()

    # Update the post
    updated_post =
      post
      |> Ash.Changeset.for_update(:update, %{
        person_detail: {"Updated", "Name"}
      })
      |> Ash.update!()

    assert updated_post.person_detail == {"Updated", "Name"}

    # Verify by reading from database
    retrieved_post =
      Post
      |> Ash.Query.filter(id == ^post.id)
      |> Ash.read_one!()

    assert retrieved_post.person_detail == {"Updated", "Name"}
  end

  test "tuple type validates constraints" do
    # Try to create with empty first name (violates min_length constraint)
    assert_raise Ash.Error.Invalid, fn ->
      Post
      |> Ash.Changeset.for_create(:create, %{
        title: "Invalid Post",
        person_detail: {"", "Doe"}
      })
      |> Ash.create!()
    end

    # Try to create with empty last name (violates min_length constraint)
    assert_raise Ash.Error.Invalid, fn ->
      Post
      |> Ash.Changeset.for_create(:create, %{
        title: "Invalid Post",
        person_detail: {"John", ""}
      })
      |> Ash.create!()
    end
  end
end
