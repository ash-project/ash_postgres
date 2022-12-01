defmodule AshPostgresTest do
  use AshPostgres.RepoCase, async: false

  test "transaction metadata is given to on_transaction_begin" do
    AshPostgres.Test.Post
    |> Ash.Changeset.new(%{title: "title"})
    |> AshPostgres.Test.Api.create!()

    assert_receive %{
      type: :create,
      metadata: %{action: :create, actor: nil, resource: AshPostgres.Test.Post}
    }
  end
end
