# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Temporal.BeforeNow do
  @moduledoc """
  Test validation: the given datetime field must be before `now()`.

  Used to verify temporal anchoring of validations — its `now()` resolves to the
  changeset's `as_of` (atomically via the data layer, eagerly via `as_of`), not
  the wall clock.
  """
  use Ash.Resource.Validation

  import Ash.Expr
  alias Ash.Error.Changes.InvalidAttribute

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def supports(_opts), do: [Ash.Changeset]

  # Atomic check: invalid when `field >= now()` (i.e. not before now). The `now()`
  # here is anchored to the changeset's `as_of` when the data layer renders it.
  @impl true
  def atomic(_changeset, opts, _context) do
    field = Keyword.fetch!(opts, :field)

    {:atomic, [field], expr(^atomic_ref(field) >= now()),
     expr(
       error(^InvalidAttribute, %{
         field: ^field,
         message: "must be before now"
       })
     )}
  end

  # Eager check mirrors the atomic one, anchored to the changeset's `as_of`.
  @impl true
  def validate(changeset, opts, _context) do
    field = Keyword.fetch!(opts, :field)
    value = Ash.Changeset.get_attribute(changeset, field)
    as_of = changeset.as_of || DateTime.utc_now()

    if is_nil(value) || DateTime.compare(value, as_of) == :lt do
      :ok
    else
      {:error, field: field, message: "must be before now"}
    end
  end
end
