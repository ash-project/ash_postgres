defmodule AshPostgres.CustomAggregate do
  @moduledoc """
  A custom aggregate implementation for ecto.
  """

  @doc """
  The dynamic expression to create the aggregate.

  The binding refers to the resource being aggregated,
  use `as(^binding)` to reference it.

  For example:

      Ecto.Query.dynamic(
        [],
        fragment("string_agg(?, ?)", field(as(^binding), ^opts[:field]), ^opts[:delimiter])
      )
  """
  @callback dynamic(opts :: Keyword.t(), binding :: integer) :: Ecto.Query.dynamic_expr()

  defmacro __using__(_) do
    quote do
      @behaviour AshPostgres.CustomAggregate
    end
  end
end
