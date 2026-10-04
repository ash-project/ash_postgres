# SPDX-FileCopyrightText: 2024 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Temporal.WriteConflict do
  @moduledoc """
  Used when a temporal write keeps losing to concurrent writes to the same records.

  A temporal write that finds the versions it's splitting were changed by another
  transaction in the meantime runs again. This is raised when it has run `attempts` times
  and still conflicted, which takes many transactions writing the same slice of the same
  records at once. Retrying the action is safe: nothing was written.
  """

  use Splode.Error, fields: [:resource, :attempts], class: :framework

  def message(error) do
    "Temporal write to #{inspect(error.resource)} conflicted with concurrent writes to the " <>
      "same records #{error.attempts} times in a row, so nothing was written. " <>
      "Retrying the action is safe."
  end
end
