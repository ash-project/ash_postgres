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
      }, column: #{inspect(destination_field)}, with: [#{source_attribute}: :#{
        destination_attribute
      }]), default: #{attribute.default}, primary_key: #{attribute.primary_key?}"
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
                multitenancy: %{strategy: :context}
              }
            } = attribute
        }) do
      Mix.shell().info("""
      table `#{current_table}` with attribute multitenancy refers to table `#{table}` with schema based multitenancy.
      This means that it is not possible to use a foreign key. This is not necessarily a problem, just something
      you should be aware of
      """)

      "add #{inspect(attribute.name)}, #{inspect(attribute.type)}, default: #{attribute.default}, primary_key: #{
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

    def up(%{attribute: %{type: :integer, default: "nil", generated?: true} = attribute}) do
      "add #{inspect(attribute.name)}, :serial, null: #{attribute.allow_nil?}, primary_key: #{
        attribute.primary_key?
      }"
    end

    def up(%{attribute: attribute}) do
      "add #{inspect(attribute.name)}, #{inspect(attribute.type)}, null: #{attribute.allow_nil?}, default: #{
        attribute.default
      }, primary_key: #{attribute.primary_key?}"
    end

    def down(
          %{
            attribute: attribute,
            table: table,
            multitenancy: multitenancy
          } = op
        ) do
      AshPostgres.MigrationGenerator.Operation.RemoveAttribute.up(%{
        op
        | attribute: attribute,
          table: table,
          multitenancy: multitenancy
      })
    end
  end

  defmodule AlterAttribute do
    @moduledoc false
    defstruct [:old_attribute, :new_attribute, :table, :multitenancy, :old_multitenancy]

    defp alter_opts(attribute, old_attribute) do
      primary_key =
        if attribute.primary_key? and !old_attribute.primary_key? do
          ", primary_key: true"
        end

      default =
        if attribute.default != old_attribute.default do
          if is_nil(attribute.default) do
            ", default: nil"
          else
            ", default: #{attribute.default}"
          end
        end

      null =
        if attribute.allow_nil? != old_attribute.allow_nil? do
          ", null: #{attribute.allow_nil?}"
        end

      "#{null}#{default}#{primary_key}"
    end

    def up(%{
          multitenancy: multitenancy,
          old_attribute: old_attribute,
          new_attribute: attribute
        }) do
      type_or_reference =
        if AshPostgres.MigrationGenerator.has_reference?(multitenancy, attribute) and
             Map.get(old_attribute, :references) != Map.get(attribute, :references) do
          reference(multitenancy, attribute)
        else
          inspect(attribute.type)
        end

      "modify #{inspect(attribute.name)}, #{type_or_reference}#{
        alter_opts(attribute, old_attribute)
      }"
    end

    defp reference(%{strategy: :context}, %{
           type: type,
           name: name,
           references: %{
             multitenancy: %{strategy: :context},
             table: table,
             destination_field: destination_field
           }
         }) do
      "references(#{inspect(table)}, type: #{inspect(type)}, column: #{inspect(destination_field)}, name: \"\#\{prefix\}_#{
        table
      }_#{name}_fkey\")"
    end

    defp reference(%{strategy: :attribute, attribute: source_attribute}, %{
           type: type,
           references: %{
             multitenancy: %{strategy: :attribute, attribute: destination_attribute},
             table: table,
             destination_field: destination_field
           }
         }) do
      "references(#{inspect(table)}, type: #{inspect(type)}, column: #{inspect(destination_field)}, with: [#{
        source_attribute
      }: :#{destination_attribute}])"
    end

    defp reference(_, %{
           type: type,
           references: %{
             table: table,
             destination_field: destination_field
           }
         }) do
      "references(#{inspect(table)}, type: #{inspect(type)}, column: #{inspect(destination_field)})"
    end

    def down(op) do
      up(%{
        op
        | old_attribute: op.new_attribute,
          new_attribute: op.old_attribute,
          old_multitenancy: op.multitenancy,
          multitenancy: op.old_multitenancy
      })
    end
  end

  defmodule DropForeignKey do
    @moduledoc false
    # We only run this migration in one direction, based on the input
    # This is because the creation of a foreign key is handled by `references/3`
    # We only need to drop it before altering an attribute with `references/3`
    defstruct [:attribute, :table, :multitenancy, :direction, no_phase: true]

    def up(%{attribute: attribute, table: table, multitenancy: multitenancy, direction: :up}) do
      if multitenancy && multitenancy.strategy == :context do
        "drop constraint(:#{table}, \"\#\{prefix\}_#{table}_#{attribute.name}_fkey\")"
      else
        "drop constraint(:#{table}, \"#{table}_#{attribute.name}_fkey\")"
      end
    end

    def up(_), do: ""

    def down(%{attribute: attribute, table: table, multitenancy: multitenancy, direction: :down}) do
      if multitenancy && multitenancy.strategy == :context do
        "drop constraint(:#{table}, \"\#\{prefix\}_#{table}_#{attribute.name}_fkey\")"
      else
        "drop constraint(:#{table}, \"#{table}_#{attribute.name}_fkey\")"
      end
    end

    def down(_), do: ""
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
    defstruct [:attribute, :table, :multitenancy, :old_multitenancy, commented?: true]

    def up(%{attribute: attribute, commented?: true}) do
      """
      # Attribute removal has been commented out to avoid data loss. See the migration generator documentation for more
      # If you uncomment this, be sure to also uncomment the corresponding attribute *addition* in the `down` migration
      # remove #{inspect(attribute.name)}
      """
    end

    def up(%{attribute: attribute}) do
      "remove #{inspect(attribute.name)}"
    end

    def down(%{attribute: attribute, multitenancy: multitenancy, commented?: true}) do
      prefix = """
      # This is the `down` migration of the statement:
      #
      #     remove #{inspect(attribute.name)}
      #
      """

      contents =
        %AshPostgres.MigrationGenerator.Operation.AddAttribute{
          attribute: attribute,
          multitenancy: multitenancy
        }
        |> AshPostgres.MigrationGenerator.Operation.AddAttribute.up()
        |> String.split("\n")
        |> Enum.map(&"# #{&1}")
        |> Enum.join("\n")

      prefix <> "\n" <> contents
    end

    def down(%{attribute: attribute, multitenancy: multitenancy}) do
      AshPostgres.MigrationGenerator.Operation.AddAttribute.up(
        %AshPostgres.MigrationGenerator.Operation.AddAttribute{
          attribute: attribute,
          multitenancy: multitenancy
        }
      )
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
      {name_prefix, keys} =
        case multitenancy.strategy do
          :context ->
            {"\#\{prefix\}_", keys}

          :attribute ->
            {"", [multitenancy.attribute | keys]}

          _ ->
            {"", keys}
        end

      if base_filter do
        "create unique_index(:#{table}, [#{Enum.map_join(keys, ",", &inspect/1)}], name: \"#{
          name_prefix
        }#{table}_#{name}_unique_index\", where: \"#{base_filter}\")"
      else
        "create unique_index(:#{table}, [#{Enum.map_join(keys, ",", &inspect/1)}], name: \"#{
          name_prefix
        }#{table}_#{name}_unique_index\")"
      end
    end

    def down(%{
          identity: %{name: name, keys: keys},
          table: table,
          multitenancy: multitenancy
        }) do
      {name_prefix, keys} =
        case multitenancy.strategy do
          :context ->
            {"\#\{prefix\}_", keys}

          :attribute ->
            {"", [multitenancy.attribute | keys]}

          _ ->
            {"", keys}
        end

      "drop_if_exists unique_index(:#{table}, [#{Enum.map_join(keys, ",", &inspect/1)}], name: \"#{
        name_prefix
      }#{table}_#{name}_unique_index\")"
    end
  end

  defmodule RemoveUniqueIndex do
    @moduledoc false
    defstruct [:identity, :table, :multitenancy, :old_multitenancy, no_phase: true]

    def up(%{identity: %{name: name, keys: keys}, table: table, old_multitenancy: multitenancy}) do
      {name_prefix, keys} =
        case multitenancy.strategy do
          :context ->
            {"\#\{prefix\}_", keys}

          :attribute ->
            {"", [multitenancy.attribute | keys]}

          _ ->
            {"", keys}
        end

      "drop_if_exists unique_index(:#{table}, [#{Enum.map_join(keys, ",", &inspect/1)}], name: \"#{
        name_prefix
      }#{table}_#{name}_unique_index\")"
    end

    def down(%{
          identity: %{name: name, keys: keys, base_filter: base_filter},
          table: table,
          multitenancy: multitenancy
        }) do
      {name_prefix, keys} =
        case multitenancy.strategy do
          :context ->
            {"\#\{prefix\}_", keys}

          :attribute ->
            {"", [multitenancy.attribute | keys]}

          _ ->
            {"", keys}
        end

      if base_filter do
        "create unique_index(:#{table}, [#{Enum.map_join(keys, ",", &inspect/1)}], name: \"#{
          name_prefix
        }#{table}_#{name}_unique_index\", where: \"#{base_filter}\")"
      else
        "create unique_index(:#{table}, [#{Enum.map_join(keys, ",", &inspect/1)}], name: \"#{
          name_prefix
        }#{table}_#{name}_unique_index\")"
      end
    end
  end
end
