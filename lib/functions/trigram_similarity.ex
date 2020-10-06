defmodule AshPostgres.Functions.TrigramSimilarity do
  @moduledoc """
  A filter predicate that filters based on trigram similarity.

  See the postgres docs on [https://www.postgresql.org/docs/9.6/pgtrgm.html](trigram) for more information.

  Requires the pg_trgm extension. Configure which extensions you have installed in your `AshPostgres.Repo`

  At least one of the `equals`, `greater_than` and `less_than`

      # Example

      filter(query, [trigram_similarity: [:name, "geoff", [greater_than: 0.4]]])
  """

  use Ash.Query.Function, name: :trigram_similarity

  def args, do: [:ref, :term, {:options, [:less_than, :greater_than, :equals]}]

  def new([_, text | _]) when not is_binary(text) do
    {:error, "#{Ash.Query.Function.ordinal(2)} argument must be a string, got #{text}"}
  end

  def new([%Ref{} = ref, text, opts]) do
    with :ok <- required_options_provided(opts),
         {:ok, less_than} <- validate_similarity(opts[:less_than]),
         {:ok, greater_than} <- validate_similarity(opts[:greater_than]),
         {:ok, equals} <- validate_similarity(opts[:equals]) do
      new_options = [
        less_than: less_than,
        greater_than: greater_than,
        equals: equals
      ]

      {:ok,
       %__MODULE__{
         arguments: [
           ref,
           text,
           new_options
         ]
       }}
    else
      _ ->
        {:error,
         "Invalid options for `trigram_similarity` in the #{Ash.Query.Function.ordinal(3)} argument"}
    end
  end

  def compare(%__MODULE__{arguments: [ref]}, %Ash.Query.Operator.IsNil{left: ref}) do
    :mutually_exclusive
  end

  def compare(_, _), do: :unknown

  defp validate_similarity(nil), do: {:ok, nil}
  defp validate_similarity(1), do: {:ok, 1.0}
  defp validate_similarity(0), do: {:ok, 0.0}

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
    case {opts[:greater_than], opts[:less_than], opts[:equals]} do
      {nil, nil, nil} -> :error
      {nil, nil, _equals} -> :ok
      {_greater_than, nil, nil} -> :ok
      {nil, _less_than, nil} -> :ok
      {_greater_than, _less_than, nil} -> :ok
    end
  end
end
