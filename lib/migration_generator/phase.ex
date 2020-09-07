defmodule AshPostgres.MigrationGenerator.Phase do
  defmodule Create do
    defstruct [:table, operations: []]

    def up(%{table: table, operations: operations}) do
      "create table(#{inspect(table)}, primary_key: false) do\n" <>
        Enum.map_join(operations, "\n", fn operation -> operation.__struct__.up(operation) end) <>
        "\nend"
    end

    def down(%{table: table}) do
      "drop table(#{inspect(table)})"
    end
  end

  defmodule Alter do
    defstruct [:table, operations: []]

    def up(%{table: table, operations: operations}) do
      body =
        Enum.map_join(operations, "\n", fn operation -> operation.__struct__.up(operation) end)

      "alter table(#{inspect(table)}) do\n" <>
        body <>
        "\nend"
    end

    def down(%{table: table, operations: operations}) do
      body =
        operations
        |> Enum.reverse()
        |> Enum.map_join("\n", fn operation -> operation.__struct__.down(operation) end)

      "alter table(#{inspect(table)}) do\n" <>
        body <>
        "\nend"
    end
  end
end
