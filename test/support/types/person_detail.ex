defmodule AshPostgres.Test.PersonDetail do
  @moduledoc """
  A tuple type for testing Ash.Type.Tuple
  """
  use Ash.Type.NewType,
    subtype_of: :tuple,
    constraints: [
      fields: [
        first_name: [type: :string, allow_nil?: false],
        last_name: [type: :string, allow_nil?: false]
      ]
    ]
end
