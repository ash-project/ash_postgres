defmodule AshPostgres.MigrationGenerator.Phase do
  @moduledoc false

  defmodule Create do
    @moduledoc false
    defstruct [:table, operations: []]

    def up(%{table: table, operations: operations}) do
      "create table(:#{table}, primary_key: false) do\n" <>
        Enum.map_join(operations, "\n", fn operation -> operation.__struct__.up(operation) end) <>
        "\nend"
    end

    def down(%{table: table}) do
      "drop table(#{inspect(table)})"
    end
  end

  defmodule Alter do
    @moduledoc false
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

      "alter table(:#{table}) do\n" <>
        body <>
        "\nend"
    end
  end
end
