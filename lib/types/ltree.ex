defmodule AshPostgres.Ltree do
  @constraints [
    escape?: [
      type: :boolean,
      doc: """
      Escape the ltree segments to make it possible to include characters that
      are either `.` (the separation character) or any other unsupported
      character like `-` (Postgres <= 15).  
        
      If the option is enabled, any characters besides `[0-9a-zA-Z]` will be
      replaced with `_[HEX Ascii Code]`.  
        
      Additionally the type will no longer take strings as user input since
      it's impossible to decide between `.` being a separator or part of a
      segment.  
        
      If the option is disabled, any string will be relayed directly to
      postgres. If the segments are provided as a list, they can't contain `.`
      since postgres would split the segment.
      """
    ],
    min_length: [
      type: :non_neg_integer,
      doc: "A minimum length for the tree segments."
    ],
    max_length: [
      type: :non_neg_integer,
      doc: "A maximum length for the tree segments."
    ]
  ]

  @moduledoc """
  Ash Type for [postgres `ltree`](https://www.postgresql.org/docs/current/ltree.html),
  a hierarchical tree-like data type.

  ## Postgres Extension

  To be able to use the `ltree` type, you'll have to enable the postgres `ltree`
  extension first.

  See `m:AshPostgres.Repo#module-installed-extensions`

  ## Constraints

  #{Spark.Options.docs(@constraints)}
  """

  use Ash.Type

  @type t() :: [segment()]
  @type segment() :: String.t()

  @impl Ash.Type
  def storage_type(_constraints), do: :ltree

  @impl Ash.Type
  def constraints, do: @constraints

  @impl Ash.Type
  def matches_type?(list, _constraints) when is_list(list), do: true

  def matches_type?(binary, constraints) when is_binary(binary),
    do: not Keyword.get(constraints, :escape?, false)

  def matches_type?(_ltree, _constraints), do: false

  @impl Ash.Type
  def generator(constraints) do
    segment =
      if constraints[:escape?],
        do: StreamData.string(:utf8, min_length: 1),
        else: StreamData.string(:alphanumeric, min_length: 1)

    StreamData.list_of(segment, Keyword.take(constraints, [:min_length, :max_length]))
  end

  @impl Ash.Type
  def apply_constraints(nil, _constraints), do: {:ok, nil}

  def apply_constraints(ltree, constraints) do
    segment_validation =
      Enum.reduce_while(ltree, :ok, fn segment, :ok ->
        cond do
          segment == "" ->
            {:halt, {:error, message: "Ltree segments can't be empty.", value: segment}}

          not String.valid?(segment) ->
            {:halt,
             {:error, message: "Ltree segments must be valid UTF-8 strings.", value: segment}}

          String.contains?(segment, ".") and !constraints[:escape?] ->
            {:halt,
             {:error,
              message: ~S|Ltree segments can't contain "." if :escape? is not enabled.|,
              value: segment}}

          true ->
            {:cont, :ok}
        end
      end)

    with :ok <- segment_validation do
      cond do
        constraints[:min_length] && length(ltree) < constraints[:min_length] ->
          {:error, message: "must have %{min} or more items", min: constraints[:min_length]}

        constraints[:max_length] && length(ltree) > constraints[:max_length] ->
          {:error, message: "must have %{max} or less items", max: constraints[:max_length]}

        true ->
          :ok
      end
    end
  end

  @impl Ash.Type
  def cast_input(nil, _constraints), do: {:ok, nil}

  def cast_input(string, constraints) when is_binary(string) do
    if constraints[:escape?] do
      {:error, "String input casting is not supported when the :escape? constraint is enabled"}
    else
      string |> String.split(".") |> cast_input(constraints)
    end
  end

  def cast_input(list, _constraints) when is_list(list) do
    if Enum.all?(list, &is_binary/1) do
      {:ok, list}
    else
      {:error, "Ltree segments must be strings. #{inspect(list)} provided."}
    end
  end

  def cast_input(_ltree, _constraints), do: :error

  @impl Ash.Type
  def cast_stored(nil, _constraints), do: {:ok, nil}

  def cast_stored(ltree, constraints) when is_binary(ltree) do
    segments =
      ltree
      |> String.split(".", trim: true)
      |> then(
        if constraints[:escape?] do
          fn segments -> Enum.map(segments, &unescape_segment/1) end
        else
          & &1
        end
      )

    {:ok, segments}
  end

  def cast_stored(_ltree, _constraints), do: :error

  @impl Ash.Type
  def dump_to_native(nil, _constraints), do: {:ok, nil}

  def dump_to_native(ltree, constraints) when is_list(ltree) do
    if constraints[:escape?] do
      {:ok, Enum.map_join(ltree, ".", &escape_segment/1)}
    else
      {:ok, Enum.join(ltree, ".")}
    end
  end

  def dump_to_native(_ltree, _constraints), do: :error

  @doc """
  Get shared root of given ltrees.

  ## Examples

      iex> Ltree.shared_root(["1", "2"], ["1", "1"])
      ["1"]

      iex> Ltree.shared_root(["1", "2"], ["2", "1"])
      []

  """
  @spec shared_root(ltree1 :: t(), ltree2 :: t()) :: t()
  def shared_root(ltree1, ltree2) do
    ltree1
    |> List.myers_difference(ltree2)
    |> case do
      [{:eq, shared} | _] -> shared
      _other -> []
    end
  end

  @spec escape_segment(segment :: String.t()) :: String.t()
  defp escape_segment(segment)
  defp escape_segment(<<>>), do: <<>>

  defp escape_segment(<<letter, rest::binary>>)
       when letter in ?0..?9
       when letter in ?a..?z
       when letter in ?A..?Z,
       do: <<letter, escape_segment(rest)::binary>>

  defp escape_segment(<<letter, rest::binary>>) do
    escape_code = letter |> Integer.to_string(16) |> String.pad_leading(2, "0")
    <<?_, escape_code::binary, escape_segment(rest)::binary>>
  end

  @spec unescape_segment(segment :: String.t()) :: String.t()
  defp unescape_segment(segment)
  defp unescape_segment(<<>>), do: <<>>

  defp unescape_segment(<<letter, rest::binary>>)
       when letter in ?0..?9
       when letter in ?a..?z
       when letter in ?A..?Z,
       do: <<letter, unescape_segment(rest)::binary>>

  defp unescape_segment(<<?_, h, l, rest::binary>>) do
    {letter, ""} = Integer.parse(<<h, l>>, 16)
    <<letter, unescape_segment(rest)::binary>>
  end
end
