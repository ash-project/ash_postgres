defmodule AshPostgres.FilterTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Api, Comment, Post}

  require Ash.Query

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
        |> Ash.Query.filter(title == "title")
        |> Api.read!()

      assert [] = results
    end

    test "with data that matches" do
      Post
      |> Ash.Changeset.new(%{title: "title"})
      |> Api.create!()

      results =
        Post
        |> Ash.Query.filter(title == "title")
        |> Api.read!()

      assert [%Post{title: "title"}] = results
    end

    test "with some data that matches and some data that doesnt" do
      Post
      |> Ash.Changeset.new(%{title: "title"})
      |> Api.create!()

      results =
        Post
        |> Ash.Query.filter(title == "no_title")
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
        |> Ash.Query.filter(comments.title == "match")
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
        |> Ash.Query.filter(comments.title == "match")
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
        |> Ash.Query.filter(comments.title == "match")
        |> Api.read!()

      assert [%Post{title: "title"}] = results
    end
  end

  describe "in" do
    test "it properly filters" do
      Post
      |> Ash.Changeset.new(%{title: "title"})
      |> Api.create!()

      Post
      |> Ash.Changeset.new(%{title: "title1"})
      |> Api.create!()

      Post
      |> Ash.Changeset.new(%{title: "title2"})
      |> Api.create!()

      assert [%Post{title: "title1"}, %Post{title: "title2"}] =
               Post
               |> Ash.Query.filter(title in ["title1", "title2"])
               |> Ash.Query.sort(title: :asc)
               |> Api.read!()
    end
  end

  describe "with a boolean filter applied" do
    test "with no data" do
      results =
        Post
        |> Ash.Query.filter(title == "title" or score == 1)
        |> Api.read!()

      assert [] = results
    end

    test "with data that doesn't match" do
      Post
      |> Ash.Changeset.new(%{title: "no title", score: 2})
      |> Api.create!()

      results =
        Post
        |> Ash.Query.filter(title == "title" or score == 1)
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
        |> Ash.Query.filter(title == "title" or score == 1)
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
        |> Ash.Query.filter(title == "title" or score == 1)
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
        |> Ash.Query.filter(title == "match" or comments.title == "match")
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
        |> Ash.Query.filter(title == "match" or comments.title == "match")
        |> Api.read!()

      assert [%Post{title: "match"}] = results
    end

    test "with related data and an inner join condition" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "match"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "match"})
      |> Ash.Changeset.replace_relationship(:post, post)
      |> Api.create!()

      results =
        Post
        |> Ash.Query.filter(title == comments.title)
        |> Api.read!()

      assert [%Post{title: "match"}] = results

      results =
        Post
        |> Ash.Query.filter(title != comments.title)
        |> Api.read!()

      assert [] = results
    end
  end

  describe "basic expressions" do
    test "basic expressions work" do
      Post
      |> Ash.Changeset.new(%{title: "match", score: 4})
      |> Api.create!()

      Post
      |> Ash.Changeset.new(%{title: "non_match", score: 2})
      |> Api.create!()

      assert [%{title: "match"}] =
               Post
               |> Ash.Query.filter(score + 1 == 5)
               |> Api.read!()
    end
  end

  describe "case insensitive fields" do
    test "it matches case insensitively" do
      Post
      |> Ash.Changeset.new(%{title: "match", category: "FoObAr"})
      |> Api.create!()

      Post
      |> Ash.Changeset.new(%{category: "bazbuz"})
      |> Api.create!()

      assert [%{title: "match"}] =
               Post
               |> Ash.Query.filter(category == "fOoBaR")
               |> Api.read!()
    end
  end

  describe "contains/2" do
    test "it works when it matches" do
      Post
      |> Ash.Changeset.new(%{title: "match"})
      |> Api.create!()

      Post
      |> Ash.Changeset.new(%{title: "bazbuz"})
      |> Api.create!()

      assert [%{title: "match"}] =
               Post
               |> Ash.Query.filter(contains(title, "atc"))
               |> Api.read!()
    end

    test "it works when a case insensitive string is provided as a value" do
      Post
      |> Ash.Changeset.new(%{title: "match"})
      |> Api.create!()

      Post
      |> Ash.Changeset.new(%{title: "bazbuz"})
      |> Api.create!()

      assert [%{title: "match"}] =
               Post
               |> Ash.Query.filter(contains(title, ^%Ash.CiString{string: "ATC"}))
               |> Api.read!()
    end

    test "it works on a case insensitive column" do
      Post
      |> Ash.Changeset.new(%{category: "match"})
      |> Api.create!()

      Post
      |> Ash.Changeset.new(%{category: "bazbuz"})
      |> Api.create!()

      assert [%{category: %Ash.CiString{string: "match"}}] =
               Post
               |> Ash.Query.filter(contains(category, ^"ATC"))
               |> Api.read!()
    end
  end

  describe "atom filters" do
    test "it works on matches" do
      Post
      |> Ash.Changeset.new(%{title: "match"})
      |> Api.create!()

      result =
        Post
        |> Ash.Query.filter(type == :sponsored)
        |> Api.read!()

      assert [%Post{title: "match"}] = result
    end
  end

  describe "trigram_similarity" do
    test "it works on matches" do
      Post
      |> Ash.Changeset.new(%{title: "match"})
      |> Api.create!()

      results =
        Post
        |> Ash.Query.filter(trigram_similarity(title, "match") > 0.9)
        |> Api.read!()

      assert [%Post{title: "match"}] = results
    end

    test "it works on non-matches" do
      Post
      |> Ash.Changeset.new(%{title: "match"})
      |> Api.create!()

      results =
        Post
        |> Ash.Query.filter(trigram_similarity(title, "match") < 0.1)
        |> Api.read!()

      assert [] = results
    end
  end

  describe "fragments" do
    test "double replacement works" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "match", score: 4})
        |> Api.create!()

      Post
      |> Ash.Changeset.new(%{title: "non_match", score: 2})
      |> Api.create!()

      assert [%{title: "match"}] =
               Post
               |> Ash.Query.filter(fragment("? = ?", title, ^post.title))
               |> Api.read!()

      assert [] =
               Post
               |> Ash.Query.filter(fragment("? = ?", title, "nope"))
               |> Api.read!()
    end
  end
end
