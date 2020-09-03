defmodule AshPostgres.FilterTest do
  use AshPostgres.RepoCase

  defmodule Post do
    use Ash.Resource,
      data_layer: AshPostgres.DataLayer

    postgres do
      table "posts"
      repo AshPostgres.TestRepo
    end

    actions do
      read(:read)
      create(:create)
    end

    attributes do
      attribute(:id, :uuid, primary_key?: true, default: &Ecto.UUID.generate/0)
      attribute(:title, :string)
      attribute(:score, :integer)
      attribute(:public, :boolean)
    end

    relationships do
      has_many(:comments, AshPostgres.FilterTest.Comment, destination_field: :post_id)
    end
  end

  defmodule Comment do
    use Ash.Resource,
      data_layer: AshPostgres.DataLayer

    postgres do
      table "comments"
      repo AshPostgres.TestRepo
    end

    actions do
      read(:read)
      create(:create)
    end

    attributes do
      attribute(:id, :uuid, primary_key?: true, default: &Ecto.UUID.generate/0)
      attribute(:title, :string)
    end

    relationships do
      belongs_to(:post, Post)
    end
  end

  defmodule Api do
    use Ash.Api

    resources do
      resource(Post)
      resource(Comment)
    end
  end

  describe "with no filter applied" do
    test "with no data" do
      assert [] = Api.read!(Post)
    end

    test "with data" do
      Post
      |> Ash.Changeset.new(%{title: "title"})
      |> Api.create!()

      assert [%Post{title: "title"}] = Api.read!(Post)
    end
  end

  describe "with a simple filter applied" do
    test "with no data" do
      results =
        Post
        |> Ash.Query.filter(title: "title")
        |> Api.read!()

      assert [] = results
    end

    test "with data that matches" do
      Post
      |> Ash.Changeset.new(%{title: "title"})
      |> Api.create!()

      results =
        Post
        |> Ash.Query.filter(title: "title")
        |> Api.read!()

      assert [%Post{title: "title"}] = results
    end

    test "with some data that matches and some data that doesnt" do
      Post
      |> Ash.Changeset.new(%{title: "title"})
      |> Api.create!()

      results =
        Post
        |> Ash.Query.filter(title: "no_title")
        |> Api.read!()

      assert [] = results
    end

    test "with related data that doesn't match" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "not match"})
      |> Ash.Changeset.replace_relationship(:post, post)
      |> Api.create!()

      results =
        Post
        |> Ash.Query.filter(comments: [title: "match"])
        |> Api.read!()

      assert [] = results
    end

    test "with related data that does match" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "match"})
      |> Ash.Changeset.replace_relationship(:post, post)
      |> Api.create!()

      results =
        Post
        |> Ash.Query.filter(comments: [title: "match"])
        |> Api.read!()

      assert [%Post{title: "title"}] = results
    end

    test "with related data that does and doesn't match" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "match"})
      |> Ash.Changeset.replace_relationship(:post, post)
      |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "not match"})
      |> Ash.Changeset.replace_relationship(:post, post)
      |> Api.create!()

      results =
        Post
        |> Ash.Query.filter(comments: [title: "match"])
        |> Api.read!()

      assert [%Post{title: "title"}] = results
    end
  end

  describe "with a boolean filter applied" do
    test "with no data" do
      results =
        Post
        |> Ash.Query.filter(or: [[title: "title"], [score: 1]])
        |> Api.read!()

      assert [] = results
    end

    test "with data that doesn't match" do
      Post
      |> Ash.Changeset.new(%{title: "no title", score: 2})
      |> Api.create!()

      results =
        Post
        |> Ash.Query.filter(or: [[title: "title"], [score: 1]])
        |> Api.read!()

      assert [] = results
    end

    test "with data that matches both conditions" do
      Post
      |> Ash.Changeset.new(%{title: "title", score: 0})
      |> Api.create!()

      Post
      |> Ash.Changeset.new(%{score: 1, title: "nothing"})
      |> Api.create!()

      results =
        Post
        |> Ash.Query.filter(or: [[title: "title"], [score: 1]])
        |> Api.read!()
        |> Enum.sort_by(& &1.score)

      assert [%Post{title: "title", score: 0}, %Post{title: "nothing", score: 1}] = results
    end

    test "with data that matches one condition and data that matches nothing" do
      Post
      |> Ash.Changeset.new(%{title: "title", score: 0})
      |> Api.create!()

      Post
      |> Ash.Changeset.new(%{score: 2, title: "nothing"})
      |> Api.create!()

      results =
        Post
        |> Ash.Query.filter(or: [[title: "title"], [score: 1]])
        |> Api.read!()
        |> Enum.sort_by(& &1.score)

      assert [%Post{title: "title", score: 0}] = results
    end

    test "with related data in an or statement that matches, while basic filter doesn't match" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "doesn't match"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "match"})
      |> Ash.Changeset.replace_relationship(:post, post)
      |> Api.create!()

      results =
        Post
        |> Ash.Query.filter(or: [[title: "match"], [comments: [title: "match"]]])
        |> Api.read!()

      assert [%Post{title: "doesn't match"}] = results
    end

    test "with related data in an or statement that doesn't match, while basic filter does match" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "match"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "doesn't match"})
      |> Ash.Changeset.replace_relationship(:post, post)
      |> Api.create!()

      results =
        Post
        |> Ash.Query.filter(or: [[title: "match"], [comments: [title: "match"]]])
        |> Api.read!()

      assert [%Post{title: "match"}] = results
    end
  end
end
