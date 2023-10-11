defmodule AshPostgres.AtomicsTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Api, Post}

  import Ash.Expr

  test "atomics work on upserts" do
    id = Ash.UUID.generate()

    Post
    |> Ash.Changeset.for_create(:create, %{id: id, title: "foo", price: 1}, upsert?: true)
    |> Ash.Changeset.atomic_update(:price, expr(price + 1))
    |> Api.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{id: id, title: "foo", price: 1}, upsert?: true)
    |> Ash.Changeset.atomic_update(:price, expr(price + 1))
    |> Api.create!()

    assert [%{price: 2}] = Post |> Api.read!()
  end

  test "a basic atomic works" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "foo", price: 1})
      |> Api.create!()

    assert %{price: 2} =
             post
             |> Ash.Changeset.for_update(:update, %{})
             |> Ash.Changeset.atomic_update(:price, expr(price + 1))
             |> Api.update!()
  end

  test "an atomic works with a datetime" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "foo", price: 1})
      |> Api.create!()

    now = DateTime.utc_now()

    assert %{created_at: ^now} =
             post
             |> Ash.Changeset.for_update(:update, %{})
             |> Ash.Changeset.atomic_update(:created_at, expr(^now))
             |> Api.update!()
  end

  test "an atomic that violates a constraint will return the proper error" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "foo", price: 1})
      |> Api.create!()

    assert_raise Ash.Error.Invalid, ~r/does not exist/, fn ->
      post
      |> Ash.Changeset.for_update(:update, %{})
      |> Ash.Changeset.atomic_update(:organization_id, Ash.UUID.generate())
      |> Api.update!()
    end
  end

  test "an atomic can refer to a calculation" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "foo", price: 1})
      |> Api.create!()

    post =
      post
      |> Ash.Changeset.for_update(:update, %{})
      |> Ash.Changeset.atomic_update(:score, expr(score_after_winning))
      |> Api.update!()

    assert post.score == 1
  end

  test "an atomic can be attached to an action" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "foo", price: 1})
      |> Api.create!()

    assert Post.increment_score!(post, 2).score == 2

    assert Post.increment_score!(post, 2).score == 4
  end
end
