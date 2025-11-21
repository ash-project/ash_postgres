# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.ComplexCalculationTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Comment, Post}
  require Ash.Query

  describe "complex calculations with filtered aggregates" do
    test "estimated_reading_time calculation works with filtered aggregates and pagination" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{
          title: "Test Post",
          base_reading_time: 0
        })
        |> Ash.create!()

      for i <- 1..3 do
        Comment
        |> Ash.Changeset.for_create(:create, %{
          post_id: post.id,
          reading_time: 30 + i * 10,
          status: :published
        })
        |> Ash.create!()
      end

      query_opts = [
        load: [:published_comments, :estimated_reading_time],
        page: [limit: 5]
      ]

      page_result =
        Ash.Query.filter(Post, id == ^post.id)
        |> Ash.read!(query_opts)

      [post] = page_result.results

      assert post.estimated_reading_time == 150
      assert post.published_comments == 3
    end

    test "estimated_reading_time works when loaded independently (control test)" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{
          title: "Control Test",
          base_reading_time: 0
        })
        |> Ash.create!()

      for i <- 1..3 do
        Comment
        |> Ash.Changeset.for_create(:create, %{
          post_id: post.id,
          reading_time: 30 + i * 10,
          status: :published
        })
        |> Ash.create!()
      end

      [post] =
        Ash.Query.filter(Post, id == ^post.id)
        |> Ash.read!(load: [:estimated_reading_time])

      assert post.estimated_reading_time == 150
    end
  end
end
