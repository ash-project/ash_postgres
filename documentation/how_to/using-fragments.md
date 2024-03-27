# Using Fragments

Fragments allow you to use arbitrary postgres expressions in your queries. Fragments can often be an escape hatch to allow you to do things that don't have something officially supported with Ash.

## Examples

Use simple expressions

```elixir
fragment("? / ?", points, count)
```

Call functions

```elixir
fragment("repeat('hello', 4)")
```

Use entire queries

```elixir
fragment("points > (SELECT SUM(points) FROM games WHERE user_id = ? AND id != ?)", user_id, id)
```

Using entire queries like the above is a last resort, but can often help us avoid having to add extra structure unnecessarily.

sql function in a calculate

```elixir
calculations do
  calculate :lower_name, :string, expr(
    fragment("LOWER(?)", name)
  )
end
```

sql function in a migration

```elixir
create table(:managers, primary_key: false) do
  add :id, :uuid, null: false, default: fragment("UUID_GENERATE_V4()"), primary_key: true
end
```
