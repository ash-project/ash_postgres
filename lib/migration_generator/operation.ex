defmodule AshPostgres.MigrationGenerator.Operation do
  @moduledoc false

  defmodule Helper do
    @moduledoc false
    def join(list),
      do:
        list
        |> List.flatten()
        |> Enum.reject(&is_nil/1)
        |> Enum.join(", ")
        |> String.replace(", )", ")")

    def maybe_add_default("nil"), do: nil
    def maybe_add_default(value), do: "default: #{value}"

    def maybe_add_primary_key(true), do: "primary_key: true"
    def maybe_add_primary_key(_), do: nil

    def maybe_add_null(false), do: "null: false"
    def maybe_add_null(_), do: nil

    def on_delete(%{on_delete: on_delete}) when on_delete in [:delete, :nilify] do
      "on_delete: :#{on_delete}_all"
    end

    def on_delete(%{on_delete: on_delete}) when is_atom(on_delete) and not is_nil(on_delete) do
      "on_delete: :#{on_delete}"
    end

    def on_delete(_), do: nil

    def on_update(%{on_update: on_update}) when on_update in [:update, :nilify] do
      "on_update: :#{on_update}_all"
    end

    def on_update(%{on_update: on_update}) when is_atom(on_update) and not is_nil(on_update) do
      "on_update: :#{on_update}"
    end

    def on_update(_), do: nil
  end

  defmodule CreateTable do
    @moduledoc false
    defstruct [:table, :multitenancy, :old_multitenancy]
  end

  defmodule AddAttribute do
    @moduledoc false
    defstruct [:attribute, :table, :multitenancy, :old_multitenancy]

    import Helper

    def up(%{
          multitenancy: %{strategy: :attribute, attribute: source_attribute},
          attribute:
            %{
              references:
                %{
                  table: table,
                  destination_field: destination_field,
                  multitenancy: %{strategy: :attribute, attribute: destination_attribute}
                } = reference
            } = attribute
        }) do
      [
        "add #{inspect(attribute.name)}",
        "references(:#{table}",
        [
          "column: #{inspect(destination_field)}",
          "with: [#{source_attribute}: :#{destination_attribute}]",
          "name: #{inspect(reference.name)}",
          on_delete(reference),
          on_update(reference)
        ],
        ")",
        maybe_add_default(attribute.default),
        maybe_add_primary_key(attribute.primary_key?)
      ]
      |> join()
    end

    def up(%{
          multitenancy: %{strategy: :context},
          attribute:
            %{
              references:
                %{
                  table: table,
                  destination_field: destination_field,
                  multitenancy: %{strategy: :attribute}
                } = reference
            } = attribute
        }) do
      [
        "add #{inspect(attribute.name)}",
        "references(:#{table}",
        [
          "column: #{inspect(destination_field)}",
          "prefix: \"public\"",
          "name: #{inspect(reference.name)}",
          on_delete(reference),
          on_update(reference)
        ],
        ")",
        maybe_add_default(attribute.default),
        maybe_add_primary_key(attribute.primary_key?)
      ]
      |> join()
    end

    def up(%{
          multitenancy: %{strategy: :attribute},
          attribute:
            %{
              references: %{
                multitenancy: %{strategy: :context}
              }
            } = attribute
        }) do
      [
        "add #{inspect(attribute.name)}",
        inspect(attribute.type),
        maybe_add_default(attribute.default),
        maybe_add_primary_key(attribute.primary_key?)
      ]
      |> join()
    end

    def up(%{
          multitenancy: %{strategy: :context},
          attribute:
            %{references: %{table: table, destination_field: destination_field} = reference} =
              attribute
        }) do
      [
        "add #{inspect(attribute.name)}",
        "references(:#{table}",
        [
          "column: #{inspect(destination_field)}",
          "name: #{inspect(reference.name)}",
          on_delete(reference),
          on_update(reference)
        ],
        ")",
        maybe_add_default(attribute.default),
        maybe_add_primary_key(attribute.primary_key?)
      ]
      |> join()
    end

    def up(%{
          attribute:
            %{references: %{table: table, destination_field: destination_field} = reference} =
              attribute
        }) do
      [
        "add #{inspect(attribute.name)}",
        "references(:#{table}",
        [
          "column: #{inspect(destination_field)}",
          "name: #{inspect(reference.name)}",
          on_delete(reference),
          on_update(reference)
        ],
        ")",
        maybe_add_default(attribute.default),
        maybe_add_primary_key(attribute.primary_key?)
      ]
      |> join()
    end

    def up(%{attribute: %{type: :bigint, default: "nil", generated?: true} = attribute}) do
      [
        "add #{inspect(attribute.name)}",
        ":bigserial",
        maybe_add_null(attribute.allow_nil?),
        maybe_add_primary_key(attribute.primary_key?)
      ]
      |> join()
    end

    def up(%{attribute: %{type: :integer, default: "nil", generated?: true} = attribute}) do
      [
        "add #{inspect(attribute.name)}",
        ":serial",
        maybe_add_null(attribute.allow_nil?),
        maybe_add_primary_key(attribute.primary_key?)
      ]
      |> join()
    end

    def up(%{attribute: attribute}) do
      [
        "add #{inspect(attribute.name)}",
        "#{inspect(attribute.type)}",
        maybe_add_null(attribute.allow_nil?),
        maybe_add_default(attribute.default),
        maybe_add_primary_key(attribute.primary_key?)
      ]
      |> join()
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

    import Helper

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
           references:
             %{
               multitenancy: %{strategy: :context},
               table: table,
               destination_field: destination_field
             } = reference
         }) do
      join([
        "references(:#{table}, column: #{inspect(destination_field)}",
        "name: #{inspect(reference.name)}",
        on_delete(reference),
        on_update(reference),
        ")"
      ])
    end

    defp reference(%{strategy: :attribute, attribute: source_attribute}, %{
           references:
             %{
               multitenancy: %{strategy: :attribute, attribute: destination_attribute},
               table: table,
               destination_field: destination_field
             } = reference
         }) do
      join([
        "references(:#{table}, column: #{inspect(destination_field)}, with: [#{source_attribute}: :#{
          destination_attribute
        }]",
        "name: #{inspect(reference.name)}",
        on_delete(reference),
        on_update(reference),
        ")"
      ])
    end

    defp reference(
           %{strategy: :context},
           %{
             references:
               %{
                 table: table,
                 destination_field: destination_field
               } = reference
           }
         ) do
      join([
        "references(:#{table}, column: #{inspect(destination_field)}, prefix: \"public\"",
        "name: #{inspect(reference.name)}",
        on_delete(reference),
        on_update(reference),
        ")"
      ])
    end

    defp reference(
           _,
           %{
             references:
               %{
                 table: table,
                 destination_field: destination_field
               } = reference
           }
         ) do
      join([
        "references(:#{table}, column: #{inspect(destination_field)}",
        "name: #{inspect(reference.name)}",
        on_delete(reference),
        on_update(reference),
        ")"
      ])
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

    def up(%{table: table, attribute: %{references: reference}, direction: :up}) do
      "drop constraint(:#{table}, #{inspect(reference.name)})"
    end

    def up(_) do
      ""
    end

    def down(%{table: table, attribute: %{references: reference}, direction: :down}) do
      "drop constraint(:#{table}, #{inspect(reference.name)})"
    end

    def down(_) do
      ""
    end
  end

  defmodule RenameAttribute do
    @moduledoc false
    defstruct [
      :old_attribute,
      :new_attribute,
      :table,
      :multitenancy,
      :old_multitenancy,
      no_phase: true
    ]

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
            {"\#\{prefix()\}_", keys}

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
            {"\#\{prefix()\}_", keys}

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
            {"\#\{prefix()\}_", keys}

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
            {"\#\{prefix()\}_", keys}

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

  defmodule AddCheckConstraint do
    @moduledoc false
    defstruct [:table, :constraint, :multitenancy, :old_multitenancy, no_phase: true]

    def up(%{
          constraint: %{
            name: name,
            check: check,
            base_filter: base_filter
          },
          table: table
        }) do
      if base_filter do
        "create constraint(:#{table}, :#{name}, check: \"#{base_filter} AND #{check}\")"
      else
        "create constraint(:#{table}, :#{name}, check: \"#{check}\")"
      end
    end

    def down(%{
          constraint: %{name: name},
          table: table
        }) do
      "drop_if_exists constraint(:#{table}, :#{name})"
    end
  end

  defmodule RemoveCheckConstraint do
    @moduledoc false
    defstruct [:table, :constraint, :multitenancy, :old_multitenancy, no_phase: true]

    def up(%{constraint: %{name: name}, table: table}) do
      "drop_if_exists constraint(:#{table}, :#{name})"
    end

    def down(%{
          constraint: %{
            name: name,
            check: check,
            base_filter: base_filter
          },
          table: table
        }) do
      if base_filter do
        "create constraint(:#{table}, :#{name}, check: \"#{base_filter} AND #{check}\")"
      else
        "create constraint(:#{table}, :#{name}, check: \"#{check}\")"
      end
    end
  end
end
