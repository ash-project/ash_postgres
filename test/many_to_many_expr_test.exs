defmodule AshPostgres.ManyToManyExprTest do
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.Author
  alias AshPostgres.Test.CoAuthorPost
  alias AshPostgres.Test.Post

  require Ash.Query

  setup ctx do
    main_author =
      if ctx[:main_author?],
        do: create_author(),
        else: nil

    co_authors =
      if ctx[:co_authors],
        do:
          1..ctx[:co_authors]
          |> Stream.map(
            &(Author
              |> Ash.Changeset.for_create(:create, %{first_name: "John #{&1}", last_name: "Doe"})
              |> Ash.create!())
          )
          |> Enum.into([]),
        else: []

    %{
      main_author: main_author,
      co_authors: co_authors
    }
  end

  def create_author(params \\ %{first_name: "John", last_name: "Doe"}) do
    Author
    |> Ash.Changeset.for_create(:create, params)
    |> Ash.create!()
  end

  def create_post(author) do
    Post
    |> Ash.Changeset.for_create(:create, %{title: "Post by #{author.first_name}"})
    |> Ash.create!()
  end

  def create_co_author_post(author, post, role) do
    CoAuthorPost
    |> Ash.Changeset.for_create(:create, %{author_id: author.id, post_id: post.id, role: role})
    |> Ash.create!()
  end

  def get_author!(author_id) do
    Author
    |> Ash.Query.new()
    |> Ash.Query.filter(id == ^author_id)
    |> Ash.Query.load([
      :all_co_authored_posts,
      :cancelled_co_authored_posts,
      :editor_of,
      :writer_of
    ])
    |> Ash.read_one!()
  end

  def get_co_author_post!(a_id, p_id) do
    CoAuthorPost
    |> Ash.Query.new()
    |> Ash.Query.filter(author_id == ^a_id and post_id == ^p_id)
    |> Ash.read_one!()
  end

  def get_post!(post_id) do
    Post.get_by_id!(post_id, load: [:co_author_posts, :co_authors_unfiltered, :co_authors])
  end

  def cancel(author, post) do
    get_co_author_post!(author.id, post.id)
    |> CoAuthorPost.cancel()
  end

  def uncancel(author, post) do
    get_co_author_post!(author.id, post.id)
    |> CoAuthorPost.uncancel()
  end

  describe "manual join-resource insertion" do
    @tag main_author?: true
    @tag co_authors: 3
    test "filter on many_to_many relationship using parent works as expected - basic",
         %{
           main_author: main_author,
           co_authors: co_authors
         } do
      post = create_post(main_author)

      [first_ca, second_ca, third_ca] = co_authors

      # Add first co-author
      create_co_author_post(first_ca, post, :editor)

      first_ca = get_author!(first_ca.id)
      post = get_post!(post.id)

      assert Enum.count(post.co_authors) == 1
      assert Enum.count(first_ca.all_co_authored_posts) == 1
      assert Enum.count(first_ca.editor_of) == 1
      assert Enum.empty?(first_ca.writer_of) == true
      assert Enum.empty?(first_ca.cancelled_co_authored_posts) == true

      # Add second co-author
      create_co_author_post(second_ca, post, :writer)

      second_ca = get_author!(second_ca.id)
      post = get_post!(post.id)

      assert Enum.count(post.co_authors) == 2
      assert Enum.count(second_ca.all_co_authored_posts) == 1
      assert Enum.count(second_ca.writer_of) == 1
      assert Enum.empty?(second_ca.editor_of) == true
      assert Enum.empty?(second_ca.cancelled_co_authored_posts) == true

      # Add third co-author
      create_co_author_post(third_ca, post, :proof_reader)

      third_ca = get_author!(third_ca.id)
      post = get_post!(post.id)

      assert Enum.count(post.co_authors) == 3
      assert Enum.count(third_ca.all_co_authored_posts) == 1
      assert Enum.empty?(third_ca.editor_of) == true
      assert Enum.empty?(third_ca.writer_of) == true
      assert Enum.empty?(third_ca.cancelled_co_authored_posts) == true
    end

    @tag main_author?: true
    @tag co_authors: 4
    test "filter on many_to_many relationship using parent works as expected - cancelled",
         %{
           main_author: main_author,
           co_authors: co_authors
         } do
      first_post = create_post(main_author)
      second_post = create_post(main_author)

      [first_ca, second_ca, third_ca, fourth_ca] = co_authors

      # Add first co-author
      create_co_author_post(first_ca, first_post, :editor)
      create_co_author_post(first_ca, second_post, :writer)

      first_ca = get_author!(first_ca.id)
      first_post = get_post!(first_post.id)

      assert Enum.count(first_post.co_authors) == 1
      assert Enum.count(first_post.co_authors_unfiltered) == 1

      assert Enum.count(first_ca.all_co_authored_posts) == 2
      assert Enum.count(first_ca.editor_of) == 1
      assert Enum.count(first_ca.writer_of) == 1
      assert Enum.empty?(first_ca.cancelled_co_authored_posts) == true

      # Add second co-author
      create_co_author_post(second_ca, first_post, :proof_reader)
      create_co_author_post(second_ca, second_post, :writer)

      second_ca = get_author!(second_ca.id)
      first_post = get_post!(first_post.id)
      second_post = get_post!(second_post.id)

      assert Enum.count(second_post.co_authors) == 2
      assert Enum.count(second_post.co_authors_unfiltered) == 2

      assert Enum.count(second_ca.all_co_authored_posts) == 2
      assert Enum.count(second_ca.writer_of) == 1
      assert Enum.empty?(second_ca.editor_of) == true
      assert Enum.empty?(second_ca.cancelled_co_authored_posts) == true

      # Add third co-author
      create_co_author_post(third_ca, first_post, :proof_reader)
      create_co_author_post(third_ca, second_post, :proof_reader)
      cancel(third_ca, second_post)

      third_ca = get_author!(third_ca.id)
      first_post = get_post!(first_post.id)
      second_post = get_post!(second_post.id)

      assert Enum.count(first_post.co_authors) == 3
      assert Enum.count(first_post.co_authors_unfiltered) == 3
      assert Enum.count(second_post.co_authors) == 2
      assert Enum.count(second_post.co_authors_unfiltered) == 3

      assert Enum.count(third_ca.all_co_authored_posts) == 2
      assert Enum.count(third_ca.cancelled_co_authored_posts) == 1
      assert Enum.empty?(third_ca.editor_of) == true
      assert Enum.empty?(third_ca.writer_of) == true

      # Add fourth co-author
      create_co_author_post(fourth_ca, first_post, :proof_reader)
      create_co_author_post(fourth_ca, second_post, :editor)
      cancel(fourth_ca, first_post)
      cancel(fourth_ca, second_post)

      fourth_ca = get_author!(fourth_ca.id)
      first_post = get_post!(first_post.id)
      second_post = get_post!(second_post.id)

      assert Enum.count(first_post.co_authors) == 3
      assert Enum.count(first_post.co_authors_unfiltered) == 4
      assert Enum.count(second_post.co_authors) == 2
      assert Enum.count(second_post.co_authors_unfiltered) == 4

      assert Enum.count(fourth_ca.all_co_authored_posts) == 2
      assert Enum.count(fourth_ca.editor_of) == 1
      assert Enum.count(fourth_ca.cancelled_co_authored_posts) == 2
      assert Enum.empty?(fourth_ca.writer_of) == true
    end
  end
end
