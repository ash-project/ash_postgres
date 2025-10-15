defmodule AshPostgres.Test.ImmutableErrorTester.Validations.UpdateMany do
  @moduledoc false
  use Ash.Resource.Validation

  import Ash.Expr

  @impl true
  def init(opts), do: {:ok, opts}

  # Validation that always fails. Builds an error that include many (all attributes) value
  # expressions, and zero literal values (empty base input).
  #
  # Use fragment with PG function to ensure the validation runs as part of the query.
  @impl true
  def atomic(_changeset, _opts, _context) do
    [
      {:atomic, :*, expr(fragment("pg_column_size(?) != 0", ^ref(:id))),
       expr(
         error(
           AshPostgres.Test.ImmutableErrorTester.Error,
           atom_value: ^atomic_ref(:atom_value),
           string_value: ^atomic_ref(:string_value),
           integer_value: ^atomic_ref(:integer_value),
           float_value: ^atomic_ref(:float_value),
           boolean_value: ^atomic_ref(:boolean_value),
           struct_value: ^atomic_ref(:struct_value),
           uuid_value: ^atomic_ref(:uuid_value),
           date_value: ^atomic_ref(:date_value),
           time_value: ^atomic_ref(:time_value),
           ci_string_value: ^atomic_ref(:ci_string_value),
           naive_datetime_value: ^atomic_ref(:naive_datetime_value),
           utc_datetime_value: ^atomic_ref(:utc_datetime_value),
           timestamptz_value: ^atomic_ref(:timestamptz_value),
           string_array_value: ^atomic_ref(:string_array_value),
           response_value: ^atomic_ref(:response_value),
           nullable_string_value: ^atomic_ref(:nullable_string_value)
         )
       )}
    ]
  end
end
