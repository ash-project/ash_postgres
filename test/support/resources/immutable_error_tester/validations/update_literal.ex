# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.ImmutableErrorTester.Validations.UpdateLiteral do
  @moduledoc false
  use Ash.Resource.Validation

  import Ash.Expr

  @impl true
  def init(opts), do: {:ok, opts}

  # Validation that always fails. Builds an error with only literal values, zero expression values.
  #
  # Use fragment with PG function to ensure the validation runs as part of the query.
  @impl true
  def atomic(_changeset, _opts, _context) do
    [
      {:atomic, :*, expr(fragment("pg_column_size(?) != 0", ^ref(:id))),
       expr(
         error(AshPostgres.Test.ImmutableErrorTester.Error,
           string_value: "literal string",
           integer_value: 123,
           float_value: 9.99,
           boolean_value: false,
           string_array_value: ["alpha", "beta"],
           nullable_string_value: nil
         )
       )}
    ]
  end
end
