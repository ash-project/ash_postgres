defmodule AshPostgres.CalculationTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Api, Author, Comment, Post}

  require Ash.Query

  test "an expression calculation can be filtered on" do
    post =
      Post
      |> Ash.Changeset.new(%{title: "match"})
      |> Api.create!()

    post2 =
      Post
      |> Ash.Changeset.new(%{title: "title2"})
      |> Api.create!()

    post3 =
      Post
      |> Ash.Changeset.new(%{title: "title3"})
      |> Api.create!()

    Comment
    |> Ash.Changeset.new(%{title: "_"})
    |> Ash.Changeset.replace_relationship(:post, post)
    |> Api.create!()

    Comment
    |> Ash.Changeset.new(%{title: "_"})
    |> Ash.Changeset.replace_relationship(:post, post)
    |> Api.create!()

    Comment
    |> Ash.Changeset.new(%{title: "_"})
    |> Ash.Changeset.replace_relationship(:post, post)
    |> Api.create!()

    post
    |> Ash.Changeset.new()
    |> Ash.Changeset.replace_relationship(:linked_posts, [post2, post3])
    |> Api.update!()

    post2
    |> Ash.Changeset.new()
    |> Ash.Changeset.replace_relationship(:linked_posts, [post3])
    |> Api.update!()

    assert [%{c_times_p: 6, title: "match"}] =
             Post
             |> Ash.Query.load(:c_times_p)
             |> Api.read!()
             |> Enum.filter(&(&1.c_times_p == 6))

    Application.put_env(:foo, :bar, true)

    assert [
             %{c_times_p: %Ash.NotLoaded{}, title: "match"}
           ] =
             Post
             |> Ash.Query.filter(c_times_p == 6)
             |> Api.read!()
  end

  test "calculations can be used in related filters" do
    post =
      Post
      |> Ash.Changeset.new(%{title: "match"})
      |> Api.create!()

    post2 =
      Post
      |> Ash.Changeset.new(%{title: "title2"})
      |> Api.create!()

    post3 =
      Post
      |> Ash.Changeset.new(%{title: "title3"})
      |> Api.create!()

    Comment
    |> Ash.Changeset.new(%{title: "match"})
    |> Ash.Changeset.replace_relationship(:post, post)
    |> Api.create!()

    Comment
    |> Ash.Changeset.new(%{title: "match"})
    |> Ash.Changeset.replace_relationship(:post, post)
    |> Api.create!()

    Comment
    |> Ash.Changeset.new(%{title: "match"})
    |> Ash.Changeset.replace_relationship(:post, post)
    |> Api.create!()

    Comment
    |> Ash.Changeset.new(%{title: "no_match"})
    |> Ash.Changeset.replace_relationship(:post, post2)
    |> Api.create!()

    post
    |> Ash.Changeset.new()
    |> Ash.Changeset.replace_relationship(:linked_posts, [post2, post3])
    |> Api.update!()

    post2
    |> Ash.Changeset.new()
    |> Ash.Changeset.replace_relationship(:linked_posts, [post3])
    |> Api.update!()

    posts_query =
      Post
      |> Ash.Query.load(:c_times_p)

    assert %{post: %{c_times_p: 6}} =
             Comment
             |> Ash.Query.load(post: posts_query)
             |> Api.read!()
             |> Enum.filter(&(&1.post.c_times_p == 6))
             |> Enum.at(0)

    query =
      Comment
      |> Ash.Query.filter(post.c_times_p == 6)
      |> Ash.Query.load(post: posts_query)
      |> Ash.Query.limit(1)

    Application.put_env(:foo, :bar, true)

    assert [
             %{post: %{c_times_p: 6, title: "match"}}
           ] = Api.read!(query)
  end

  test "concat calculation can be filtered on" do
    author =
      Author
      |> Ash.Changeset.new(%{first_name: "is", last_name: "match"})
      |> Api.create!()

    Author
    |> Ash.Changeset.new(%{first_name: "not", last_name: "match"})
    |> Api.create!()

    author_id = author.id

    assert %{id: ^author_id} =
             Author
             |> Ash.Query.filter(full_name == "is match")
             |> Api.read_one!()
  end

  test "conditional calculations can be filtered on" do
    author =
      Author
      |> Ash.Changeset.new(%{first_name: "tom"})
      |> Api.create!()

    Author
    |> Ash.Changeset.new(%{first_name: "tom", last_name: "holland"})
    |> Api.create!()

    author_id = author.id

    assert %{id: ^author_id} =
             Author
             |> Ash.Query.filter(conditional_full_name == "(none)")
             |> Api.read_one!()
  end

  test "parameterized calculations can be filtered on" do
    Author
    |> Ash.Changeset.new(%{first_name: "tom", last_name: "holland"})
    |> Api.create!()

    assert %{param_full_name: "tom holland"} =
             Author
             |> Ash.Query.load(:param_full_name)
             |> Api.read_one!()

    assert %{param_full_name: "tom~holland"} =
             Author
             |> Ash.Query.load(param_full_name: [separator: "~"])
             |> Api.read_one!()

    assert %{} =
             Author
             |> Ash.Query.filter(param_full_name(separator: "~") == "tom~holland")
             |> Api.read_one!()
  end

  test "parameterized related calculations can be filtered on" do
    author =
      Author
      |> Ash.Changeset.new(%{first_name: "tom", last_name: "holland"})
      |> Api.create!()

    Comment
    |> Ash.Changeset.new(%{title: "match"})
    |> Ash.Changeset.replace_relationship(:author, author)
    |> Api.create!()

    assert %{title: "match"} =
             Comment
             |> Ash.Query.filter(author.param_full_name(separator: "~") == "tom~holland")
             |> Api.read_one!()

    assert %{title: "match"} =
             Comment
             |> Ash.Query.filter(
               author.param_full_name(separator: "~") == "tom~holland" and
                 author.param_full_name(separator: " ") == "tom holland"
             )
             |> Api.read_one!()
  end
end
