<!--
SPDX-FileCopyrightText: 2020 Zach Daniel

SPDX-License-Identifier: MIT
-->

# Expressions

In addition to the expressions listed in the [Ash expressions guide](https://hexdocs.pm/ash/expressions.html), AshPostgres provides the following expressions

# Fragments

Fragments allow you to use arbitrary postgres expressions in your queries. Fragments can often be an escape hatch to allow you to do things that don't have something officially supported with Ash.

### Examples

#### Simple expressions

```elixir
fragment("? / ?", points, count)
```

#### Calling functions

```elixir
fragment("repeat('hello', 4)")
```

#### Using entire queries

```elixir
fragment("points > (SELECT SUM(points) FROM games WHERE user_id = ? AND id != ?)", user_id, id)
```

> ### a last resort {: .warning}
>
> Using entire queries as shown above is a last resort, but can sometimes be the best way to accomplish a given task.

#### In calculations

```elixir
calculations do
  calculate :lower_name, :string, expr(
    fragment("LOWER(?)", name)
  )
end
```

#### In migrations

```elixir
create table(:managers, primary_key: false) do
  add :id, :uuid, null: false, default: fragment("UUID_GENERATE_V4()"), primary_key: true
end
```

## Like and ILike

These wrap the postgres builtin like and ilike operators.

Please be aware, these match _patterns_ not raw text. Use `contains/1` if you want to match text without supporting patterns, i.e `%` and `_` have semantic meaning!

For example:

```elixir
Ash.Query.filter(User, like(name, "%obo%")) # name contains obo anywhere in the string, case sensitively
```

```elixir
Ash.Query.filter(User, ilike(name, "%ObO%")) # name contains ObO anywhere in the string, case insensitively
```

## Trigram similarity

To use this expression, you must have the `pg_trgm` extension in your repos `installed_extensions` list.

This calls the `similarity` function from that extension. See more in the [pgtrgm guide](https://www.postgresql.org/docs/current/pgtrgm.html)

For example:

```elixir
Ash.Query.filter(User, trigram_similarity(first_name, "fred") > 0.8)
```

## required!/1 and ash_required/1

`required!/1` (and the equivalent `ash_required/1`) express that a value must be present (not nil). They are equivalent to `not is_nil(expr)`. In SQL they compile to `(expr) IS NOT NULL` or, when using the ash-functions extension, to the stored function `ash_required(expr)`.

**Setup:** Add AshPostgres’s custom expressions to your Ash config so the expression parser knows about them (no changes to the main Ash repo needed):

```elixir
# config/config.exs (or config/dev.exs, config/runtime.exs)
config :ash, :custom_expressions, [
  AshPostgres.Expressions.Required,
  AshPostgres.Expressions.AshRequired
]
```

The **ash-functions extension** (installed via `mix ash_postgres.install_extensions` or migrations) includes an `ash_required(value)` SQL function that returns true when the value is not null. You can use it in raw SQL (e.g. fragments) as well.

Use them in filters, calculations, aggregates, and `exists/2` when you want clearer intent than `not is_nil(...)`.

### Examples

```elixir
# Filter: only records where an optional attribute is set
Ash.Query.filter(Post, required!(post_category))

# Same using the explicit name
Ash.Query.filter(Post, ash_required(post_category))

# In aggregate query filters
Post
|> Ash.Query.aggregate(:count, :comments, query: [filter: expr(required!(title))])

# In calculations (e.g. "has value" flag)
calculate :has_rating, :boolean, expr(required!(latest_rating_score))

# In exists
Ash.Query.filter(Comment, exists(post, required!(id)))
```

### Semantics and SQL

- **Semantics:** True when the argument is not nil; false when it is nil.
- **SQL:** Compiled to `(expression) IS NOT NULL` or to the extension function `ash_required(expression)` when the ash-functions extension is installed.
- **Edge cases:** Behaves like `not is_nil(expr)` over joins, nullable relationships, and in calculations. Use `required!(expr)` wherever you would use `not is_nil(expr)` for readability.
