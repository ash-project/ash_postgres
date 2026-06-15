# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Changes.AfterBatchMarker do
  @moduledoc """
  An atomic-compatible change with an `after_batch` hook, used to verify that `Ash.update_many`
  runs after_batch hooks on its single-statement (MERGE) path.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context), do: changeset

  @impl true
  def atomic(_changeset, _opts, _context), do: :ok

  @impl true
  def batch_change(changesets, _opts, _context), do: changesets

  @impl true
  def after_batch(results, _opts, _context) do
    Enum.map(results, fn {_changeset, record} ->
      {:ok, Ash.Resource.put_metadata(record, :after_batch_ran, true)}
    end)
  end
end

defmodule AshPostgres.Test.Changes.AtomicAfterActionMarker do
  @moduledoc """
  An atomic change that registers an `after_action` hook (atomic changes may carry after_action
  hooks). Used to verify `Ash.update_many` runs after_action hooks on its MERGE path.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context), do: add_hook(changeset)

  @impl true
  def atomic(changeset, _opts, _context), do: {:atomic, add_hook(changeset), %{}}

  defp add_hook(changeset) do
    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      {:ok, Ash.Resource.put_metadata(record, :after_action_ran, true)}
    end)
  end
end
