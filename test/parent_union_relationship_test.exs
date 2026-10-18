defmodule AshPostgres.ParentUnionRelationshipTest do
  use AshPostgres.RepoCase, async: false
  require Ash.Query
  alias AshPostgres.Test.{Author, Comment, Organization, Post, PostLink, User}

  setup do
    org = Ash.Seed.seed!(Organization, %{name: "org"})
    user = Ash.Seed.seed!(User, %{organization_id: org.id})
    alice = Ash.Seed.seed!(Author, %{first_name: "Alice"})
    bob = Ash.Seed.seed!(Author, %{first_name: "Bob"})

    post = Ash.Seed.seed!(Post, %{title: "main", organization_id: org.id, author_id: bob.id})
    linked = Ash.Seed.seed!(Post, %{title: "linked", organization_id: org.id})
    Ash.Seed.seed!(PostLink, %{source_post_id: post.id, destination_post_id: linked.id})

    # interleaved sort values across the two parent paths
    for {title, post_id} <- [{"a", post.id}, {"c", post.id}, {"b", linked.id}] do
      Ash.Seed.seed!(Comment, %{title: title, post_id: post_id, author_id: alice.id})
    end

    %{post: post, user: user, bob: bob}
  end

  defp load!(post, load, opts \\ [authorize?: false]) do
    Post
    |> Ash.Query.filter(id == ^post.id)
    |> Ash.read_one!(Keyword.put(opts, :load, load))
  end

  defp titles(post, relationship) do
    post |> load!(relationship) |> Map.get(relationship) |> Enum.map(& &1.title)
  end

  test "sorted union of parent to-many paths has no duplicates", %{post: post} do
    assert ["a", "b", "c"] == titles(post, :union_comments)
  end

  test "load query filters on the destination's relationships still apply to the destination", %{
    post: post
  } do
    query = Comment |> Ash.Query.filter(author.first_name == "Alice")

    assert ["a", "b", "c"] ==
             post
             |> load!(union_comments: query)
             |> Map.get(:union_comments)
             |> Enum.map(& &1.title)
  end

  test "destination read policies still apply to the destination", %{post: post, user: user} do
    assert ["a", "b", "c"] ==
             post
             |> load!(:union_comments, actor: user, authorize?: true)
             |> Map.get(:union_comments)
             |> Enum.map(& &1.title)
  end

  test "aggregates over the union are correct", %{post: post} do
    post = load!(post, [:count_of_union_comments, :union_comment_titles])

    assert post.count_of_union_comments == 3
    assert Enum.sort(post.union_comment_titles) == ["a", "b", "c"]
  end

  test "union combined with a parent to-one ref", %{post: post} do
    assert ["a", "b", "c"] == titles(post, :union_comments_with_parent_author)
  end

  test "parent to-many paths combined with and", %{post: post} do
    assert ["a", "c"] == titles(post, :comments_with_two_parent_paths)
  end

  test "destination relationship refs inside the union resolve against the destination", %{
    post: post
  } do
    assert ["a", "b", "c"] == titles(post, :union_comments_with_destination_ref)
  end

  test "single parent to-many path with a non-key predicate has no duplicates", %{post: post} do
    assert ["a", "c"] == titles(post, :own_comments_titled_at_most)
  end

  test "exists through the union" do
    assert ["linked", "main"] ==
             Post
             |> Ash.Query.filter(exists(union_comments, title == "b"))
             |> Ash.read!()
             |> Enum.map(& &1.title)
             |> Enum.sort()
  end

  test "ref through the union" do
    assert ["main"] ==
             Post
             |> Ash.Query.filter(union_comments.title == "c")
             |> Ash.read!()
             |> Enum.map(& &1.title)
  end

  test "exists through the union at a nested path", %{bob: bob} do
    assert [%{id: id}] =
             Author |> Ash.Query.filter(exists(posts.union_comments, title == "b")) |> Ash.read!()

    assert id == bob.id
  end

  test "aggregate over the union at a nested path", %{bob: bob} do
    author =
      Author
      |> Ash.Query.filter(id == ^bob.id)
      |> Ash.Query.aggregate(:count, :count, [:posts, :union_comments_unsorted])
      |> Ash.read_one!()

    assert author.aggregates.count == 3
  end
end
