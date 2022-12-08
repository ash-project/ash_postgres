defmodule AshPostgres.CustomAggregate do
  @callback dynamic(opts :: Keyword.t(), binding :: integer) :: Ecto.Query.dynamic()

  defmacro __using__(_) do
    quote do
      @behaviour AshPostgres.CustomAggregate
    end
  end
end
