defmodule AshPostgres.MigrationGenerator.Phase do
  @moduledoc false

  defmodule Create do
    @moduledoc false
    defstruct [:table, :multitenancy, operations: [], commented?: false]

    def up(%{table: table, operations: operations, multitenancy: multitenancy}) do
      if multitenancy.strategy == :context do
        "create table(:#{table}, primary_key: false, prefix: prefix) do\n" <>
          Enum.map_join(operations, "\n", fn operation -> operation.__struct__.up(operation) end) <>
          "\nend"
      else
        "create table(:#{table}, primary_key: false) do\n" <>
          Enum.map_join(operations, "\n", fn operation -> operation.__struct__.up(operation) end) <>
          "\nend"
      end
    end

    def down(%{table: table, multitenancy: multitenancy}) do
      if multitenancy.strategy == :context do
        "drop table(#{inspect(table)}, prefix: prefix)"
      else
        "drop table(#{inspect(table)})"
      end
    end
  end

  defmodule Alter do
    @moduledoc false
    defstruct [:table, :multitenancy, operations: [], commented?: false]

    def up(%{table: table, operations: operations, multitenancy: multitenancy}) do
      body =
        Enum.map_join(operations, "\n", fn operation -> operation.__struct__.up(operation) end)

      if multitenancy.strategy == :context do
        "alter table(:#{table}, prefix: prefix) do\n" <>
          body <>
          "\nend"
      else
        "alter table(:#{table}) do\n" <>
          body <>
          "\nend"
      end
    end

    def down(%{table: table, operations: operations, multitenancy: multitenancy}) do
      body =
        operations
        |> Enum.reverse()
        |> Enum.map_join("\n", fn operation -> operation.__struct__.down(operation) end)

      if multitenancy.strategy == :context do
        "alter table(:#{table}, prefix: prefix) do\n" <>
          body <>
          "\nend"
      else
        "alter table(:#{table}) do\n" <>
          body <>
          "\nend"
      end
    end
  end
end
