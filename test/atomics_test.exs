defmodule AshPostgres.AtomicsTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Post

  import Ash.Expr

  test "atomics work on upserts" do
    id = Ash.UUID.generate()

    Post
    |> Ash.Changeset.for_create(:create, %{id: id, title: "foo", price: 1}, upsert?: true)
    |> Ash.Changeset.atomic_update(:price, expr(price + 1))
    |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{id: id, title: "foo", price: 1}, upsert?: true)
    |> Ash.Changeset.atomic_update(:price, expr(price + 1))
    |> Ash.create!()

    assert [%{price: 2}] = Post |> Ash.read!()
  end

  test "a basic atomic works" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "foo", price: 1})
      |> Ash.create!()

    assert %{price: 2} =
             post
             |> Ash.Changeset.for_update(:update, %{})
             |> Ash.Changeset.atomic_update(:price, expr(price + 1))
             |> Ash.update!()
  end

  test "an atomic works with a datetime" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "foo", price: 1})
      |> Ash.create!()

    now = DateTime.utc_now()

    assert %{created_at: ^now} =
             post
             |> Ash.Changeset.new()
             |> Ash.Changeset.atomic_update(:created_at, expr(^now))
             |> Ash.Changeset.for_update(:update, %{})
             |> Ash.update!()
  end

  test "an atomic that violates a constraint will return the proper error" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "foo", price: 1})
      |> Ash.create!()

    assert_raise Ash.Error.Invalid, ~r/does not exist/, fn ->
      post
      |> Ash.Changeset.new()
      |> Ash.Changeset.atomic_update(:organization_id, Ash.UUID.generate())
      |> Ash.Changeset.for_update(:update, %{})
      |> Ash.update!()
    end
  end

  test "an atomic can refer to a calculation" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "foo", price: 1})
      |> Ash.create!()

    post =
      post
      |> Ash.Changeset.for_update(:update, %{})
      |> Ash.Changeset.atomic_update(:score, expr(score_after_winning))
      |> Ash.update!()

    assert post.score == 1
  end

  test "an atomic can be attached to an action" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "foo", price: 1})
      |> Ash.create!()

    assert Post.increment_score!(post, 2).score == 2

    assert Post.increment_score!(post, 2).score == 4
  end
end
