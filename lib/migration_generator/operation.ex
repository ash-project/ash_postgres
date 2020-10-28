defmodule AshPostgres.MigrationGenerator.Operation do
  @moduledoc false
  defmodule CreateTable do
    @moduledoc false
    defstruct [:table, :multitenancy, :old_multitenancy]
  end

  defmodule AddAttribute do
    @moduledoc false
    defstruct [:attribute, :table, :multitenancy, :old_multitenancy]

    def up(%{
          multitenancy: %{strategy: :attribute, attribute: source_attribute},
          attribute:
            %{
              references: %{
                table: table,
                destination_field: destination_field,
                multitenancy: %{strategy: :attribute, attribute: destination_attribute}
              }
            } = attribute
        }) do
      "add #{inspect(attribute.name)}, references(#{inspect(table)}, type: #{
        inspect(attribute.type)
      }, column: #{inspect(destination_field)}), with: [#{source_attribute}: :#{
        destination_attribute
      }], default: #{attribute.default}, primary_key: #{attribute.primary_key?}"
    end

    def up(%{
          multitenancy: %{strategy: :context},
          attribute:
            %{
              references: %{
                table: table,
                destination_field: destination_field,
                multitenancy: %{strategy: :attribute}
              }
            } = attribute
        }) do
      "add #{inspect(attribute.name)}, references(#{inspect(table)}, type: #{
        inspect(attribute.type)
      }, column: #{inspect(destination_field)}, name: \"\#\{prefix\}_#{table}_#{attribute.name}_fkey\", prefix: \"public\"), default: #{
        attribute.default
      }, primary_key: #{attribute.primary_key?}"
    end

    def up(%{
          multitenancy: %{strategy: :attribute},
          table: current_table,
          attribute:
            %{
              references: %{
                table: table,
                destination_field: destination_field,
                multitenancy: %{strategy: :context}
              }
            } = attribute
        }) do
      Mix.shell().info("""
      table `#{current_table}` with attribute multitenancy refers to table `#{table}` with schema based multitenancy.
      This means that it is not possible to use a foreign key. This is not necessarily a problem, just something
      you should be aware of
      """)

      "add #{inspect(attribute.name)}, references(#{inspect(table)}, type: #{
        inspect(attribute.type)
      }, column: #{inspect(destination_field)}), default: #{attribute.default}, primary_key: #{
        attribute.primary_key?
      }"
    end

    def up(%{
          multitenancy: %{strategy: :context},
          attribute:
            %{references: %{table: table, destination_field: destination_field}} = attribute
        }) do
      "add #{inspect(attribute.name)}, references(#{inspect(table)}, type: #{
        inspect(attribute.type)
      }, column: #{inspect(destination_field)}, name: \"\#\{prefix\}_#{table}_#{attribute.name}_fkey\"), default: #{
        attribute.default
      }, primary_key: #{attribute.primary_key?}"
    end

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
    defstruct [:old_attribute, :new_attribute, :table, :multitenancy, :old_multitenancy]

    def up(%{
          multitenancy: %{strategy: :attribute},
          table: current_table,
          new_attribute: %{table: table} = attribute
        }) do
      Mix.shell().info("""
      table `#{current_table}` with attribute multitenancy refers to table `#{table}` with schema based multitenancy.
      This means that it is not possible to use a foreign key. This is not necessarily a problem, just something
      you should be aware of
      """)

      "modify #{inspect(attribute.name)}, #{inspect(attribute.type)}, null: #{
        attribute.allow_nil?
      }, default: #{attribute.default}, primary_key: #{attribute.primary_key?}"
    end

    def up(%{
          multitenancy: %{strategy: :context},
          new_attribute:
            %{
              references: %{
                table: table,
                destination_field: destination_field,
                multitenancy: %{strategy: :attribute}
              }
            } = attribute
        }) do
      "modify #{inspect(attribute.name)}, references(#{inspect(table)}, type: #{
        inspect(attribute.type)
      }, column: #{inspect(destination_field)}), default: #{attribute.default}, primary_key: #{
        attribute.primary_key?
      }"
    end

    def up(%{
          multitenancy: %{strategy: :attribute, attribute: source_attribute},
          new_attribute:
            %{
              references: %{
                table: table,
                destination_field: destination_field,
                multitenancy: %{strategy: :attribute, attribute: destination_attribute}
              }
            } = attribute
        }) do
      "modify #{inspect(attribute.name)}, references(#{inspect(table)}, type: #{
        inspect(attribute.type)
      }, column: #{inspect(destination_field)}), with: [#{source_attribute}: :#{
        destination_attribute
      }], default: #{attribute.default}, primary_key: #{attribute.primary_key?}"
    end

    def up(%{
          new_attribute:
            %{
              references: %{
                table: table,
                destination_field: destination_field
              }
            } = attribute
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

    def up(%{
          old_multitenancy: %{strategy: :attribute},
          old_attribute: %{references: %{multitenancy: %{strategy: :context}}} = attribute
        }) do
      "modify #{inspect(attribute.name)}, #{inspect(attribute.type)}, null: #{
        attribute.allow_nil?
      }, default: #{attribute.default}, primary_key: #{attribute.primary_key?}"
    end

    def up(%{
          old_multitenancy: %{strategy: :context},
          old_attribute:
            %{
              references: %{
                table: table,
                destination_field: destination_field,
                multitenancy: %{strategy: :attribute}
              }
            } = attribute
        }) do
      "modify #{inspect(attribute.name)}, references(#{inspect(table)}, type: #{
        inspect(attribute.type)
      }, column: #{inspect(destination_field)}), default: #{attribute.default}, primary_key: #{
        attribute.primary_key?
      }"
    end

    def up(%{
          old_multitenancy: %{strategy: :attribute, attribute: source_attribute},
          old_attribute:
            %{
              references: %{
                table: table,
                destination_field: destination_field,
                multitenancy: %{strategy: :attribute, attribute: destination_attribute}
              }
            } = attribute
        }) do
      "modify #{inspect(attribute.name)}, references(#{inspect(table)}, type: #{
        inspect(attribute.type)
      }, column: #{inspect(destination_field)}), with: [#{source_attribute}: :#{
        destination_attribute
      }], default: #{attribute.default}, primary_key: #{attribute.primary_key?}"
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
    defstruct [:old_attribute, :new_attribute, :table, :multitenancy, :old_multitenancy]

    def up(%{old_attribute: old_attribute, new_attribute: new_attribute, table: table}) do
      "rename table(:#{table}), #{inspect(old_attribute.name)}, to: #{inspect(new_attribute.name)}"
    end

    def down(%{new_attribute: old_attribute, old_attribute: new_attribute, table: table}) do
      "rename table(:#{table}), #{inspect(old_attribute.name)}, to: #{inspect(new_attribute.name)}"
    end
  end

  defmodule RemoveAttribute do
    @moduledoc false
    defstruct [:attribute, :table, :multitenancy, :old_multitenancy]

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
    defstruct [:identity, :table, :multitenancy, :old_multitenancy, no_phase: true]

    def up(%{
          identity: %{name: name, keys: keys, base_filter: base_filter},
          table: table,
          multitenancy: multitenancy
        }) do
      name_prefix =
        if multitenancy.strategy == :context do
          "\#\{prefix\}_"
        else
          ""
        end

      if base_filter do
        keys =
          if multitenancy.strategy == :attribute do
            keys ++ [multitenancy.attribute]
          else
            keys
          end

        "create unique_index(:#{table}, [#{Enum.map_join(keys, ",", &inspect/1)}], name: \"#{
          name_prefix
        }#{table}_#{name}_unique_index\", where: \"#{base_filter}\")"
      else
        "create unique_index(:#{table}, [#{Enum.map_join(keys, ",", &inspect/1)}], name: \"#{
          name_prefix
        }#{table}_#{name}_unique_index\")"
      end
    end

    def down(%{identity: %{name: name, keys: keys}, table: table, old_multitenancy: multitenancy}) do
      if multitenancy.strategy == :context do
        "drop_if_exists unique_index(:#{table}, [#{Enum.map_join(keys, ",", &inspect/1)}], name: \"\#\{prefix\}_#{
          table
        }_#{name}_unique_index\")"
      else
        "drop_if_exists unique_index(:#{table}, [#{Enum.map_join(keys, ",", &inspect/1)}], name: \"#{
          table
        }_#{name}_unique_index\")"
      end
    end
  end

  defmodule RemoveUniqueIndex do
    @moduledoc false
    defstruct [:identity, :table, :multitenancy, :old_multitenancy, no_phase: true]

    def up(%{identity: %{name: name, keys: keys}, table: table, old_multitenancy: multitenancy}) do
      if multitenancy.strategy == :context do
        "drop_if_exists unique_index(:#{table}, [#{Enum.map_join(keys, ",", &inspect/1)}], name: \"\#\{prefix\}_#{
          table
        }_#{name}_unique_index\")"
      else
        "drop_if_exists unique_index(:#{table}, [#{Enum.map_join(keys, ",", &inspect/1)}], name: \"#{
          table
        }_#{name}_unique_index\")"
      end
    end

    def down(%{identity: %{name: name, keys: keys}, table: table, multitenancy: multitenancy}) do
      keys =
        if multitenancy.strategy == :attribute do
          keys ++ [multitenancy.attribute]
        else
          keys
        end

      if multitenancy.strategy == :context do
        "create unique_index(:#{table}, [#{Enum.map_join(keys, ",", &inspect/1)}], name: \"\#\{prefix\}_#{
          table
        }_#{name}_unique_index\")"
      else
        "create unique_index(:#{table}, [#{Enum.map_join(keys, ",", &inspect/1)}], name: \"#{
          table
        }_#{name}_unique_index\")"
      end
    end
  end
end
