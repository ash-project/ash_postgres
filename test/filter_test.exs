defmodule AshPostgres.FilterTest do
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.{Author, Comment, Organization, Post, PostLink}
  alias AshPostgres.Test.ComplexCalculations.{Channel, ChannelMember}

  require Ash.Query
  import Ash.Expr

  describe "with no filter applied" do
    test "with no data" do
      assert [] = Ash.read!(Post)
    end

    test "with data" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title"})
      |> Ash.create!()

      assert [%Post{title: "title"}] = Ash.read!(Post)
    end
  end

  describe "type casting" do
    test "it does not do unnecessary type casting" do
      {query, vars} =
        Post
        |> Ash.Query.filter(version == ^10)
        |> Ash.data_layer_query!()
        |> Map.get(:query)
        |> then(&AshPostgres.TestRepo.to_sql(:all, &1))

      assert vars == ["sponsored", 10]

      assert String.contains?(query, "(p0.\"version\"::bigint = $2::bigint)")
    end

    test "it uses coalesce to optimize the || operator for non-booleans" do
      {query, _vars} =
        Post
        |> Ash.Query.filter((version || 10) == 20)
        |> Ash.data_layer_query!()
        |> Map.get(:query)
        |> then(&AshPostgres.TestRepo.to_sql(:all, &1))

      assert String.contains?(query, "(coalesce(p0.\"version\"::bigint, $2::bigint)")
    end

    test "it uses OR to optimize the || operator for booleans" do
      {query, _vars} =
        Post
        |> Ash.Query.filter(is_special || true)
        |> Ash.data_layer_query!()
        |> Map.get(:query)
        |> then(&AshPostgres.TestRepo.to_sql(:all, &1))

      assert String.contains?(query, "(p0.\"is_special\"::boolean OR $2::boolean)")
    end

    test "it uses AND to optimize the && operator for booleans" do
      {query, _vars} =
        Post
        |> Ash.Query.filter(is_special && public)
        |> Ash.data_layer_query!()
        |> Map.get(:query)
        |> then(&AshPostgres.TestRepo.to_sql(:all, &1))

      assert String.contains?(query, "(p0.\"is_special\"::boolean AND p0.\"public\"::boolean)")
    end
  end

  describe "ci_string argument casting" do
    test "it properly casts" do
      Post
      |> Ash.Query.for_read(:category_matches, %{category: "category"})
      |> Ash.read!()
    end
  end

  describe "invalid uuid" do
    test "with an invalid uuid, an invalid error is raised" do
      assert_raise Ash.Error.Invalid, fn ->
        Post
        |> Ash.Query.filter(id == "foo")
        |> Ash.read!()
      end
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

      assert_raise Ash.Error.Invalid, fn ->
        Post
        |> Ash.Query.filter(category == "blah")
        |> Ash.read!()
      end
    end
  end

  describe "with a simple filter applied" do
    test "with no data" do
      results =
        Post
        |> Ash.Query.filter(title == "title")
        |> Ash.read!()

      assert [] = results
    end

    test "with data that matches" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title"})
      |> Ash.create!()

      results =
        Post
        |> Ash.Query.filter(title == "title")
        |> Ash.read!()

      assert [%Post{title: "title"}] = results
    end

    test "with some data that matches and some data that doesnt" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title"})
      |> Ash.create!()

      results =
        Post
        |> Ash.Query.filter(title == "no_title")
        |> Ash.read!()

      assert [] = results
    end

    test "with related data that doesn't match" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "not match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      results =
        Post
        |> Ash.Query.filter(comments.title == "match")
        |> Ash.read!()

      assert [] = results
    end

    test "with related data two steps away that matches" do
      author =
        Author
        |> Ash.Changeset.for_create(:create, %{first_name: "match"})
        |> Ash.create!()

      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
        |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "title2"})
      |> Ash.Changeset.manage_relationship(:linked_posts, [post], type: :append_and_remove)
      |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "not match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
      |> Ash.create!()

      results =
        Comment
        |> Ash.Query.filter(author.posts.linked_posts.title == "title")
        |> Ash.read!()

      assert [_] = results
    end

    test "with related data that does match" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      results =
        Post
        |> Ash.Query.filter(comments.title == "match")
        |> Ash.read!()

      assert [%Post{title: "title"}] = results
    end

    test "with related data that does and doesn't match" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "not match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      results =
        Post
        |> Ash.Query.filter(comments.title == "match")
        |> Ash.read!()

      assert [%Post{title: "title"}] = results
    end
  end

  describe "in" do
    test "it properly filters" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "title1"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "title2"})
      |> Ash.create!()

      assert [%Post{title: "title1"}, %Post{title: "title2"}] =
               Post
               |> Ash.Query.filter(title in ["title1", "title2"])
               |> Ash.Query.sort(title: :asc)
               |> Ash.read!()
    end
  end

  describe "with a boolean filter applied" do
    test "with no data" do
      results =
        Post
        |> Ash.Query.filter(title == "title" or score == 1)
        |> Ash.read!()

      assert [] = results
    end

    test "with data that doesn't match" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "no title", score: 2})
      |> Ash.create!()

      results =
        Post
        |> Ash.Query.filter(title == "title" or score == 1)
        |> Ash.read!()

      assert [] = results
    end

    test "with data that matches both conditions" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title", score: 0})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{score: 1, title: "nothing"})
      |> Ash.create!()

      results =
        Post
        |> Ash.Query.filter(title == "title" or score == 1)
        |> Ash.read!()
        |> Enum.sort_by(& &1.score)

      assert [%Post{title: "title", score: 0}, %Post{title: "nothing", score: 1}] = results
    end

    test "with data that matches one condition and data that matches nothing" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title", score: 0})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{score: 2, title: "nothing"})
      |> Ash.create!()

      results =
        Post
        |> Ash.Query.filter(title == "title" or score == 1)
        |> Ash.read!()
        |> Enum.sort_by(& &1.score)

      assert [%Post{title: "title", score: 0}] = results
    end

    test "with related data in an or statement that matches, while basic filter doesn't match" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "doesn't match"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      results =
        Post
        |> Ash.Query.filter(title == "match" or comments.title == "match")
        |> Ash.read!()

      assert [%Post{title: "doesn't match"}] = results
    end

    test "with related data in an or statement that doesn't match, while basic filter does match" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "match"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "doesn't match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      results =
        Post
        |> Ash.Query.filter(title == "match" or comments.title == "match")
        |> Ash.read!()

      assert [%Post{title: "match"}] = results
    end

    test "with related data and an inner join condition" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "match"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      results =
        Post
        |> Ash.Query.filter(title == comments.title)
        |> Ash.read!()

      assert [%Post{title: "match"}] = results

      results =
        Post
        |> Ash.Query.filter(title != comments.title)
        |> Ash.read!()

      assert [] = results
    end
  end

  describe "using actor in filters" do
    test "actor templates work in relationships" do
      author =
        Author
        |> Ash.Changeset.for_create(:create, %{badges: [:author_of_the_year]})
        |> Ash.create!()

      author2 =
        Author
        |> Ash.Changeset.for_create(:create, %{badges: [:author_of_the_year]})
        |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "match", author_id: author.id})
      |> Ash.create!()

      assert [_] =
               Post
               |> Ash.Query.filter(not is_nil(current_user_author.id))
               |> Ash.read!(actor: author, authorize?: false)

      assert [] =
               Post
               |> Ash.Query.filter(not is_nil(current_user_author.id))
               |> Ash.read!(actor: author2, authorize?: false)
    end
  end

  describe "accessing embeds" do
    setup do
      Author
      |> Ash.Changeset.for_create(:create,
        bio: %{title: "Dr.", bio: "Strange", years_of_experience: 10}
      )
      |> Ash.create!()

      Author
      |> Ash.Changeset.for_create(:create,
        bio: %{title: "Highlander", bio: "There can be only one."}
      )
      |> Ash.create!()

      :ok
    end

    test "works using simple equality" do
      assert [%{bio: %{title: "Dr."}}] =
               Author
               |> Ash.Query.filter(bio[:title] == "Dr.")
               |> Ash.read!()
    end

    test "works using simple equality for integers" do
      assert [%{bio: %{title: "Dr."}}] =
               Author
               |> Ash.Query.filter(bio[:years_of_experience] == 10)
               |> Ash.read!()
    end

    test "works using an expression" do
      assert [%{bio: %{title: "Highlander"}}] =
               Author
               |> Ash.Query.filter(contains(type(bio[:bio], :string), "only one."))
               |> Ash.read!()
    end

    test "calculations that use embeds can be filtered on" do
      assert [%{bio: %{title: "Dr."}}] =
               Author
               |> Ash.Query.filter(title == "Dr.")
               |> Ash.read!()
    end
  end

  describe "basic expressions" do
    test "basic expressions work" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "match", score: 4})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "non_match", score: 2})
      |> Ash.create!()

      assert [%{title: "match"}] =
               Post
               |> Ash.Query.filter(score + 1 == 5)
               |> Ash.read!()
    end
  end

  describe "case insensitive fields" do
    test "it matches case insensitively" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "match", category: "FoObAr"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{category: "bazbuz"})
      |> Ash.create!()

      assert [%{title: "match"}] =
               Post
               |> Ash.Query.filter(category == "fOoBaR")
               |> Ash.read!()
    end
  end

  describe "contains/2" do
    test "it works when it matches" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "bazbuz"})
      |> Ash.create!()

      assert [%{title: "match"}] =
               Post
               |> Ash.Query.filter(contains(title, "atc"))
               |> Ash.read!()
    end

    test "it works when a case insensitive string is provided as a value" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "bazbuz"})
      |> Ash.create!()

      assert [%{title: "match"}] =
               Post
               |> Ash.Query.filter(contains(title, ^%Ash.CiString{string: "ATC"}))
               |> Ash.read!()
    end

    test "it works on a case insensitive column" do
      Post
      |> Ash.Changeset.for_create(:create, %{category: "match"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{category: "bazbuz"})
      |> Ash.create!()

      assert [%{category: %Ash.CiString{string: "match"}}] =
               Post
               |> Ash.Query.filter(contains(category, ^"ATC"))
               |> Ash.read!()
    end

    test "it works on a case insensitive calculation" do
      Post
      |> Ash.Changeset.for_create(:create, %{category: "match"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{category: "bazbuz"})
      |> Ash.create!()

      assert [%{category: %Ash.CiString{string: "match"}}] =
               Post
               |> Ash.Query.filter(contains(category_label, ^"ATC"))
               |> Ash.read!()
    end

    test "it works on related values" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "match"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "abba"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      post2 =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "no_match"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "acca"})
      |> Ash.Changeset.manage_relationship(:post, post2, type: :append_and_remove)
      |> Ash.create!()

      assert [%{title: "match"}] =
               Post
               |> Ash.Query.filter(contains(comments.title, ^"bb"))
               |> Ash.read!()
    end
  end

  describe "length/1" do
    test "it works with a list attribute" do
      author1 =
        Author
        |> Ash.Changeset.for_create(:create, %{badges: [:author_of_the_year]})
        |> Ash.create!()

      _author2 =
        Author
        |> Ash.Changeset.for_create(:create, %{badges: []})
        |> Ash.create!()

      author1_id = author1.id

      assert [%{id: ^author1_id}] =
               Author
               |> Ash.Query.filter(length(badges) > 0)
               |> Ash.read!()
    end

    test "it works with nil" do
      author1 =
        Author
        |> Ash.Changeset.for_create(:create, %{badges: [:author_of_the_year]})
        |> Ash.create!()

      _author2 =
        Author
        |> Ash.Changeset.new()
        |> Ash.create!()

      author1_id = author1.id

      assert [%{id: ^author1_id}] =
               Author
               |> Ash.Query.filter(length(badges || []) > 0)
               |> Ash.read!()
    end

    test "it works with a list" do
      author1 =
        Author
        |> Ash.Changeset.new()
        |> Ash.create!()

      author1_id = author1.id

      explicit_list = [:foo]

      assert [%{id: ^author1_id}] =
               Author
               |> Ash.Query.filter(length(^explicit_list) > 0)
               |> Ash.read!()

      assert [] =
               Author
               |> Ash.Query.filter(length(^explicit_list) > 1)
               |> Ash.read!()
    end

    test "it raises with bad values" do
      Author
      |> Ash.Changeset.new()
      |> Ash.create!()

      assert_raise(Ash.Error.Unknown, fn ->
        Author
        |> Ash.Query.filter(length(first_name) > 0)
        |> Ash.read!()
      end)
    end
  end

  describe "exists/2" do
    test "it works with single relationships" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "match"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "abba"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      post2 =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "no_match"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "acca"})
      |> Ash.Changeset.manage_relationship(:post, post2, type: :append_and_remove)
      |> Ash.create!()

      assert [%{title: "match"}] =
               Post
               |> Ash.Query.filter(exists(comments, title == ^"abba"))
               |> Ash.read!()
    end

    test "it works with many to many relationships" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "a"})
        |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "b"})
      |> Ash.Changeset.manage_relationship(:linked_posts, [post], type: :append_and_remove)
      |> Ash.create!()

      assert [%{title: "b"}] =
               Post
               |> Ash.Query.filter(exists(linked_posts, title == ^"a"))
               |> Ash.read!()
    end

    test "it works with join association relationships" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "a"})
        |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "b"})
      |> Ash.Changeset.manage_relationship(:linked_posts, [post], type: :append_and_remove)
      |> Ash.create!()

      other_post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "b"})
        |> Ash.create!()

      PostLink
      |> Ash.Changeset.for_create(:create, %{
        source_post_id: post.id,
        destination_post_id: other_post.id
      })
      |> Ash.create!()

      assert [%{title: "b"}] =
               Post
               |> Ash.Query.filter(exists(linked_posts, title == ^"a"))
               |> Ash.read!()
    end

    test "it works with nested relationships as the path" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "a"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "comment"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "b"})
      |> Ash.Changeset.manage_relationship(:linked_posts, [post], type: :append_and_remove)
      |> Ash.create!()

      assert [%{title: "b"}] =
               Post
               |> Ash.Query.filter(exists(linked_posts.comments, title == ^"comment"))
               |> Ash.read!()
    end

    test "it works with an `at_path`" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "a"})
        |> Ash.create!()

      other_post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "other_a"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "comment"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "comment"})
      |> Ash.Changeset.manage_relationship(:post, other_post, type: :append_and_remove)
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "b"})
      |> Ash.Changeset.manage_relationship(:linked_posts, [post], type: :append_and_remove)
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "b"})
      |> Ash.Changeset.manage_relationship(:linked_posts, [other_post], type: :append_and_remove)
      |> Ash.create!()

      assert [%{title: "b"}] =
               Post
               |> Ash.Query.filter(
                 linked_posts.title == "a" and
                   linked_posts.exists(comments, title == ^"comment")
               )
               |> Ash.read!()

      assert [%{title: "b"}] =
               Post
               |> Ash.Query.filter(
                 linked_posts.title == "a" and
                   linked_posts.exists(comments, title == ^"comment")
               )
               |> Ash.read!()
    end

    test "it works with nested relationships inside of exists" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "a"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "comment"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "b"})
      |> Ash.Changeset.manage_relationship(:linked_posts, [post], type: :append_and_remove)
      |> Ash.create!()

      assert [%{title: "b"}] =
               Post
               |> Ash.Query.filter(exists(linked_posts, comments.title == ^"comment"))
               |> Ash.read!()
    end

    test "it works with aggregates inside of exists" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "a", category: "foo"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "comment"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "b"})
      |> Ash.Changeset.manage_relationship(:linked_posts, [post], type: :append_and_remove)
      |> Ash.create!()

      assert [%{title: "b"}] =
               Post
               |> Ash.Query.filter(
                 exists(linked_posts.comments, title == ^"comment" and post_category == "foo")
               )
               |> Ash.read!()
    end

    test "it works with synthesized to-one relationships" do
      for i <- 1..4 do
        post =
          Post
          |> Ash.Changeset.for_create(:create, %{title: to_string(i), category: "foo"})
          |> Ash.create!()

        Comment
        |> Ash.Changeset.for_create(:create, %{title: "comment"})
        |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
        |> Ash.create!()

        if rem(i, 2) == 0 do
          Comment
          |> Ash.Changeset.for_create(:create, %{title: "later_comment"})
          |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
          |> Ash.create!()
        end

        post
      end

      matching_post_count =
        Post
        |> Ash.Query.filter(exists(latest_comment, title == "later_comment"))
        |> Ash.read!()
        |> Enum.count()

      assert 2 = matching_post_count
    end
  end

  describe "filtering on enum types" do
    test "it allows simple filtering" do
      Post
      |> Ash.Changeset.for_create(:create, status_enum: "open")
      |> Ash.create!()

      assert %{status_enum: :open} =
               Post
               |> Ash.Query.filter(status_enum == ^"open")
               |> Ash.read_one!()
    end

    test "it allows simple filtering without casting" do
      Post
      |> Ash.Changeset.for_create(:create, status_enum_no_cast: "open")
      |> Ash.create!()

      assert %{status_enum_no_cast: :open} =
               Post
               |> Ash.Query.filter(status_enum_no_cast == ^"open")
               |> Ash.read_one!()
    end
  end

  describe "atom filters" do
    test "it works on matches" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.create!()

      result =
        Post
        |> Ash.Query.filter(type == :sponsored)
        |> Ash.read!()

      assert [%Post{title: "match"}] = result
    end
  end

  describe "like and ilike" do
    test "like builds and matches" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "MaTcH"})
      |> Ash.create!()

      results =
        Post
        |> Ash.Query.filter(like(title, "%aTc%"))
        |> Ash.read!()

      assert [%Post{title: "MaTcH"}] = results

      results =
        Post
        |> Ash.Query.filter(like(title, "%atc%"))
        |> Ash.read!()

      assert [] = results
    end

    test "ilike builds and matches" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "MaTcH"})
      |> Ash.create!()

      results =
        Post
        |> Ash.Query.filter(ilike(title, "%aTc%"))
        |> Ash.read!()

      assert [%Post{title: "MaTcH"}] = results

      results =
        Post
        |> Ash.Query.filter(ilike(title, "%atc%"))
        |> Ash.read!()

      assert [%Post{title: "MaTcH"}] = results
    end
  end

  describe "trigram_similarity" do
    test "it works on matches" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.create!()

      results =
        Post
        |> Ash.Query.filter(trigram_similarity(title, "match") > 0.9)
        |> Ash.read!()

      assert [%Post{title: "match"}] = results
    end

    test "it works on non-matches" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.create!()

      results =
        Post
        |> Ash.Query.filter(trigram_similarity(title, "match") < 0.1)
        |> Ash.read!()

      assert [] = results
    end
  end

  describe "fragments" do
    test "double replacement works" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "match", score: 4})
        |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "non_match", score: 2})
      |> Ash.create!()

      assert [%{title: "match"}] =
               Post
               |> Ash.Query.filter(fragment("? = ?", title, ^post.title))
               |> Ash.read!()

      assert [] =
               Post
               |> Ash.Query.filter(fragment("? = ?", title, "nope"))
               |> Ash.read!()
    end
  end

  test "filtering allows filtering on list aggregates with filters" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.create!()

    post_id = post.id

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "match", likes: 5})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "non_match", likes: 5})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    post2 =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "non_match"})
      |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "non_match", likes: 5})
    |> Ash.Changeset.manage_relationship(:post, post2, type: :append_and_remove)
    |> Ash.create!()

    assert [%{id: ^post_id}] =
             Post
             |> Ash.Query.filter("match" in comment_titles_with_5_likes)
             |> Ash.read!()
  end

  test "filtering allows filtering on count aggregates with filters" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.create!()

    post_id = post.id

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "title"})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "title"})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    post2 =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "non_match"})
      |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "title"})
    |> Ash.Changeset.manage_relationship(:post, post2, type: :append_and_remove)
    |> Ash.create!()

    assert [%{id: ^post_id}] =
             Post
             |> Ash.Query.filter(count_of_comments_that_have_a_post == 2)
             |> Ash.read!()
  end

  describe "filtering on relationships that themselves have filters" do
    test "it doesn't raise an error" do
      Comment
      |> Ash.Query.filter(not is_nil(popular_ratings.id))
      |> Ash.read!()
    end

    test "it doesn't raise an error when nested" do
      Post
      |> Ash.Query.filter(not is_nil(comments.popular_ratings.id))
      |> Ash.read!()
    end

    test "aggregates using them don't raise errors" do
      Comment
      |> Ash.Query.load(:co_popular_comments)
      |> Ash.read!()
    end

    test "filtering on aggregates using them doesn't raise errors" do
      Comment
      |> Ash.Query.filter(co_popular_comments > 1)
      |> Ash.read!()
    end
  end

  test "can reference related items from a relationship expression" do
    Post
    |> Ash.Query.filter(comments_with_high_rating.title == "foo")
    |> Ash.read!()
  end

  test "filter by has_one from_many?" do
    [_cm1, cm2 | _] =
      for _ <- 1..5 do
        c = Ash.Changeset.for_create(Channel, :create, %{}) |> Ash.create!()
        Ash.Changeset.for_create(ChannelMember, :create, %{channel_id: c.id}) |> Ash.create!()
      end

    assert Channel
           |> Ash.Query.for_read(:read)
           |> Ash.Query.filter(first_member.id != ^cm2.id)
           |> Ash.read!()
           |> length == 4

    assert Channel
           |> Ash.Query.for_read(:read)
           |> Ash.Query.filter(first_member.id == ^cm2.id)
           |> Ash.read!()
           |> length == 1
  end

  test "using exists with from_many?" do
    c = Ash.Changeset.for_create(Channel, :create, %{}) |> Ash.create!()

    [cm1, cm2 | _] =
      for _ <- 1..5 do
        Ash.Changeset.for_create(ChannelMember, :create, %{channel_id: c.id}) |> Ash.create!()
      end

    assert Channel
           |> Ash.Query.for_read(:read)
           |> Ash.Query.filter(exists(first_member, id == ^cm2.id))
           |> Ash.read!()
           |> length == 0

    assert Channel
           |> Ash.Query.for_read(:read)
           |> Ash.Query.filter(exists(first_member, id == ^cm1.id))
           |> Ash.read!()
           |> length == 1
  end

  test "using `(is_nil(relationship) and other_relation_filter)` will trigger left join" do
    organization =
      Organization
      |> Ash.Changeset.for_create(:create, %{name: "foo"})
      |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{organization_id: organization.id})
    |> Ash.create!()

    assert [_] =
             Post
             |> Ash.Query.filter(
               # it isn't smart enough to know we can left join here
               # and there isn't currently a way to hint that it can
               is_nil(author) and
                 contains(
                   fragment("lower(?)", organization.name),
                   fragment("lower(?)", "foo")
                 )
             )
             |> Ash.read!()
  end

  test "filter with ref" do
    organization =
      Organization
      |> Ash.Changeset.for_create(:create, %{name: "foo"})
      |> Ash.create!()

    post =
      Post
      |> Ash.Changeset.for_create(:create, %{organization_id: organization.id})
      |> Ash.create!()

    comment =
      Comment
      |> Ash.Changeset.for_create(:create, %{title: "not match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

    fetched_org =
      Organization
      |> Ash.Query.filter(^ref([:posts, :comments], :id) == ^comment.id)
      |> Ash.read_one!()

    assert fetched_org.id == organization.id
  end
end
