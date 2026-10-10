# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Persisters.KeyColumns do
  @moduledoc false
  # The columns PostgreSQL treats as keys when it picks an update's row lock: those in a
  # unique index with no expressions and no `WHERE`. This follows how AshPostgres generates
  # the primary key, identity and custom indexes, including the tenant column it adds to them
  # under attribute multitenancy. Unique indexes created some other way aren't known here.
  #
  # Persisted as `:postgres_key_columns`, for an update to pick the row lock it takes through a
  # subquery.
  use Spark.Dsl.Transformer

  def transform(dsl) do
    {:ok, Spark.Dsl.Transformer.persist(dsl, :postgres_key_columns, key_columns(dsl))}
  end

  defp key_columns(dsl) do
    tenant_columns =
      if Ash.Resource.Info.multitenancy_strategy(dsl) == :attribute do
        [
          dsl
          |> Ash.Resource.Info.multitenancy_attribute()
          |> then(&Ash.Resource.Info.attribute(dsl, &1))
          |> then(&to_string(&1.source))
        ]
      else
        []
      end

    partial_base_filter? = not is_nil(AshPostgres.DataLayer.Info.base_filter_sql(dsl))
    skipped_identities = AshPostgres.DataLayer.Info.skip_unique_indexes(dsl)

    primary_key_columns =
      dsl
      |> Ash.Resource.Info.primary_key()
      |> Enum.map(&to_string(Ash.Resource.Info.attribute(dsl, &1).source))

    identity_columns =
      dsl
      |> Ash.Resource.Info.identities()
      |> Enum.reject(
        &(&1.name in skipped_identities or not is_nil(&1.where) or partial_base_filter?)
      )
      |> Enum.flat_map(fn identity ->
        attributes = Enum.map(identity.keys, &Ash.Resource.Info.attribute(dsl, &1))

        # A key that's a calculation makes it an expression index.
        if Enum.any?(attributes, &is_nil/1) do
          []
        else
          if(identity.all_tenants?, do: [], else: tenant_columns) ++
            Enum.map(attributes, &to_string(&1.source))
        end
      end)

    custom_index_columns =
      dsl
      |> AshPostgres.DataLayer.Info.custom_indexes()
      |> Enum.filter(& &1.unique)
      |> Enum.reject(
        &(not is_nil(&1.where) or (&1.include_base_filter? and partial_base_filter?))
      )
      |> Enum.flat_map(fn index ->
        # Custom index fields name columns. A string that isn't a plain column name is an
        # expression.
        columns = Enum.map(index.fields, &to_string(AshPostgres.CustomIndex.column_name(&1)))

        if Enum.all?(columns, &Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, &1)) do
          if(index.all_tenants?, do: [], else: tenant_columns) ++ columns
        else
          []
        end
      end)

    Enum.uniq(primary_key_columns ++ identity_columns ++ custom_index_columns)
  end
end
