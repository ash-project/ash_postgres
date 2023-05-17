defmodule AshPostgres.FilterTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Api, Author, Comment, Post}

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

  describe "citext validation" do
    setup do
      on_exit(fn ->
        Application.delete_env(:ash_postgres, :no_extensions)
      end)
    end

    test "it raises if you try to use ci_string while ci_text is not installed" do
      Application.put_env(:ash_postgres, :no_extensions, ["citext"])

      assert_raise Ash.Error.Query.InvalidExpression, fn ->
        Post
        |> Ash.Query.filter(category == "blah")
        |> Api.read!()
      end
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
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Api.create!()

      results =
        Post
        |> Ash.Query.filter(comments.title == "match")
        |> Api.read!()

      assert [] = results
    end

    test "with related data two steps away that matches" do
      author =
        Author
        |> Ash.Changeset.new(%{first_name: "match"})
        |> Api.create!()

      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
        |> Api.create!()

      Post
      |> Ash.Changeset.new(%{title: "title2"})
      |> Ash.Changeset.manage_relationship(:linked_posts, [post], type: :append_and_remove)
      |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
      |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "not match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
      |> Api.create!()

      results =
        Comment
        |> Ash.Query.filter(author.posts.linked_posts.title == "title")
        |> Api.read!()

      assert [_] = results
    end

    test "with related data that does match" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
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
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "not match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
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
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
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
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
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
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
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

  describe "accessing embeds" do
    setup do
      Author
      |> Ash.Changeset.for_create(:create,
        bio: %{title: "Dr.", bio: "Strange", years_of_experience: 10}
      )
      |> Api.create!()

      Author
      |> Ash.Changeset.for_create(:create,
        bio: %{title: "Highlander", bio: "There can be only one."}
      )
      |> Api.create!()

      :ok
    end

    test "works using simple equality" do
      assert [%{bio: %{title: "Dr."}}] =
               Author
               |> Ash.Query.filter(bio[:title] == "Dr.")
               |> Api.read!()
    end

    test "works using simple equality for integers" do
      assert [%{bio: %{title: "Dr."}}] =
               Author
               |> Ash.Query.filter(bio[:years_of_experience] == 10)
               |> Api.read!()
    end

    test "works using an expression" do
      assert [%{bio: %{title: "Highlander"}}] =
               Author
               |> Ash.Query.filter(contains(type(bio[:bio], :string), "only one."))
               |> Api.read!()
    end

    test "calculations that use embeds can be filtered on" do
      assert [%{bio: %{title: "Dr."}}] =
               Author
               |> Ash.Query.filter(title == "Dr.")
               |> Api.read!()
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

    test "it works on a case insensitive calculation" do
      Post
      |> Ash.Changeset.new(%{category: "match"})
      |> Api.create!()

      Post
      |> Ash.Changeset.new(%{category: "bazbuz"})
      |> Api.create!()

      assert [%{category: %Ash.CiString{string: "match"}}] =
               Post
               |> Ash.Query.filter(contains(category_label, ^"ATC"))
               |> Api.read!()
    end

    test "it works on related values" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "match"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "abba"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Api.create!()

      post2 =
        Post
        |> Ash.Changeset.new(%{title: "no_match"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "acca"})
      |> Ash.Changeset.manage_relationship(:post, post2, type: :append_and_remove)
      |> Api.create!()

      assert [%{title: "match"}] =
               Post
               |> Ash.Query.filter(contains(comments.title, ^"bb"))
               |> Api.read!()
    end
  end

  describe "length/1" do
    test "it works with a list attribute" do
      author1 =
        Author
        |> Ash.Changeset.new(%{badges: [:author_of_the_year]})
        |> Api.create!()

      _author2 =
        Author
        |> Ash.Changeset.new(%{badges: []})
        |> Api.create!()

      author1_id = author1.id

      assert [%{id: ^author1_id}] =
               Author
               |> Ash.Query.filter(length(badges) > 0)
               |> Api.read!()
    end

    test "it works with nil" do
      author1 =
        Author
        |> Ash.Changeset.new(%{badges: [:author_of_the_year]})
        |> Api.create!()

      _author2 =
        Author
        |> Ash.Changeset.new()
        |> Api.create!()

      author1_id = author1.id

      assert [%{id: ^author1_id}] =
               Author
               |> Ash.Query.filter(length(badges || []) > 0)
               |> Api.read!()
    end

    test "it works with a list" do
      author1 =
        Author
        |> Ash.Changeset.new()
        |> Api.create!()

      author1_id = author1.id

      explicit_list = [:foo]

      assert [%{id: ^author1_id}] =
               Author
               |> Ash.Query.filter(length(^explicit_list) > 0)
               |> Api.read!()

      assert [] =
               Author
               |> Ash.Query.filter(length(^explicit_list) > 1)
               |> Api.read!()
    end

    test "it raises with bad values" do
      Author
      |> Ash.Changeset.new()
      |> Api.create!()

      assert_raise(Ash.Error.Unknown, fn ->
        Author
        |> Ash.Query.filter(length(first_name) > 0)
        |> Api.read!()
      end)
    end
  end

  describe "exists/2" do
    test "it works with single relationships" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "match"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "abba"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Api.create!()

      post2 =
        Post
        |> Ash.Changeset.new(%{title: "no_match"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "acca"})
      |> Ash.Changeset.manage_relationship(:post, post2, type: :append_and_remove)
      |> Api.create!()

      assert [%{title: "match"}] =
               Post
               |> Ash.Query.filter(exists(comments, title == ^"abba"))
               |> Api.read!()
    end

    test "it works with many to many relationships" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "a"})
        |> Api.create!()

      Post
      |> Ash.Changeset.new(%{title: "b"})
      |> Ash.Changeset.manage_relationship(:linked_posts, [post], type: :append_and_remove)
      |> Api.create!()

      assert [%{title: "b"}] =
               Post
               |> Ash.Query.filter(exists(linked_posts, title == ^"a"))
               |> Api.read!()
    end

    test "it works with join association relationships" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "a"})
        |> Api.create!()

      Post
      |> Ash.Changeset.new(%{title: "b"})
      |> Ash.Changeset.manage_relationship(:linked_posts, [post], type: :append_and_remove)
      |> Api.create!()

      assert [%{title: "b"}] =
               Post
               |> Ash.Query.filter(exists(linked_posts, title == ^"a"))
               |> Api.read!()
    end

    test "it works with nested relationships as the path" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "a"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "comment"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Api.create!()

      Post
      |> Ash.Changeset.new(%{title: "b"})
      |> Ash.Changeset.manage_relationship(:linked_posts, [post], type: :append_and_remove)
      |> Api.create!()

      assert [%{title: "b"}] =
               Post
               |> Ash.Query.filter(exists(linked_posts.comments, title == ^"comment"))
               |> Api.read!()
    end

    test "it works with an `at_path`" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "a"})
        |> Api.create!()

      other_post =
        Post
        |> Ash.Changeset.new(%{title: "other_a"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "comment"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "comment"})
      |> Ash.Changeset.manage_relationship(:post, other_post, type: :append_and_remove)
      |> Api.create!()

      Post
      |> Ash.Changeset.new(%{title: "b"})
      |> Ash.Changeset.manage_relationship(:linked_posts, [post], type: :append_and_remove)
      |> Api.create!()

      Post
      |> Ash.Changeset.new(%{title: "b"})
      |> Ash.Changeset.manage_relationship(:linked_posts, [other_post], type: :append_and_remove)
      |> Api.create!()

      assert [%{title: "b"}] =
               Post
               |> Ash.Query.filter(
                 linked_posts.title == "a" and
                   linked_posts.exists(comments, title == ^"comment")
               )
               |> Api.read!()

      assert [%{title: "b"}] =
               Post
               |> Ash.Query.filter(
                 linked_posts.title == "a" and
                   linked_posts.exists(comments, title == ^"comment")
               )
               |> Api.read!()
    end

    test "it works with nested relationships inside of exists" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "a"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "comment"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Api.create!()

      Post
      |> Ash.Changeset.new(%{title: "b"})
      |> Ash.Changeset.manage_relationship(:linked_posts, [post], type: :append_and_remove)
      |> Api.create!()

      assert [%{title: "b"}] =
               Post
               |> Ash.Query.filter(exists(linked_posts, comments.title == ^"comment"))
               |> Api.read!()
    end

    test "it works with aggregates inside of exists" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "a", category: "foo"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "comment"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Api.create!()

      Post
      |> Ash.Changeset.new(%{title: "b"})
      |> Ash.Changeset.manage_relationship(:linked_posts, [post], type: :append_and_remove)
      |> Api.create!()

      assert [%{title: "b"}] =
               Post
               |> Ash.Query.filter(
                 exists(linked_posts.comments, title == ^"comment" and post_category == "foo")
               )
               |> Api.read!()
    end
  end

  describe "filtering on enum types" do
    test "it allows simple filtering" do
      Post
      |> Ash.Changeset.new(status_enum: "open")
      |> Api.create!()

      assert %{status_enum: :open} =
               Post
               |> Ash.Query.filter(status_enum == ^"open")
               |> Api.read_one!()
    end

    test "it allows simple filtering without casting" do
      Post
      |> Ash.Changeset.new(status_enum_no_cast: "open")
      |> Api.create!()

      assert %{status_enum_no_cast: :open} =
               Post
               |> Ash.Query.filter(status_enum_no_cast == ^"open")
               |> Api.read_one!()
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

  describe "like and ilike" do
    test "like builds and matches" do
      Post
      |> Ash.Changeset.new(%{title: "MaTcH"})
      |> Api.create!()

      results =
        Post
        |> Ash.Query.filter(like(title, "%aTc%"))
        |> Api.read!()

      assert [%Post{title: "MaTcH"}] = results

      results =
        Post
        |> Ash.Query.filter(like(title, "%atc%"))
        |> Api.read!()

      assert [] = results
    end

    test "ilike builds and matches" do
      Post
      |> Ash.Changeset.new(%{title: "MaTcH"})
      |> Api.create!()

      results =
        Post
        |> Ash.Query.filter(ilike(title, "%aTc%"))
        |> Api.read!()

      assert [%Post{title: "MaTcH"}] = results

      results =
        Post
        |> Ash.Query.filter(ilike(title, "%atc%"))
        |> Api.read!()

      assert [%Post{title: "MaTcH"}] = results
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

  test "filtering allows filtering on list aggregates with filters" do
    post =
      Post
      |> Ash.Changeset.new(%{title: "match"})
      |> Api.create!()

    post_id = post.id

    Comment
    |> Ash.Changeset.new(%{title: "match", likes: 5})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Api.create!()

    Comment
    |> Ash.Changeset.new(%{title: "non_match", likes: 5})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Api.create!()

    post2 =
      Post
      |> Ash.Changeset.new(%{title: "non_match"})
      |> Api.create!()

    Comment
    |> Ash.Changeset.new(%{title: "non_match", likes: 5})
    |> Ash.Changeset.manage_relationship(:post, post2, type: :append_and_remove)
    |> Api.create!()

    assert [%{id: ^post_id}] =
             Post
             |> Ash.Query.filter("match" in comment_titles_with_5_likes)
             |> Api.read!()
  end

  test "filtering allows filtering on count aggregates with filters" do
    post =
      Post
      |> Ash.Changeset.new(%{title: "match"})
      |> Api.create!()

    post_id = post.id

    Comment
    |> Ash.Changeset.new(%{title: "title"})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Api.create!()

    Comment
    |> Ash.Changeset.new(%{title: "title"})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Api.create!()

    post2 =
      Post
      |> Ash.Changeset.new(%{title: "non_match"})
      |> Api.create!()

    Comment
    |> Ash.Changeset.new(%{title: "title"})
    |> Ash.Changeset.manage_relationship(:post, post2, type: :append_and_remove)
    |> Api.create!()

    assert [%{id: ^post_id}] =
             Post
             |> Ash.Query.filter(count_of_comments_that_have_a_post == 2)
             |> Api.read!()
  end

  describe "filtering on relationships that themselves have filters" do
    test "it doesn't raise an error" do
      Comment
      |> Ash.Query.filter(not is_nil(popular_ratings.id))
      |> Api.read!()
    end

    test "it doesn't raise an error when nested" do
      Post
      |> Ash.Query.filter(not is_nil(comments.popular_ratings.id))
      |> Api.read!()
    end

    test "aggregates using them don't raise errors" do
      Comment
      |> Ash.Query.load(:co_popular_comments)
      |> Api.read!()
    end

    test "filtering on aggregates using them doesn't raise errors" do
      Comment
      |> Ash.Query.filter(co_popular_comments > 1)
      |> Api.read!()
    end
  end
end
