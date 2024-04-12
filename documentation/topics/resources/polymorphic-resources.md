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
