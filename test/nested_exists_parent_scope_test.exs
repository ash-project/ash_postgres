# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.NestedExistsParentScopeTest do
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.{Author, Post}

  require Ash.Query

  describe "nested exists with calculation containing parent() inside unrelated exists" do
    test "parent() references in a calculation are scoped to the calculation's own resource, not the outer exists" do
      # Setup: Author "Alice" with a post titled "Alice"
      # The post's `has_matching_author_by_unrelated_exists` calculation checks:
      #   exists(Author, first_name == parent(title))
      # When used standalone on the post, parent(title) refers to Post.title — works fine.
      #
      # Author's `has_post_matching_author_via_nested_exists` calculation checks:
      #   exists(posts, has_matching_author_by_unrelated_exists)
      # This inlines the Post calculation. The bug: parent(title) gets scoped to
      # Author instead of Post, generating SQL like `authors.title` which doesn't exist.

      author =
        Author
        |> Ash.Changeset.for_create(:create, %{first_name: "Alice"})
        |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "Alice", author_id: author.id})
      |> Ash.create!()

      # This should work: the post titled "Alice" matches the author named "Alice"
      assert %{has_post_matching_author_via_nested_exists: true} =
               Ash.load!(author, [:has_post_matching_author_via_nested_exists])
    end

    test "the inner calculation works correctly when loaded directly on the child resource" do
      # Sanity check: the Post calculation works fine when not nested
      author =
        Author
        |> Ash.Changeset.for_create(:create, %{first_name: "Bob"})
        |> Ash.create!()

      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "Bob", author_id: author.id})
        |> Ash.create!()

      assert %{has_matching_author_by_unrelated_exists: true} =
               Ash.load!(post, [:has_matching_author_by_unrelated_exists])
    end
  end
end
