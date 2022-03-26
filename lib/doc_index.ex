defmodule AshPostgres.DocIndex do
  use Ash.DocIndex

  def for_library, do: "ash_postgres"

  def extensions do
    [
      %{
        module: AshPostgres.DataLayer,
        name: "AshPostgres",
        target: "Ash.Resource",
        type: "DataLayer"
      }
    ]
  end

  @moduledoc "A module for configuring how a library is rendered in ash_hq"
  @type extension :: %{
          optional(:module) => module,
          optional(:target) => String.t(),
          optional(:default_for_target?) => boolean,
          optional(:name) => String.t(),
          optional(:type) => String.t()
        }

  @callback extensions() :: list(extension())
  @callback for_library() :: String.t()
end
