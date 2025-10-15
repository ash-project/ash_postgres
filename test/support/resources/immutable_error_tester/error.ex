defmodule AshPostgres.Test.ImmutableErrorTester.Error do
  @moduledoc false
  use Splode.Error,
    class: :invalid,
    fields: [
      :atom_value,
      :string_value,
      :integer_value,
      :float_value,
      :boolean_value,
      :struct_value,
      :uuid_value,
      :date_value,
      :time_value,
      :ci_string_value,
      :naive_datetime_value,
      :utc_datetime_value,
      :timestamptz_value,
      :string_array_value,
      :response_value,
      :nullable_string_value
    ]

  def message(_error) do
    "Immutable Error"
  end
end
