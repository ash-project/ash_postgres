defmodule AshPostgres.CustomIndex do
  @moduledoc "Represents a custom index on the table backing a resource"
  @fields [
    :table,
    :fields,
    :error_fields,
    :name,
    :unique,
    :concurrently,
    :using,
    :prefix,
    :where,
    :include,
    :nulls_distinct,
    :message,
    :all_tenants?
  ]

  defstruct @fields

  def fields, do: @fields

  @schema [
    fields: [
      type: {:wrap_list, {:or, [:atom, :string]}},
      doc: "The fields to include in the index."
    ],
    error_fields: [
      type: {:list, :atom},
      doc: "The fields to attach the error to."
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
    include: [
      type: {:list, :string},
      doc:
        "specify fields for a covering index. This is not supported by all databases. For more information on PostgreSQL support, please read the official docs."
    ],
    nulls_distinct: [
      type: :boolean,
      doc:
        "specify whether null values should be considered distinct for a unique index. Requires PostgreSQL 15 or later",
      default: true
    ],
    message: [
      type: :string,
      doc: "A custom message to use for unique indexes that have been violated"
    ],
    all_tenants?: [
      type: :boolean,
      default: false,
      doc: "Whether or not the index should factor in the multitenancy attribute or not."
    ]
  ]

  def schema, do: @schema

  def transform(index) do
    with {:ok, index} <- set_name(index) do
      set_error_fields(index)
    end
  end

  # sobelow_skip ["DOS.StringToAtom"]
  defp set_error_fields(index) do
    if index.error_fields do
      {:ok, index}
    else
      {:ok,
       %{
         index
         | error_fields:
             Enum.flat_map(index.fields, fn field ->
               if Regex.match?(~r/^[0-9a-zA-Z_]+$/, to_string(field)) do
                 if is_binary(field) do
                   [String.to_atom(field)]
                 else
                   [field]
                 end
               else
                 []
               end
             end)
       }}
    end
  end

  defp set_name(index) do
    cond do
      index.name ->
        if Regex.match?(~r/^[0-9a-zA-Z_]+$/, index.name) do
          {:ok, index}
        else
          {:error,
           "Custom index name #{index.name} is not valid. Must have letters, numbers and underscores only"}
        end

      mismatched_field =
          Enum.find(index.fields, fn field ->
            !Regex.match?(~r/^[0-9a-zA-Z_]+$/, to_string(field))
          end) ->
        {:error,
         """
         Custom index field #{mismatched_field} contains invalid index name characters.

         A name must be set manually, i.e

             `name: "your_desired_index_name"`

         Index names must have letters, numbers and underscores only
         """}

      true ->
        {:ok, index}
    end
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
