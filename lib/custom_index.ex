defmodule AshPostgres.CustomIndex do
  @moduledoc false
  defstruct [
    :table,
    :fields,
    :name,
    :unique,
    :concurrently,
    :using,
    :prefix,
    :where,
    :include,
    :message
  ]

  @schema [
    fields: [
      type: {:list, {:or, [:atom, :string]}},
      doc: "The fields to include in the index."
    ],
    name: [
      type: :string,
      doc: "the name of the index. Defaults to \"\#\{table\}_\#\{column\}_index\"."
    ],
    unique: [
      type: :boolean,
      doc: "indicates whether the index should be unique.",
      default: false
    ],
    concurrently: [
      type: :boolean,
      doc: "indicates whether the index should be created/dropped concurrently.",
      default: false
    ],
    using: [
      type: :string,
      doc: "configures the index type."
    ],
    prefix: [
      type: :string,
      doc: "specify an optional prefix for the index."
    ],
    where: [
      type: :string,
      doc: "specify conditions for a partial index."
    ],
    message: [
      type: :string,
      doc: "A custom message to use for unique indexes that have been violated"
    ],
    include: [
      type: {:list, :string},
      doc:
        "specify fields for a covering index. This is not supported by all databases. For more information on PostgreSQL support, please read the official docs."
    ]
  ]

  def schema, do: @schema

  # sobelow_skip ["DOS.StringToAtom"]
  def transform(%__MODULE__{fields: fields} = index) do
    %{
      index
      | fields:
          Enum.map(fields, fn field ->
            if is_atom(field) do
              field
            else
              String.to_atom(field)
            end
          end)
    }
  end

  def name(_resource, %{name: name}) when is_binary(name) do
    name
  end

  # sobelow_skip ["DOS.StringToAtom"]
  def name(table, %{fields: fields}) do
    [table, fields, "index"]
    |> List.flatten()
    |> Enum.map(&to_string(&1))
    |> Enum.map(&String.replace(&1, ~r"[^\w_]", "_"))
    |> Enum.map_join("_", &String.replace_trailing(&1, "_", ""))
    |> String.to_atom()
  end
end
