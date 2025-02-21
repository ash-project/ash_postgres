defmodule AshPostgres.MigrationGenerator.Phase do
  @moduledoc false

  defmodule Create do
    @moduledoc false
    defstruct [
      :table,
      :schema,
      :multitenancy,
      partitioning: nil,
      operations: [],
      commented?: false
    ]

    import AshPostgres.MigrationGenerator.Operation.Helper, only: [as_atom: 1]

    def up(%{
          schema: schema,
          table: table,
          operations: operations,
          multitenancy: multitenancy,
          partitioning: partitioning
        }) do
      if multitenancy.strategy == :context do
        arguments = arguments([prefix(true), options(partitioning: partitioning)])

        "create table(:#{as_atom(table)}, primary_key: false#{arguments}) do\n" <>
          Enum.map_join(operations, "\n", fn operation -> operation.__struct__.up(operation) end) <>
          "\nend"
      else
        arguments = arguments([prefix(schema), options(partitioning: partitioning)])

        "create table(:#{as_atom(table)}, primary_key: false#{arguments}) do\n" <>
          Enum.map_join(operations, "\n", fn operation -> operation.__struct__.up(operation) end) <>
          "\nend"
      end
    end

    def down(%{schema: schema, table: table, multitenancy: multitenancy}) do
      if multitenancy.strategy == :context do
        "drop table(:#{as_atom(table)}, prefix: prefix())"
      else
        opts =
          if schema do
            ", prefix: \"#{schema}\""
          else
            ""
          end

        "drop table(:#{as_atom(table)}#{opts})"
      end
    end

    def arguments([nil, nil]), do: ""
    def arguments(arguments), do: ", " <> Enum.join(Enum.reject(arguments, &is_nil(&1)), ",")

    def prefix(true), do: "prefix: prefix()"
    def prefix(schema) when is_binary(schema) and schema != "", do: "prefix: \"#{schema}\""
    def prefix(_), do: nil

    def options(_options, _acc \\ [])
    def options([], []), do: nil
    def options([], acc), do: "options: \"#{Enum.join(acc, " ")}\""

    def options([{:partitioning, %{method: method, attribute: attribute}} | rest], acc) do
      option = "PARTITION BY #{String.upcase(Atom.to_string(method))} (#{attribute})"

      rest
      |> options(acc ++ [option])
    end

    def options([_ | rest], acc) do
      options(rest, acc)
    end
  end

  defmodule Alter do
    @moduledoc false
    defstruct [:schema, :table, :multitenancy, operations: [], commented?: false]

    import AshPostgres.MigrationGenerator.Operation.Helper, only: [as_atom: 1]

    def up(%{table: table, schema: schema, operations: operations, multitenancy: multitenancy}) do
      body =
        operations
        |> Enum.map_join("\n", fn operation -> operation.__struct__.up(operation) end)
        |> String.trim()

      if body == "" do
        ""
      else
        if multitenancy.strategy == :context do
          "alter table(:#{as_atom(table)}, prefix: prefix()) do\n" <>
            body <>
            "\nend"
        else
          opts =
            if schema do
              ", prefix: \"#{schema}\""
            else
              ""
            end

          "alter table(:#{as_atom(table)}#{opts}) do\n" <>
            body <>
            "\nend"
        end
      end
    end

    def down(%{table: table, schema: schema, operations: operations, multitenancy: multitenancy}) do
      body =
        operations
        |> Enum.reverse()
        |> Enum.map_join("\n", fn operation -> operation.__struct__.down(operation) end)
        |> String.trim()

      if body == "" do
        ""
      else
        if multitenancy.strategy == :context do
          "alter table(:#{as_atom(table)}, prefix: prefix()) do\n" <>
            body <>
            "\nend"
        else
          opts =
            if schema do
              ", prefix: \"#{schema}\""
            else
              ""
            end

          "alter table(:#{as_atom(table)}#{opts}) do\n" <>
            body <>
            "\nend"
        end
      end
    end
  end
end
