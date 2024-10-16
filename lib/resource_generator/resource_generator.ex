defmodule AshPostgres.ResourceGenerator do
  @moduledoc false
  alias AshPostgres.ResourceGenerator.Spec

  require Logger

  def generate(igniter, repos, domain, opts \\ []) do
    {igniter, resources} = Ash.Resource.Igniter.list_resources(igniter)

    # This is a hack. We should be looking at compiled resources
    # unlikely to ever matter given how this task will be used though.
    resources = Enum.filter(resources, &Code.ensure_loaded?/1)

    igniter = Igniter.include_all_elixir_files(igniter)

    opts = handle_csv_opts(opts, [:tables, :skip_tables, :extend])

    specs =
      repos
      |> Enum.flat_map(&Spec.tables(&1, skip_tables: opts[:skip_tables], tables: opts[:tables]))
      |> Enum.map(fn %{table_name: table} = spec ->
        resource =
          table
          |> Inflex.singularize()
          |> Macro.camelize()
          |> then(&Module.concat([domain, &1]))

        %{spec | resource: resource}
      end)
      |> Enum.group_by(& &1.resource)
      |> Enum.map(fn
        {_resource, [single]} ->
          single

        {resource, specs} ->
          raise """
          Duplicate resource names detected across multiple repos: #{inspect(resource)}

          #{inspect(Enum.map(specs, & &1.repo))}

          To address this, run this command separately for each repo and specify the
          `--domain` option to put the resources into a separate domain, or omit the table
          with `--tables` or `--skip-tables`
          """
      end)
      |> Spec.add_relationships(resources, opts)

    Enum.reduce(specs, igniter, fn table_spec, igniter ->
      table_to_resource(igniter, table_spec, domain, opts)
    end)
  end

  defp handle_csv_opts(opts, keys) do
    Enum.reduce(keys, opts, fn key, opts ->
      opts
      |> Keyword.get_values(key)
      |> case do
        [] ->
          opts

        values ->
          values
          |> Enum.join(",")
          |> String.split(",", trim: true)
          |> then(&Keyword.put(opts, key, &1))
      end
    end)
  end

  defp table_to_resource(
         igniter,
         %AshPostgres.ResourceGenerator.Spec{} = table_spec,
         domain,
         opts
       ) do
    no_migrate_flag =
      if opts[:no_migrations] do
        "migrate? false"
      end

    resource =
      """
      use Ash.Resource,
        domain: #{inspect(domain)},
        data_layer: AshPostgres.DataLayer

      postgres do
        table #{inspect(table_spec.table_name)}
        repo #{inspect(table_spec.repo)}
        #{no_migrate_flag}
        #{references(table_spec, opts[:no_migrations])}
        #{custom_indexes(table_spec, opts[:no_migrations])}
        #{check_constraints(table_spec, opts[:no_migrations])}
        #{skip_unique_indexes(table_spec)}
        #{identity_index_names(table_spec)}
      end

      attributes do
        #{attributes(table_spec)}
      end
      """
      |> add_identities(table_spec)
      |> add_relationships(table_spec)

    igniter
    |> Ash.Domain.Igniter.add_resource_reference(domain, table_spec.resource)
    |> Igniter.Project.Module.create_module(table_spec.resource, resource)
    |> then(fn igniter ->
      if opts[:extend] && opts[:extend] != [] do
        Igniter.compose_task(igniter, "ash.patch.extend", [
          table_spec.resource | opts[:extend] || []
        ])
      else
        igniter
      end
    end)
  end

  defp check_constraints(%{check_constraints: _check_constraints}, true) do
    ""
  end

  defp check_constraints(%{check_constraints: []}, _) do
    ""
  end

  defp check_constraints(%{check_constraints: check_constraints}, _) do
    check_constraints =
      Enum.map_join(check_constraints, "\n", fn check_constraint ->
        """
        check_constraint :#{check_constraint.column}, "#{check_constraint.name}", check: "#{check_constraint.expression}", message: "is invalid"
        """
      end)

    """
    check_constraints do
      #{check_constraints}
    end
    """
  end

  defp skip_unique_indexes(%{indexes: indexes}) do
    indexes
    |> Enum.filter(fn %{unique?: unique?, columns: columns} ->
      unique? && Enum.all?(columns, &Regex.match?(~r/^[0-9a-zA-Z_]+$/, &1))
    end)
    |> Enum.reject(&index_as_identity?/1)
    |> case do
      [] ->
        ""

      indexes ->
        """
          skip_unique_indexes [#{Enum.map_join(indexes, ",", &":#{&1.identity_name}")}]
        """
    end
  end

  defp identity_index_names(%{indexes: indexes}) do
    indexes
    |> Enum.filter(fn %{unique?: unique?, columns: columns} ->
      unique? && Enum.all?(columns, &Regex.match?(~r/^[0-9a-zA-Z_]+$/, &1))
    end)
    |> case do
      [] ->
        []

      indexes ->
        indexes
        |> Enum.map_join(", ", fn index ->
          "#{index.identity_name}: \"#{index.name}\""
        end)
        |> then(&"identity_index_names [#{&1}]")
    end
  end

  defp add_identities(str, %{indexes: indexes}) do
    indexes
    |> Enum.filter(fn %{unique?: unique?, columns: columns} ->
      unique? && Enum.all?(columns, &Regex.match?(~r/^[0-9a-zA-Z_]+$/, &1))
    end)
    |> Enum.map(fn index ->
      name = index.identity_name

      fields = "[" <> Enum.map_join(index.columns, ", ", &":#{&1}") <> "]"

      case identity_options(index) do
        "" ->
          "identity :#{name}, #{fields}"

        options ->
          """
          identity :#{name}, #{fields} do
            #{options}
          end
          """
      end
    end)
    |> case do
      [] ->
        str

      identities ->
        """
        #{str}

        identities do
          #{Enum.join(identities, "\n")}
        end
        """
    end
  end

  defp identity_options(index) do
    ""
    |> add_identity_where(index)
    |> add_nils_distinct?(index)
  end

  defp add_identity_where(str, %{where_clause: nil}), do: str

  defp add_identity_where(str, %{name: name, where_clause: where_clause}) do
    Logger.warning("""
    Index #{name} has been left commented out in its resource
    Manual conversion of `#{where_clause}` to an Ash expression is required.
    """)

    """
    #{str}
    # Express `#{where_clause}` as an Ash expression
    # where expr(...)
    """
  end

  defp add_nils_distinct?(str, %{nils_distinct?: false}) do
    "#{str}\n nils_distinct? false"
  end

  defp add_nils_distinct?(str, _), do: str

  defp add_relationships(str, %{relationships: []}) do
    str
  end

  defp add_relationships(str, %{relationships: relationships} = spec) do
    relationships
    |> Enum.map_join("\n", fn relationship ->
      case relationship_options(spec, relationship) do
        "" ->
          "#{relationship.type} :#{relationship.name}, #{inspect(relationship.destination)}"

        options ->
          """
          #{relationship.type} :#{relationship.name}, #{inspect(relationship.destination)} do
             #{options}
          end
          """
      end
    end)
    |> then(fn rels ->
      """
      #{str}

      relationships do
        #{rels}
      end
      """
    end)
  end

  defp relationship_options(spec, %{type: :belongs_to} = rel) do
    case Enum.find(spec.attributes, fn attribute ->
           attribute.name == rel.source_attribute
         end) do
      %{
        default: default,
        generated?: generated?,
        source: source,
        name: name
      }
      when not is_nil(default) or generated? or source != name ->
        "define_attribute? false"
        |> add_destination_attribute(rel, "id")
        |> add_source_attribute(rel, "#{rel.name}_id")
        |> add_allow_nil(rel)
        |> add_filter(rel)

      attribute ->
        ""
        |> add_destination_attribute(rel, "id")
        |> add_source_attribute(rel, "#{rel.name}_id")
        |> add_allow_nil(rel)
        |> add_primary_key(attribute.primary_key?)
        |> add_attribute_type(attribute)
        |> add_filter(rel)
    end
  end

  defp relationship_options(_spec, rel) do
    default_destination_attribute =
      rel.source
      |> Module.split()
      |> List.last()
      |> Macro.underscore()
      |> Kernel.<>("_id")

    ""
    |> add_destination_attribute(rel, default_destination_attribute)
    |> add_source_attribute(rel, "id")
    |> add_filter(rel)
  end

  defp add_filter(str, %{match_with: []}), do: str

  defp add_filter(str, %{match_with: match_with}) do
    filter =
      Enum.map_join(match_with, " and ", fn {source, dest} ->
        "parent(#{source}) == #{dest}"
      end)

    "#{str}\n filter expr(#{filter})"
  end

  defp add_attribute_type(str, %{attr_type: :uuid}), do: str

  defp add_attribute_type(str, %{attr_type: attr_type}) do
    "#{str}\n attribute_type :#{attr_type}"
  end

  defp add_destination_attribute(str, rel, default) do
    if rel.destination_attribute == default do
      str
    else
      "#{str}\n destination_attribute :#{rel.destination_attribute}"
    end
  end

  defp add_source_attribute(str, rel, default) do
    if rel.source_attribute == default do
      str
    else
      "#{str}\n source_attribute :#{rel.source_attribute}"
    end
  end

  defp references(_table_spec, true) do
    ""
  end

  defp references(table_spec, _) do
    table_spec.foreign_keys
    |> Enum.flat_map(fn %Spec.ForeignKey{} = foreign_key ->
      default_name = "#{table_spec.table_name}_#{foreign_key.column}_fkey"

      if default_name == foreign_key.constraint_name and
           foreign_key.on_update == "NO ACTION" and
           foreign_key.on_delete == "NO ACTION" and
           foreign_key.match_type in ["SIMPLE", "NONE"] do
        []
      else
        relationship =
          Enum.find(table_spec.relationships, fn relationship ->
            relationship.type == :belongs_to and
              relationship.constraint_name == foreign_key.constraint_name
          end).name

        options =
          ""
          |> add_on(:update, foreign_key.on_update)
          |> add_on(:delete, foreign_key.on_delete)
          |> add_match_with(foreign_key.match_with)
          |> add_match_type(foreign_key.match_type)

        [
          """
          reference :#{relationship} do
            #{options}
          end
          """
        ]
      end
      |> Enum.join("\n")
      |> String.trim()
      |> then(
        &[
          """
          references do
            #{&1}
          end
          """
        ]
      )
    end)
  end

  defp add_match_with(str, empty) when empty in [[], nil], do: str

  defp add_match_with(str, keyval),
    do: str <> "\nmatch_with [#{Enum.map_join(keyval, fn {key, val} -> "#{key}: :#{val}" end)}]"

  defp add_match_type(str, type) when type in ["SIMPLE", "NONE"], do: str

  defp add_match_type(str, "FULL"), do: str <> "\nmatch_type :full"
  defp add_match_type(str, "PARTIAL"), do: str <> "\nmatch_type :partial"

  defp add_on(str, type, "RESTRICT"), do: str <> "\non_#{type} :restrict"
  defp add_on(str, type, "CASCADE"), do: str <> "\non_#{type} :#{type}"
  defp add_on(str, type, "SET NULL"), do: str <> "\non_#{type} :nilify"
  defp add_on(str, _type, _), do: str

  defp custom_indexes(table_spec, true) do
    table_spec.indexes
    |> Enum.reject(fn index ->
      !index.unique? || (&index_as_identity?/1) ||
        Enum.any?(index.columns, &String.contains?(&1, "("))
    end)
    |> case do
      [] ->
        ""

      indexes ->
        indexes
        |> Enum.map_join(", ", fn %{index: name, columns: columns} ->
          columns = Enum.map_join(columns, ", ", &":#{&1}")
          "{[#{columns}], #{inspect(name)}}"
        end)
        |> then(fn index_names ->
          "unique_index_names [#{index_names}]"
        end)
    end
  end

  defp custom_indexes(table_spec, _) do
    table_spec.indexes
    |> Enum.reject(&index_as_identity?/1)
    |> case do
      [] ->
        ""

      indexes ->
        indexes
        |> Enum.map_join("\n", fn index ->
          columns =
            index.columns
            |> Enum.map_join(", ", fn thing ->
              if String.contains?(thing, "(") do
                inspect(thing)
              else
                ":#{thing}"
              end
            end)

          case index_options(table_spec, index) do
            "" ->
              "index [#{columns}]"

            options ->
              """
              index [#{columns}] do
                #{options}
              end
              """
          end
        end)
        |> then(fn indexes ->
          """
          custom_indexes do
            #{indexes}
          end
          """
        end)
    end
  end

  defp index_as_identity?(index) do
    is_nil(index.where_clause) and index.using == "btree" and index.include in [nil, []] and
      Enum.all?(index.columns, &Regex.match?(~r/^[0-9a-zA-Z_]+$/, &1))
  end

  defp index_options(spec, index) do
    default_name =
      if Enum.all?(index.columns, &Regex.match?(~r/^[0-9a-zA-Z_]+$/, &1)) do
        AshPostgres.CustomIndex.name(spec.table_name, %{fields: index.columns})
      end

    ""
    |> add_index_name(index.name, default_name)
    |> add_unique(index.unique?)
    |> add_using(index.using)
    |> add_where(index.where_clause)
    |> add_include(index.include)
    |> add_nulls_distinct(index.nulls_distinct)
  end

  defp add_index_name(str, default, default), do: str
  defp add_index_name(str, name, _), do: str <> "\nname #{inspect(name)}"

  defp add_unique(str, false), do: str
  defp add_unique(str, true), do: str <> "\nunique true"

  defp add_nulls_distinct(str, true), do: str
  defp add_nulls_distinct(str, false), do: str <> "\nnulls_distinct false"

  defp add_using(str, "btree"), do: str
  defp add_using(str, using), do: str <> "\nusing #{inspect(using)}"

  defp add_where(str, empty) when empty in [nil, ""], do: str
  defp add_where(str, where), do: str <> "\nwhere #{inspect(where)}"

  defp add_include(str, empty) when empty in [nil, []], do: str

  defp add_include(str, include),
    do: str <> "\ninclude [#{Enum.map_join(include, ", ", &inspect/1)}]"

  defp attributes(table_spec) do
    table_spec.attributes
    |> Enum.split_with(& &1.default)
    |> then(fn {l, r} -> r ++ l end)
    |> Enum.split_with(& &1.primary_key?)
    |> then(fn {l, r} -> l ++ r end)
    |> Enum.filter(fn attribute ->
      if not is_nil(attribute.default) or !!attribute.generated? or
           attribute.source != attribute.name do
        true
      else
        not Enum.any?(table_spec.relationships, fn relationship ->
          relationship.type == :belongs_to and relationship.source_attribute == attribute.name
        end)
      end
    end)
    |> Enum.map_join("\n", &attribute(&1))
  end

  defp attribute(attribute) do
    now_default = &DateTime.utc_now/0
    uuid_default = &Ash.UUID.generate/0

    {constructor, attribute, type?, type_option?} =
      case attribute do
        %{name: "updated_at", attr_type: attr_type} ->
          {"update_timestamp", %{attribute | default: nil, generated?: false}, false,
           attr_type != :utc_datetime_usec}

        %{default: default, attr_type: attr_type}
        when default == now_default ->
          {"create_timestamp", %{attribute | default: nil, generated?: false}, false,
           attr_type != :utc_datetime_usec}

        %{default: default, attr_type: attr_type, primary_key?: true}
        when default == uuid_default ->
          {"uuid_primary_key",
           %{attribute | default: nil, primary_key?: false, generated?: false, allow_nil?: true},
           false, attr_type != :uuid}

        _ ->
          {"attribute", attribute, true, false}
      end

    case String.trim(options(attribute, type_option?)) do
      "" ->
        if type? do
          "#{constructor} :#{attribute.name}, #{inspect(attribute.attr_type)}"
        else
          "#{constructor} :#{attribute.name}"
        end

      options ->
        if type? do
          """
          #{constructor} :#{attribute.name}, #{inspect(attribute.attr_type)} do
            #{options}
          end
          """
        else
          """
          #{constructor} :#{attribute.name} do
            #{options}
          end
          """
        end
    end
  end

  defp options(attribute, type_option?) do
    ""
    |> add_primary_key(attribute)
    |> add_allow_nil(attribute)
    |> add_sensitive(attribute)
    |> add_default(attribute)
    |> add_type(attribute, type_option?)
    |> add_generated(attribute)
    |> add_source(attribute)
  end

  defp add_type(str, %{attr_type: attr_type}, true) do
    str <> "\n    type #{inspect(attr_type)}"
  end

  defp add_type(str, _, _), do: str

  defp add_generated(str, %{generated?: true}) do
    str <> "\n    generated? true"
  end

  defp add_generated(str, _), do: str

  defp add_source(str, %{name: name, source: source}) when name != source do
    str <> "\n    source :#{source}"
  end

  defp add_source(str, _), do: str

  defp add_primary_key(str, %{primary_key?: true}) do
    str <> "\n    primary_key? true"
  end

  defp add_primary_key(str, _), do: str

  defp add_allow_nil(str, %{allow_nil?: false}) do
    str <> "\n    allow_nil? false"
  end

  defp add_allow_nil(str, _), do: str

  defp add_sensitive(str, %{sensitive?: true}) do
    str <> "\n    sensitive? true"
  end

  defp add_sensitive(str, _), do: str

  defp add_default(str, %{default: default}) when not is_nil(default) do
    str <> "\n    default #{inspect(default)}"
  end

  defp add_default(str, _), do: str
end
