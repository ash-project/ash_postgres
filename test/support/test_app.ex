defmodule AshPostgres.TestApp do
  @moduledoc false
  def start(_type, _args) do
    children = [
      AshPostgres.TestRepo
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AshPostgres.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
