defmodule AshPostgres.Predicates.Trigram do
  @moduledoc """
  A filter predicate that filters based on trigram similarity.

  See the postgres docs on [https://www.postgresql.org/docs/9.6/pgtrgm.html](trigram) for more information.

  Requires the pg_trgm extension. Configure which extensions you have installed in your `AshPostgres.Repo`

      # Example

      filter(query, name: [trigram: [text: "geoff", greater_than: 0.4]])
  """

  alias Ash.Error.Filter.InvalidFilterValue
  defstruct [:text, :greater_than, :less_than, :equals]

  def new(_resource, attr_name, attr_type, opts) do
    with :ok <- required_options_provided(opts),
         {:ok, value} <- Ash.Type.cast_input(attr_type, opts[:text]),
         {:ok, less_than} <- validate_similarity(opts[:less_than]),
         {:ok, greater_than} <- validate_similarity(opts[:greater_than]),
         {:ok, equals} <- validate_similarity(opts[:equals]) do
      {:ok,
       %__MODULE__{text: value, greater_than: greater_than, less_than: less_than, equals: equals}}
    else
      _ ->
        {:error,
         InvalidFilterValue.exception(
           filter: %__MODULE__{
             text: opts[:text],
             less_than: opts[:less_than],
             greater_than: opts[:greater_than],
             equals: opts[:equals]
           },
           value: opts,
           field: attr_name
         )}
    end
  end

  defp validate_similarity(nil), do: {:ok, nil}
  defp validate_similarity(1), do: {:ok, 1}
  defp validate_similarity(0), do: {:ok, 0}

  defp validate_similarity(similarity)
       when is_float(similarity) and similarity <= 1.0 and similarity >= 0.0 do
    {:ok, similarity}
  end

  defp validate_similarity(similarity) when is_binary(similarity) do
    sanitized =
      case similarity do
        "." <> decimal_part -> "0." <> decimal_part
        other -> other
      end

    case Float.parse(sanitized) do
      {float, ""} -> {:ok, float}
      _ -> :error
    end
  end

  defp required_options_provided(opts) do
    if Keyword.has_key?(opts, :text) do
      case {opts[:greater_than], opts[:less_than], opts[:equals]} do
        {nil, nil, nil} -> :error
        {nil, nil, _equals} -> :ok
        {_greater_than, nil, nil} -> :ok
        {nil, _less_than, nil} -> :ok
        {_greater_than, _less_than, nil} -> :ok
      end
    else
      :error
    end
  end
end

defimpl Inspect, for: AshPostgres.Predicates.Trigram do
  import Inspect.Algebra
  import Ash.Filter.InspectHelpers

  def inspect(%{text: text, equals: nil, less_than: nil, greater_than: greater_than}, opts) do
    concat([
      attr(opts),
      " trigram similarity to ",
      to_doc(text, opts),
      " is greater than ",
      to_doc(greater_than, opts)
    ])
  end

  def inspect(%{text: text, equals: nil, less_than: less_than, greater_than: nil}, opts) do
    concat([
      attr(opts),
      " trigram similarity to ",
      to_doc(text, opts),
      " is less than ",
      to_doc(less_than, opts)
    ])
  end

  def inspect(%{text: text, equals: nil, less_than: less_than, greater_than: greater_than}, opts) do
    concat([
      attr(opts),
      " trigram similarity to ",
      to_doc(text, opts),
      " is between ",
      to_doc(less_than, opts),
      " and ",
      to_doc(greater_than, opts)
    ])
  end

  def inspect(%{text: text, equals: equals, less_than: nil, greater_than: nil}, opts) do
    concat([
      attr(opts),
      " trigram similarity to ",
      to_doc(text, opts),
      " == ",
      to_doc(equals, opts)
    ])
  end
end
