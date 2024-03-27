defmodule AshPostgres.Type do
  @moduledoc """
  Postgres specific callbacks for `Ash.Type`.

  Use this in addition to `Ash.Type`.
  """

  @callback value_to_postgres_default(Ash.Type.t(), Ash.Type.constraints(), term) ::
              {:ok, String.t()} | :error

  defmacro __using__(_) do
    quote do
      @behaviour AshPostgres.Type
      def value_to_postgres_default(_, _, _), do: :error

      defoverridable value_to_postgres_default: 3
    end
  end
end
