# AshPostgres

![Elixir CI](https://github.com/ash-project/ash_postgres/workflows/Elixir%20CI/badge.svg)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Coverage Status](https://coveralls.io/repos/github/ash-project/ash_postgres/badge.svg?branch=main)](https://coveralls.io/github/ash-project/ash_postgres?branch=main)
[![Hex version badge](https://img.shields.io/hexpm/v/ash_postgres.svg)](https://hex.pm/packages/ash_postgres)

AshPostgres supports all the capabilities of an Ash data layer. AshPostgres is the primary Ash data layer.

Custom Predicates:

- `AshPostgres.Predicates.Trigram`

## DSL

See the DSL documentation in `AshPostgres.DataLayer` for DSL documentation

## Usage

Add `ash_postgres` to your `mix.exs` file.

```elixir
{:ash_postgres, "~> 1.3.6"}
```

To use this data layer, you need to chage your Ecto Repo's from `use Ecto.Repo`,
to `use AshPostgres.Repo`. because AshPostgres adds functionality to Ecto Repos.

Then, configure each of your `Ash.Resource` resources by adding `use Ash.Resource, data_layer: AshPostgres.DataLayer` like so:

```elixir
defmodule MyApp.SomeResource do
  use Ash.Resource, data_layer: AshPostgres.DataLayer

  postgres do
    repo MyApp.Repo
    table "table_name"
  end

  attributes do
    # ... Attribute definitions
  end
end
```

## Generating Migrations

See the documentation for `Mix.Tasks.AshPostgres.GenerateMigrations` for how to generate
migrations from your resources

# Contributors

Ash is made possible by its excellent community!

<a href="https://github.com/ash-project/ash_postgres/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=ash-project/ash_postgres" />
</a>

[Become a contributor](https://ash-hq.org/docs/guides/ash/latest/how_to/contribute.md)
