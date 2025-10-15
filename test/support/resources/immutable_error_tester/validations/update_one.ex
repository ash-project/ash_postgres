defmodule AshPostgres.Test.ImmutableErrorTester.Validations.UpdateOne do
  @moduledoc false
  use Ash.Resource.Validation

  import Ash.Expr

  @impl true
  def init(opts), do: {:ok, opts}

  # Validation that always fails. Builds an error with a single expression value and literal
  # values (non-empty base input).
  #
  # Use fragment with PG function to ensure the validation runs as part of the query.
  @impl true
  def atomic(_changeset, _opts, _context) do
    [
      {:atomic, [:integer_value, :id], expr(fragment("pg_column_size(?) != 0", ^ref(:id))),
       expr(
         error(
           Ash.Error.Changes.InvalidAttribute,
           field: :integer_value,
           value: ^atomic_ref(:integer_value),
           message: "integer_value failed validation"
         )
       )}
    ]
  end
end
