# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.LockTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Post
  require Ash.Query

  setup do
    Application.put_env(:ash, :disable_async?, true)

    on_exit(fn ->
      Application.put_env(:ash, :disable_async?, false)
      AshPostgres.TestNoSandboxRepo.delete_all(Post)
    end)
  end

  test "lock conflicts raise appropriate errors" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "locked"})
      |> Ash.Changeset.set_context(%{data_layer: %{repo: AshPostgres.TestNoSandboxRepo}})
      |> Ash.create!()

    task1 =
      Task.async(fn ->
        AshPostgres.TestNoSandboxRepo.transaction(fn ->
          Post
          |> Ash.Query.lock("FOR UPDATE NOWAIT")
          |> Ash.Query.set_context(%{data_layer: %{repo: AshPostgres.TestNoSandboxRepo}})
          |> Ash.Query.filter(id == ^post.id)
          |> Ash.read!()

          :timer.sleep(1000)
          :ok
        end)
      end)

    task2 =
      Task.async(fn ->
        try do
          AshPostgres.TestNoSandboxRepo.transaction(fn ->
            :timer.sleep(100)

            Post
            |> Ash.Query.lock("FOR UPDATE NOWAIT")
            |> Ash.Query.set_context(%{data_layer: %{repo: AshPostgres.TestNoSandboxRepo}})
            |> Ash.Query.filter(id == ^post.id)
            |> Ash.read!()
          end)
        rescue
          e ->
            {:error, e}
        end
      end)

    assert [{:ok, :ok}, {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Invalid.Unavailable{}]}}] =
             Task.await_many([task1, task2], :infinity)
  end
end
