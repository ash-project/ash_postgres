# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Type do
  @moduledoc """
  Postgres specific callbacks for `Ash.Type`.

  Use this in addition to `Ash.Type`.
  """

  @callback value_to_postgres_default(Ash.Type.t(), Ash.Type.constraints(), term) ::
              {:ok, String.t()} | :error

  @callback postgres_reference_expr(Ash.Type.t(), Ash.Type.constraints(), term) ::
              {:ok, term} | :error

  @callback migration_type(Ash.Type.constraints()) :: term()

  @optional_callbacks value_to_postgres_default: 3,
                      postgres_reference_expr: 3,
                      migration_type: 1

  defmacro __using__(_) do
    quote do
      @behaviour AshPostgres.Type

      def value_to_postgres_default(_, _, _), do: :error
      def postgres_reference_expr(_, _, _), do: :error

      defoverridable value_to_postgres_default: 3,
                     postgres_reference_expr: 3
    end
  end
end
