defmodule AshPostgres.MigrationGenerator.Operation do
  @moduledoc false
  defmodule CreateTable do
    @moduledoc false
    defstruct [:table]
  end

  defmodule AddAttribute do
    @moduledoc false
    defstruct [:attribute, :table]

    def up(%{
          attribute:
            %{references: %{table: table, destination_field: destination_field}} = attribute
        }) do
      "add #{inspect(attribute.name)}, references(#{inspect(table)}, type: #{
        inspect(attribute.type)
      }, column: #{inspect(destination_field)}), default: #{attribute.default}, primary_key: #{
        attribute.primary_key?
      }"
    end

    def up(%{attribute: attribute}) do
      "add #{inspect(attribute.name)}, #{inspect(attribute.type)}, null: #{attribute.allow_nil?}, default: #{
        attribute.default
      }, primary_key: #{attribute.primary_key?}"
    end

    def down(%{attribute: attribute}) do
      "remove #{inspect(attribute.name)}"
    end
  end

  defmodule AlterAttribute do
    @moduledoc false
    defstruct [:old_attribute, :new_attribute, :table]

    def up(%{
          new_attribute:
            %{references: %{table: table, destination_field: destination_field}} = attribute
        }) do
      "modify #{inspect(attribute.name)}, references(#{inspect(table)}, type: #{
        inspect(attribute.type)
      }, column: #{inspect(destination_field)}), default: #{attribute.default}, primary_key: #{
        attribute.primary_key?
      }"
    end

    def up(%{new_attribute: attribute}) do
      "modify #{inspect(attribute.name)}, #{inspect(attribute.type)}, null: #{
        attribute.allow_nil?
      }, default: #{attribute.default}, primary_key: #{attribute.primary_key?}"
    end

    def down(%{
          old_attribute:
            %{references: %{table: table, destination_field: destination_field}} = attribute
        }) do
      "modify #{inspect(attribute.name)}, references(#{inspect(table)}, type: #{
        inspect(attribute.type)
      }, column: #{inspect(destination_field)}), default: #{attribute.default}, primary_key: #{
        attribute.primary_key?
      }"
    end

    def down(%{old_attribute: attribute}) do
      "modify #{inspect(attribute.name)}, #{inspect(attribute.type)}, null: #{
        attribute.allow_nil?
      }, default: #{attribute.default}, primary_key: #{attribute.primary_key?}"
    end
  end

  defmodule RenameAttribute do
    @moduledoc false
    defstruct [:old_attribute, :new_attribute, :table]

    def up(%{old_attribute: old_attribute, new_attribute: new_attribute, table: table}) do
      "rename table(:#{table}), #{inspect(old_attribute.name)}, to: #{inspect(new_attribute.name)}"
    end

    def down(%{new_attribute: old_attribute, old_attribute: new_attribute, table: table}) do
      "rename table(:#{table}), #{inspect(old_attribute.name)}, to: #{inspect(new_attribute.name)}"
    end
  end

  defmodule RemoveAttribute do
    @moduledoc false
    defstruct [:attribute, :table]

    def up(%{attribute: attribute}) do
      "remove #{inspect(attribute.name)}"
    end

    def down(%{
          attribute:
            %{references: %{table: table, destination_field: destination_field}} = attribute
        }) do
      "add #{inspect(attribute.name)}, references(#{inspect(table)}, type: #{
        inspect(attribute.type)
      }, column: #{inspect(destination_field)}), default: #{attribute.default}, primary_key: #{
        attribute.primary_key?
      }"
    end

    def down(%{attribute: attribute}) do
      "add #{inspect(attribute.name)}, #{inspect(attribute.type)}, null: #{attribute.allow_nil?}, default: #{
        attribute.default
      }, primary_key: #{attribute.primary_key?}"
    end
  end

  defmodule AddUniqueIndex do
    @moduledoc false
    defstruct [:identity, :table]

    def up(%{identity: %{name: name, keys: keys}, table: table}) do
      "create unique_index(:#{table}, [#{Enum.map_join(keys, ",", &inspect/1)}], name: \"#{table}_#{
        name
      }_unique_index\")"
    end

    def down(%{identity: %{name: name, keys: keys}, table: table}) do
      # {
      "drop unique_index(:#{table}, [#{Enum.map_join(keys, ",", &inspect/1)}], name: \"#{table}_#{
        name
      }_unique_index\")"
    end
  end

  defmodule RemoveUniqueIndex do
    @moduledoc false
    defstruct [:identity, :table]

    def up(%{identity: %{name: name, keys: keys}, table: table}) do
      "drop unique_index(:#{table}, [#{Enum.map_join(keys, ",", &inspect/1)}], name: \"#{table}_#{
        name
      }_unique_index\")"
    end

    def down(%{identity: %{name: name, keys: keys}, table: table}) do
      "create unique_index(:#{table}, [#{Enum.map_join(keys, ",", &inspect/1)}], name: \"#{table}_#{
        name
      }_unique_index\")"
    end
  end
end
