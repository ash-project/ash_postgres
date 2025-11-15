defmodule AshPostgres.Test.ComplexCalculationTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Comment, Post}
  require Ash.Query

  describe "complex calculations with filtered aggregates" do
    test "estimated_reading_time calculation works with filtered aggregates and pagination" do
      # Setup test data - create post with comments to test complex calculation
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{
          title: "Test Post",
          base_reading_time: 0  # Set to 0 so COALESCE finds a value
        })
        |> Ash.create!()

      # Add comments with reading time data and status to test aggregates
      for i <- 1..3 do
        Comment
        |> Ash.Changeset.for_create(:create, %{
          post_id: post.id,
          reading_time: 30 + i * 10,  # 40, 50, 60 - total reading time = 150
          status: :published  # This triggers the published_comments count aggregate
        })
        |> Ash.create!()
      end

      # Test complex calculation pattern:
      # 1. published_comments is a count aggregate with filter
      # 2. estimated_reading_time is a calculation that depends on filtered sum aggregates
      # 3. Loading them together with keyset pagination should work correctly
      query_opts = [
        load: [:published_comments, :estimated_reading_time],
        page: [limit: 5]  # keyset pagination
      ]

      page_result =
        Ash.Query.filter(Post, id == ^post.id)
        |> Ash.read!(query_opts)

      [post] = page_result.results

      # Verify calculation works correctly with complex aggregates
      assert post.estimated_reading_time == 150
      assert post.published_comments == 3
    end

    test "estimated_reading_time works when loaded independently (control test)" do
      # Control test - same data, but load calculation alone
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{
          title: "Control Test",
          base_reading_time: 0  # Set to 0 so COALESCE finds a value
        })
        |> Ash.create!()

      for i <- 1..3 do
        Comment
        |> Ash.Changeset.for_create(:create, %{
          post_id: post.id,
          reading_time: 30 + i * 10,  # total = 150
          status: :published
        })
        |> Ash.create!()
      end

      # Loading calculation alone should work fine
      [post] =
        Ash.Query.filter(Post, id == ^post.id)
        |> Ash.read!(load: [:estimated_reading_time])

      # This should work and return 150
      assert post.estimated_reading_time == 150
    end
  end
end