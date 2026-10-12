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

    %{post: post, user: user}
  end

  defp load!(post, load, opts \\ [authorize?: false]) do
    Post
    |> Ash.Query.filter(id == ^post.id)
    |> Ash.read_one!(Keyword.put(opts, :load, load))
  end

  test "sorted union of parent to-many paths has no duplicates", %{post: post} do
    assert ["a", "b", "c"] ==
             post |> load!(:union_comments) |> Map.get(:union_comments) |> Enum.map(& &1.title)
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
end
