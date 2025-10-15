defmodule AshPostgres.Test.ImmutableErrorTester.Struct do
  @moduledoc false
  use Ash.TypedStruct

  typed_struct do
    field(:name, :string, allow_nil?: false)
    field(:count, :integer, allow_nil?: false)
    field(:active?, :boolean, allow_nil?: false)
  end
end
