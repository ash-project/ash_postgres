# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Support.Relationships.FilterChileRelationshipByParentRelationshipTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Comment, Post}

  require Ash.Query

  describe "loading ratings of a comment filtered by a post" do
    setup do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "Post Title", score: 2})
        |> Ash.create!()

      ratings =
        for i <- [1, 2, 2, 2, 3, 4, 5] do
          %{score: i}
        end

      comment =
        Comment
        |> Ash.Changeset.for_create(:create, %{title: "Comment Title"})
        |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
        |> Ash.Changeset.manage_relationship(:ratings, ratings, type: :create)
        |> Ash.create!()

      [post: post, comment: comment]
    end

    test "it can load the ratings_with_same_score_as_post relationship", %{
      comment: comment
    } do
      comment = Ash.load!(comment, :ratings_with_same_score_as_post)

      ratings = comment.ratings_with_same_score_as_post

      assert Enum.count(ratings) == 3
      assert Enum.all?(ratings, &(&1.score == 2))
    end
  end
end
