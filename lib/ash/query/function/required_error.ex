#
# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT
#
unless Code.ensure_loaded?(Ash.Query.Function.RequiredError) do
  defmodule Ash.Query.Function.RequiredError do
    @moduledoc false

    # Compatibility shim:
    # Some Ash versions include `Ash.Query.Function.RequiredError` (used by `ash_required!/2`),
    # but others may not. Our postgres adapter and test suite expect it to exist.

    use Ash.Query.Function, name: :required!, predicate?: false

    @impl true
    def args, do: [[:any, :any]]

    @impl true
    def new([value_expr, attribute]) when is_struct(attribute) or is_map(attribute) do
      {:ok, %__MODULE__{arguments: [value_expr, attribute]}}
    end

    def new(_), do: {:error, "required!/2 expects (value, attribute)"}

    @impl true
    def evaluate(%{arguments: [value, attribute]}) do
      if is_nil(value) do
        resource =
          Map.get(attribute, :resource) ||
            raise("attribute must have :resource for required!")

        field =
          Map.get(attribute, :name) ||
            Map.get(attribute, "name") ||
            raise("attribute must have :name for required!")

        {:error,
         Ash.Error.Changes.Required.exception(
           field: field,
           type: :attribute,
           resource: resource
         )}
      else
        {:known, value}
      end
    end

    @impl true
    def can_return_nil?(_), do: false

    @impl true
    def evaluate_nil_inputs?, do: true

    @impl true
    def returns, do: :unknown
  end
end

