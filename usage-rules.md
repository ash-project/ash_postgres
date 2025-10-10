<!--
SPDX-FileCopyrightText: 2020 Zach Daniel

SPDX-License-Identifier: MIT
-->

# Rules for working with AshPostgres

## Understanding AshPostgres

AshPostgres is the PostgreSQL data layer for Ash Framework. It's the most fully-featured Ash data layer and should be your default choice unless you have specific requirements for another data layer. Any PostgreSQL version higher than 13 is fully supported.

## Basic Configuration

To use AshPostgres, add the data layer to your resource:

```elixir
defmodule MyApp.Tweet do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  attributes do
    integer_primary_key :id
    attribute :text, :string
  end

  relationships do
    belongs_to :author, MyApp.User
  end

  postgres do
    table "tweets"
    repo MyApp.Repo
  end
end
```

## PostgreSQL Configuration

### Table & Schema Configuration

```elixir
postgres do
  # Required: Define the table name for this resource
  table "users"

  # Optional: Define the PostgreSQL schema
  schema "public"

  # Required: Define the Ecto repo to use
  repo MyApp.Repo

  # Optional: Control whether migrations are generated for this resource
  migrate? true
end
```

## Foreign Key References

Use the `references` section to configure foreign key behavior:

```elixir
postgres do
  table "comments"
  repo MyApp.Repo

  references do
    # Simple reference with defaults
    reference :post

    # Fully configured reference
    reference :user,
      on_delete: :delete,      # What happens when referenced row is deleted
      on_update: :update,      # What happens when referenced row is updated
      name: "comments_to_users_fkey", # Custom constraint name
      deferrable: true,        # Make constraint deferrable
      initially_deferred: false # Defer constraint check to end of transaction
  end
end
```

### Foreign Key Actions

For `on_delete` and `on_update` options:

- `:nothing` or `:restrict` - Prevent the change to the referenced row
- `:delete` - Delete the row when the referenced row is deleted (for `on_delete` only)
- `:update` - Update the row according to changes in the referenced row (for `on_update` only)
- `:nilify` - Set all foreign key columns to NULL
- `{:nilify, columns}` - Set specific columns to NULL (Postgres 15.0+ only)

> **Warning**: These operations happen directly at the database level. No resource logic, authorization rules, validations, or notifications are triggered.

## Check Constraints

Define database check constraints:

```elixir
postgres do
  check_constraints do
    check_constraint :positive_amount,
      check: "amount > 0",
      name: "positive_amount_check",
      message: "Amount must be positive"

    check_constraint :status_valid,
      check: "status IN ('pending', 'active', 'completed')"
  end
end
```

## Custom Indexes

Define custom indexes beyond those automatically created for identities and relationships:

```elixir
postgres do
  custom_indexes do
    index [:first_name, :last_name]

    index :email,
      unique: true,
      name: "users_email_index",
      where: "email IS NOT NULL",
      using: :gin

    index [:status, :created_at],
      concurrently: true,
      include: [:user_id]
  end
end
```

## Custom SQL Statements

Include custom SQL in migrations:

```elixir
postgres do
  custom_statements do
    statement "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\""

    statement """
    CREATE TRIGGER update_updated_at
    BEFORE UPDATE ON posts
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
    """

    statement "DROP INDEX IF EXISTS posts_title_index",
      on_destroy: true # Only run when resource is destroyed/dropped
  end
end
```

## Migrations and Codegen

### Development Migration Workflow (Recommended)

For development iterations, use the dev workflow to avoid naming migrations prematurely:

1. Make resource changes
2. Run `mix ash.codegen --dev` to generate and run dev migrations
3. Review the migrations and run `mix ash.migrate` to run them
4. Continue making changes and running `mix ash.codegen --dev` as needed
5. When your feature is complete, run `mix ash.codegen add_feature_name` to generate final named migrations (this will rollback dev migrations and squash them)
3. Review the migrations and run `mix ash.migrate` to run them

### Traditional Migration Generation

For single-step changes or when you know the final feature name:

