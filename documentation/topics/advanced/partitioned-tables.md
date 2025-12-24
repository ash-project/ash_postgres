<!--
SPDX-FileCopyrightText: 2025 ash_postgres contributors

SPDX-License-Identifier: MIT
-->

# Partitioned Tables

PostgreSQL supports table partitioning, which allows you to split a large table into smaller, more manageable pieces. Partitioning can improve query performance, simplify maintenance, and enable better data management strategies.

For more information on PostgreSQL partitioning, see the [PostgreSQL partitioning documentation](https://www.postgresql.org/docs/current/ddl-partitioning.html).

> ### Multitenancy and Partitioning {: .info}
>
> If you're interested in using partitions for multitenancy, start with AshPostgres's [Schema Based Multitenancy](schema-based-multitenancy.html) feature, which uses PostgreSQL schemas to separate tenant data. Schema-based multitenancy is generally the recommended approach for multitenancy in AshPostgres.

## Setting Up a Partitioned Table

To create a partitioned table in AshPostgres, you'll use the `create_table_options` DSL option to specify the partitioning strategy. This option passes configuration directly to Ecto's `create table/2` function.

### Range Partitioning Example

Here's an example of setting up a range-partitioned table by date:

```elixir
defmodule MyApp.SensorReading do
  use Ash.Resource,
    domain: MyApp.Domain,
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id
    attribute :sensor_id, :integer
    attribute :reading_value, :float
    create_timestamp :inserted_at
  end

  postgres do
    table "sensor_readings"
    repo MyApp.Repo

    # Configure the table as a partitioned table
    create_table_options "PARTITION BY RANGE (inserted_at)"

    # Create a default partition to catch any data that doesn't fit into specific partitions
    custom_statements do
      statement :default_partition do
        up """
        CREATE TABLE IF NOT EXISTS sensor_readings_default
        PARTITION OF sensor_readings DEFAULT;
        """
        down """
        DROP TABLE IF EXISTS sensor_readings_default;
        """
      end
    end
  end
end
```

### List Partitioning Example

Here's an example of list partitioning by region:

```elixir
defmodule MyApp.Order do
  use Ash.Resource,
    domain: MyApp.Domain,
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id
    attribute :order_number, :string
    attribute :region, :string
    attribute :total, :decimal
    create_timestamp :inserted_at
  end

  postgres do
    table "orders"
    repo MyApp.Repo

    # Configure the table as a list-partitioned table
    create_table_options "PARTITION BY LIST (region)"

    # Create a default partition
    custom_statements do
      statement :default_partition do
        up """
        CREATE TABLE IF NOT EXISTS orders_default
        PARTITION OF orders DEFAULT;
        """
        down """
        DROP TABLE IF EXISTS orders_default;
        """
      end
    end
  end
end
```

### Hash Partitioning Example

Here's an example of hash partitioning:

```elixir
defmodule MyApp.LogEntry do
  use Ash.Resource,
    domain: MyApp.Domain,
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id
    attribute :user_id, :integer
    attribute :message, :string
    create_timestamp :inserted_at
  end

  postgres do
    table "log_entries"
    repo MyApp.Repo

    # Configure the table as a hash-partitioned table
    create_table_options "PARTITION BY HASH (user_id)"

    # Create a default partition
    custom_statements do
      statement :default_partition do
        up """
        CREATE TABLE IF NOT EXISTS log_entries_default
        PARTITION OF log_entries DEFAULT;
        """
        down """
        DROP TABLE IF EXISTS log_entries_default;
        """
      end
    end
  end
end
```

## Creating Additional Partitions

After the initial migration, you can create additional partitions as needed using custom statements. For example, to create monthly partitions for a range-partitioned table:

```elixir
postgres do
  table "sensor_readings"
  repo MyApp.Repo

  create_table_options "PARTITION BY RANGE (inserted_at)"

  custom_statements do
    statement :default_partition do
      up """
      CREATE TABLE IF NOT EXISTS sensor_readings_default
      PARTITION OF sensor_readings DEFAULT;
      """
      down """
      DROP TABLE IF EXISTS sensor_readings_default;
      """
    end

    # Example: Create a partition for January 2024
    statement :january_2024_partition do
      up """
      CREATE TABLE IF NOT EXISTS sensor_readings_2024_01
      PARTITION OF sensor_readings
      FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
      """
      down """
      DROP TABLE IF EXISTS sensor_readings_2024_01;
      """
    end

    # Example: Create a partition for February 2024
    statement :february_2024_partition do
      up """
      CREATE TABLE IF NOT EXISTS sensor_readings_2024_02
      PARTITION OF sensor_readings
      FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');
      """
      down """
      DROP TABLE IF EXISTS sensor_readings_2024_02;
      """
    end
  end
end
```

## Dynamically Creating Partitions

For list-partitioned tables, you may want to create partitions dynamically as part of a action. Here's an example helper function for creating partitions:

```elixir
def create_partition(resource, partition_name, list_value) do
  repo = AshPostgres.DataLayer.Info.repo(resource)
  table_name = AshPostgres.DataLayer.Info.table(resource)
  schema = AshPostgres.DataLayer.Info.schema(resource) || "public"

  sql = """
  CREATE TABLE IF NOT EXISTS "#{schema}"."#{partition_name}"
  PARTITION OF "#{schema}"."#{table_name}"
  FOR VALUES IN ('#{list_value}')
  """

  case Ecto.Adapters.SQL.query(repo, sql, []) do
    {:ok, _} ->
      :ok

    {:error, %{postgres: %{code: :duplicate_table}}} ->
      :ok

    {:error, error} ->
      {:error, "Failed to create partition for #{table_name}: #{inspect(error)}"}
  end
end
```

Similarly, you'll want to dynamically drop partitions when they're no longer needed.



> ### Partitioning is Complex {: .warning}
>
> Table partitioning is a complex topic with many considerations around performance, maintenance, foreign keys, and data management. This guide shows how to configure partitioned tables in AshPostgres, but it is not a comprehensive primer on PostgreSQL partitioning. For detailed information on partitioning strategies, best practices, and limitations, please refer to the [PostgreSQL partitioning documentation](https://www.postgresql.org/docs/current/ddl-partitioning.html).

## See Also

- [Ecto.Migration.table/2 documentation](https://hexdocs.pm/ecto_sql/Ecto.Migration.html#table/2) for more information on table options
- [PostgreSQL Partitioning documentation](https://www.postgresql.org/docs/current/ddl-partitioning.html) for detailed information on partitioning strategies
- [Custom Statements documentation](https://hexdocs.pm/ash_postgres/dsl-ashpostgres-datalayer.html#postgres-custom_statements) for more information on using custom statements in migrations
