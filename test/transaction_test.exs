# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.TransactionTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Post

  require Ash.Query

  test "after_transaction hooks are invoked on failure" do
    assert_raise Ash.Error.Unknown, ~r/something bad happened/, fn ->
      Post
      |> Ash.Changeset.for_create(:create)
      |> Ash.Changeset.after_action(fn _changeset, _result ->
        raise "something bad happened"
      end)
      |> send_after_transaction_result()
      |> Ash.create()
    end

    assert_receive {:error,
                    %RuntimeError{
                      message: "something bad happened"
                    }}
  end

  test "after_transaction hooks are invoked on failure, even in a nested context" do
    assert_raise Ash.Error.Unknown, ~r/something bad happened inside/, fn ->
      Post
      |> Ash.Changeset.for_create(:create)
      |> Ash.Changeset.after_action(fn _changeset, result ->
        Post
        |> Ash.Changeset.for_create(:create)
        |> Ash.Changeset.after_action(fn _changeset, _result ->
          raise "something bad happened inside"
        end)
        |> send_after_transaction_result()
        |> Ash.create!()

        {:ok, result}
      end)
      |> send_after_transaction_result()
      |> Ash.create()
    end

    assert_receive {:error,
                    %RuntimeError{
                      message: "something bad happened inside"
                    }}

    assert_receive {:error, %Ash.Error.Unknown{}}
  end

  test "after_transaction hooks are invoked on success" do
    Post
    |> Ash.Changeset.for_create(:create)
    |> send_after_transaction_result()
    |> Ash.create()

    assert_receive {:ok, %Post{}}
  end

  test "after_transaction hooks are invoked on success and can reverse a failure" do
    assert {:ok, %Post{}} =
             Post
             |> Ash.Changeset.for_create(:create)
             |> Ash.Changeset.after_action(fn _changeset, result ->
               Post
               |> Ash.Changeset.for_create(:create)
               |> Ash.Changeset.after_action(fn _changeset, _result ->
                 raise "something bad happened inside"
               end)
               |> send_after_transaction_result()
               |> Ash.create!()

               {:ok, result}
             end)
             |> Ash.Changeset.after_transaction(fn _changeset, {:error, _} ->
               Post
               |> Ash.Changeset.for_create(:create)
               |> Ash.create()
             end)
             |> send_after_transaction_result()
             |> Ash.create()

    assert_receive {:error,
                    %RuntimeError{
                      message: "something bad happened inside"
                    }}

    assert_receive {:ok, %Post{}}
  end

  defp send_after_transaction_result(changeset) do
    Ash.Changeset.after_transaction(changeset, fn _changeset, result ->
      send(self(), result)
      result
    end)
  end
end
