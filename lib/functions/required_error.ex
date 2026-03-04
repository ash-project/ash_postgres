# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Functions.RequiredError do
  @moduledoc """
  Expression that returns the value if present, or an error if nil.
  Used for required-attribute validation (Part B): `ash_required!(^value, ^attribute)`.

  When the data layer supports `:required_error`, Ash can build
  `expr(ash_required!(^value, ^attribute))` instead of the inline if/is_nil/error block.
  This module is returned from the data layer's `functions/1` so the expression is available
  when using AshPostgres.
  """
  use Ash.Query.Function, name: :ash_required!, predicate?: false

  @impl true
  def args, do: [[:any, :any]]

  @impl true
  def new([value_expr, attribute]) when is_struct(attribute) or is_map(attribute) do
    {:ok, %__MODULE__{arguments: [value_expr, attribute]}}
  end

  def new(_), do: {:error, "ash_required! expects (value, attribute)"}

  @impl true
  def evaluate(%{arguments: [value, attribute]}) do
    if is_nil(value) do
      resource =
        Map.get(attribute, :resource) || raise("attribute must have :resource for ash_required!")

      field =
        Map.get(attribute, :name) || Map.get(attribute, "name") ||
          raise("attribute must have :name for ash_required!")

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
