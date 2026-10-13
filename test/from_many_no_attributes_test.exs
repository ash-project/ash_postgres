# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.FromManyNoAttributesTest do
  @moduledoc """
  A `has_one` that is both `no_attributes?` and `from_many?` has no join
  condition to narrow it down, so its sort and the implied `LIMIT 1` are the
  only things that make it resolve to a single row.

  See https://github.com/ash-project/ash_postgres/issues/239.

  The newest comment always belongs to a different post than the one being
  loaded, so an implementation that quietly joins on `post_id` cannot pass.
  """
  use AshPostgres.RepoCase, async: false

  require Ash.Query

  alias AshPostgres.Test.Comment
  alias AshPostgres.Test.Post

  defp comment_on(post, title, created_at) do
    Comment
    |> Ash.Changeset.for_create(:create, %{
      title: title,
      post_id: post.id,
      created_at: created_at
    })
    |> Ash.create!()
  end

  setup do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "post"})
      |> Ash.create!()

    other_post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "other post"})
      |> Ash.create!()

    oldest = comment_on(post, "oldest", ~U[2024-01-01 00:00:00Z])
    middle = comment_on(post, "middle", ~U[2024-03-01 00:00:00Z])
    newest = comment_on(other_post, "newest", ~U[2024-06-01 00:00:00Z])

    %{post: post, other_post: other_post, oldest: oldest, middle: middle, newest: newest}
  end

  defp post_ids(posts), do: posts |> Enum.map(& &1.id) |> Enum.sort()

  test "loading the relationship on a record returns only the first sorted row", %{
    post: post,
    newest: newest
  } do
    loaded = Ash.load!(post, :latest_comment_anywhere)

    assert %Comment{} = loaded.latest_comment_anywhere
    assert loaded.latest_comment_anywhere.id == newest.id
  end

  test "loading the relationship on several records gives each the same single row", %{
    post: post,
    other_post: other_post,
    newest: newest
  } do
    loaded = Ash.load!([post, other_post], :latest_comment_anywhere)

    assert length(loaded) == 2

    for record <- loaded do
      assert %Comment{} = record.latest_comment_anywhere
      assert record.latest_comment_anywhere.id == newest.id
    end
  end

  test "loading the relationship as part of a read returns only the first sorted row", %{
    newest: newest
  } do
    loaded =
      Post
      |> Ash.Query.load(:latest_comment_anywhere)
      |> Ash.read!()

    assert length(loaded) == 2

    for record <- loaded do
      assert %Comment{} = record.latest_comment_anywhere
      assert record.latest_comment_anywhere.id == newest.id
    end
  end

  test "the relationship is nil rather than an empty list when nothing is related" do
    Comment
    |> Ash.read!()
    |> Enum.each(&Ash.destroy!/1)

    assert [_, _] =
             loaded =
             Post
             |> Ash.Query.load(:latest_comment_anywhere)
             |> Ash.read!()

    for record <- loaded do
      assert is_nil(record.latest_comment_anywhere)
    end
  end

  test "filtering through the relationship only considers the first sorted row", %{
    post: post,
    other_post: other_post,
    oldest: oldest,
    middle: middle,
    newest: newest
  } do
    for not_first <- [oldest, middle] do
      assert [] =
               Post
               |> Ash.Query.filter(latest_comment_anywhere.id == ^not_first.id)
               |> Ash.read!()
    end

    assert Post
           |> Ash.Query.filter(latest_comment_anywhere.id == ^newest.id)
           |> Ash.read!()
           |> post_ids() == post_ids([post, other_post])
  end

  test "exists through the relationship only considers the first sorted row", %{
    post: post,
    other_post: other_post,
    oldest: oldest,
    middle: middle,
    newest: newest
  } do
    for not_first <- [oldest, middle] do
      assert [] =
               Post
               |> Ash.Query.filter(exists(latest_comment_anywhere, id == ^not_first.id))
               |> Ash.read!()
    end

    assert Post
           |> Ash.Query.filter(exists(latest_comment_anywhere, id == ^newest.id))
           |> Ash.read!()
           |> post_ids() == post_ids([post, other_post])
  end

  test "the attribute-based equivalent resolves per record on the same data", %{
    post: post,
    other_post: other_post,
    middle: middle,
    newest: newest
  } do
    assert %{latest_comment: %Comment{id: post_latest}} = Ash.load!(post, :latest_comment)
    assert post_latest == middle.id

    assert %{latest_comment: %Comment{id: other_latest}} =
             Ash.load!(other_post, :latest_comment)

    assert other_latest == newest.id
  end
end