1. Run `mix ash.codegen add_feature_name` to generate migrations
2. Review the generated migrations in `priv/repo/migrations`
3. Run `mix ash.migrate` to apply the migrations

> **Tip**: The dev workflow (`--dev` flag) is preferred during development as it allows you to iterate without thinking of migration names and provides better development ergonomics.

> **Warning**: Always review migrations before applying them to ensure they are correct and safe.

## Multitenancy

AshPostgres supports schema-based multitenancy:

```elixir
defmodule MyApp.Tenant do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  # Resource definition...

  postgres do
    table "tenants"
    repo MyApp.Repo

    # Automatically create/manage tenant schemas
    manage_tenant do
      template ["tenant_", :id]
    end
  end
end
```

### Setting Up Multitenancy

1. Configure your repo to support multitenancy:

```elixir
defmodule MyApp.Repo do
  use AshPostgres.Repo, otp_app: :my_app

  # Return all tenant schemas for migrations
  def all_tenants do
    import Ecto.Query, only: [from: 2]
    all(from(t in "tenants", select: fragment("? || ?", "tenant_", t.id)))
  end
end
```

2. Mark resources that should be multi-tenant:

```elixir
defmodule MyApp.Post do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  multitenancy do
    strategy :context
    attribute :tenant
  end

  # Resource definition...
end
```

3. When tenant migrations are generated, they'll be in `priv/repo/tenant_migrations`

4. Run tenant migrations in addition to regular migrations:

```bash
# Run regular migrations
mix ash.migrate

# Run tenant migrations
mix ash_postgres.migrate --tenants
```

## Advanced Features

### Manual Relationships

For complex relationships that can't be expressed with standard relationship types:

```elixir
defmodule MyApp.Post.Relationships.HighlyRatedComments do
  use Ash.Resource.ManualRelationship
  use AshPostgres.ManualRelationship

  def load(posts, _opts, context) do
    post_ids = Enum.map(posts, & &1.id)

    {:ok,
     MyApp.Comment
     |> Ash.Query.filter(post_id in ^post_ids)
     |> Ash.Query.filter(rating > 4)
     |> MyApp.read!()
     |> Enum.group_by(& &1.post_id)}
  end

  def ash_postgres_join(query, _opts, current_binding, as_binding, :inner, destination_query) do
    {:ok,
     Ecto.Query.from(_ in query,
       join: dest in ^destination_query,
       as: ^as_binding,
       on: dest.post_id == as(^current_binding).id,
       on: dest.rating > 4
     )}
  end

  # Other required callbacks...
end

# In your resource:
relationships do
  has_many :highly_rated_comments, MyApp.Comment do
    manual MyApp.Post.Relationships.HighlyRatedComments
  end
end
```

### Using Multiple Repos (Read Replicas)

Configure different repos for reads vs mutations:

```elixir
postgres do
  repo fn resource, type ->
    case type do
      :read -> MyApp.ReadReplicaRepo
      :mutate -> MyApp.WriteRepo
    end
  end
end
```

## Best Practices

1. **Organize migrations**: Run `mix ash.codegen` after each meaningful set of resource changes with a descriptive name:
   ```bash
   mix ash.codegen --name add_user_roles
   mix ash.codegen --name implement_post_tagging
   ```

2. **Use check constraints for domain invariants**: Enforce data integrity at the database level:
   ```elixir
   check_constraints do
     check_constraint :valid_status, check: "status IN ('pending', 'active', 'completed')"
     check_constraint :positive_balance, check: "balance >= 0"
   end
   ```

3. **Use custom statements for schema-only changes**: If you need to add database objects not directly tied to resources:
   ```elixir
   custom_statements do
     statement "CREATE EXTENSION IF NOT EXISTS \"pgcrypto\""
     statement "CREATE INDEX users_search_idx ON users USING gin(search_vector)"
   end
   ```

Remember that using AshPostgres provides a full-featured PostgreSQL data layer for your Ash application, giving you both the structure and declarative approach of Ash along with the power and flexibility of PostgreSQL.
