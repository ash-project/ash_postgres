<!--
SPDX-FileCopyrightText: 2020 Zach Daniel

SPDX-License-Identifier: MIT
-->

# Polymorphic Resources

To support leveraging the same resource backed by multiple tables (useful for things like polymorphic associations), AshPostgres supports setting the `data_layer.table` context for a given resource. For this example, lets assume that you have a `MyApp.Post` resource and a `MyApp.Comment` resource. For each of those resources, users can submit `reactions`. However, you want a separate table for `post_reactions` and `comment_reactions`. You could accomplish that like so:

```elixir
defmodule MyApp.Reaction do
  use Ash.Resource,
    domain: MyDomain,
    data_layer: AshPostgres.DataLayer

  postgres do
    polymorphic? true # Without this, `table` is a required configuration
  end

  attributes do
    attribute :resource_id, :uuid, public?: true
  end

  ...
end
```

Then, in your related resources, you set the table context like so:

```elixir
defmodule MyApp.Post do
  use Ash.Resource,
    domain: MyDomain,
    data_layer: AshPostgres.DataLayer

  ...

  relationships do
    has_many :reactions, MyApp.Reaction,
      relationship_context: %{data_layer: %{table: "post_reactions"}},
      destination_attribute: :resource_id
  end
end

defmodule MyApp.Comment do
  use Ash.Resource,
    domain: MyDomain,
    data_layer: AshPostgres.DataLayer

  ...

  relationships do
    has_many :reactions, MyApp.Reaction,
      relationship_context: %{data_layer: %{table: "comment_reactions"}},
      destination_attribute: :resource_id
  end
end
```

With this, when loading or editing related data, ash will automatically set that context.
For managing related data, see `Ash.Changeset.manage_relationship/4` and other relationship functions
in `Ash.Changeset`

## Table specific actions

To make actions use a specific table, you can use the `set_context` query preparation/change.

For example:

```elixir
defmodule MyApp.Reaction do
  # ...
  actions do
    read :for_comments do
      prepare set_context(%{data_layer: %{table: "comment_reactions"}})
    end

    read :for_posts do
      prepare set_context(%{data_layer: %{table: "post_reactions"}})
    end
  end
end
```

## Migrations

When a migration is marked as `polymorphic? true`, the migration generator will look at
all resources that are related to it, that set the `%{data_layer: %{table: "table"}}` context.
For each of those, a migration is generated/managed automatically. This means that adding reactions
to a new resource is as easy as adding the relationship and table context, and then running
`mix ash.codegen`.

## Polymorphic references

For each `has_many` or `has_one` relationship from a source resource to a polymorphic resource that supplies a table context, AshPostgres generates a foreign key that points to the source resource’s table. This foreign key is created in the `table` specified by the relationship’s `data_layer` context.

To configure the foreign key, add a `references` map alongside `table` in the relationship’s `data_layer` context:

```elixir
relationships do
  has_many :event_locations, MyApp.EventLocation,
    relationship_context: %{
      data_layer: %{
        table: "event_locations",
        references: %{
          on_delete: :delete,
          on_update: :update,
          name: "event_locations_event_id_fkey"
        }
      }
    },
    destination_attribute: :event_id
end
```

### Options

The following options go inside `relationship_context.data_layer.references`:

| Name | Type | Default | Docs |
|------|------|---------|------|
| `on_delete` | `:delete \| :nilify \| :nothing \| :restrict \| {:nilify, atom \| list(atom)}` | `:nothing` | Configures what happens when a source-table row is deleted. |
| `on_update` | `:update \| :nilify \| :nothing \| :restrict` | `:nothing` | Configures what happens when the referenced column in the source table is updated. |
| `name` | `String.t` | generated | Sets the name of the generated foreign-key constraint. |

The legacy `polymorphic_on_delete`, `polymorphic_on_update`, and `polymorphic_name` options are deprecated but remain supported for backwards compatibility. New configurations should use `relationship_context.data_layer.references`. See the [DSL reference](../../dsls/DSL-AshPostgres.DataLayer.md#postgres-references) for the legacy options.

Remove the corresponding legacy option when moving a setting into the relationship context. Configuring both forms for the same setting raises an error, even when their values match.
