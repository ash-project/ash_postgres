defmodule AshPostgres.Functions.Fragment do
  @moduledoc """
  A function that maps to ecto's `fragment` function

  https://hexdocs.pm/ecto/Ecto.Query.API.html#fragment/1
  """

  use Ash.Query.Function, name: :fragment

  def private?, do: true

  # Varargs is special, and should only be used in rare circumstances (like this one)
  # no type casting or help can be provided for these functions.
  def args, do: :var_args

  def new([fragment | _]) when not is_binary(fragment) do
    {:error, "First argument to `fragment` must be a string."}
  end

  def new([fragment | rest]) do
    split = split_fragment(fragment)

    if Enum.count(split, &(&1 == :slot)) != length(rest) do
      {:error,
       "fragment(...) expects extra arguments in the same amount of question marks in string. " <>
         "It received #{Enum.count(split, &(&1 == :slot))} extra argument(s) but expected #{length(rest)}"}
    else
      {:ok, %__MODULE__{arguments: merge_fragment(split, rest)}}
    end
  end

  def casted_new([fragment | _]) when not is_binary(fragment) do
    {:error, "First argument to `fragment` must be a string."}
  end

  def casted_new([fragment | rest]) do
    split = split_fragment(fragment)

    if Enum.count(split, &(&1 == :slot)) != length(rest) do
      {:error,
       "fragment(...) expects extra arguments in the same amount of question marks in string. " <>
         "It received #{Enum.count(split, &(&1 == :slot))} extra argument(s) but expected #{length(rest)}"}
    else
      {:ok, %__MODULE__{arguments: merge_fragment(split, rest, :casted_expr)}}
    end
  end

  defp merge_fragment(expr, args, tag \\ :expr)
  defp merge_fragment([], [], _tag), do: []

  defp merge_fragment([:slot | rest], [arg | rest_args], tag) do
    [{tag, arg} | merge_fragment(rest, rest_args, tag)]
  end

  defp merge_fragment([val | rest], rest_args, tag) do
    [{:raw, val} | merge_fragment(rest, rest_args, tag)]
  end

  defp split_fragment(frag, consumed \\ "")

  defp split_fragment(<<>>, consumed),
    do: [consumed]

  defp split_fragment(<<??, rest::binary>>, consumed),
    do: [consumed, :slot | split_fragment(rest, "")]

  defp split_fragment(<<?\\, ??, rest::binary>>, consumed),
    do: split_fragment(rest, consumed <> <<??>>)

  defp split_fragment(<<first::utf8, rest::binary>>, consumed),
    do: split_fragment(rest, consumed <> <<first::utf8>>)
end
