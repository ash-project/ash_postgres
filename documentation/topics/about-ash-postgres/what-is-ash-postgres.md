# What is AshPostgres?

AshPostgres is the PostgreSQL `Ash.DataLayer` for [Ash Framework](https://hexdocs.pm/ash). This is the most fully-featured Ash data layer, and unless you need a specific characteristic or feature of another data layer, you should use `AshPostgres`.

Use this to persist records in a PostgreSQL table or view. For example, the resource below would be persisted in a table called `tweets`:

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

The table might look like this:

| id  | text            | author_id |
| --- | --------------- | --------- |
| 1   | "Hello, world!" | 1         |

Creating records would add to the table, destroying records would remove from the table, and updating records would update the table.
