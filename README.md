# AshPostgres

![Elixir CI](https://github.com/ash-project/ash_postgres/workflows/Elixir%20CI/badge.svg)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Coverage Status](https://coveralls.io/repos/github/ash-project/ash_postgres/badge.svg?branch=master)](https://coveralls.io/github/ash-project/ash_postgres?branch=master)
[![Hex version badge](https://img.shields.io/hexpm/v/ash_postgres.svg)](https://hex.pm/packages/ash_postgres)

AshPostgres supports all capabilities of an Ash data layer, and it will
most likely stay that way, as postgres is the primary target/most maintained
data layer.

Custom Predicates:

- AshPostgres.Predicates.Trigram

## DSL

See the DSL documentation in `AshPostgres.DataLayer` for DSL documentation

## Usage

First, ensure you've added ash_postgres to your `mix.exs` file.

```elixir
{:ash_postgres, "~> x.y.z"}
```

To use this data layer, you need to define an `Ecto.Repo`. Within each Repo you
should add `use AshPostgres.Repo` after the `use Ecto.Repo` call because
AshPostgres adds some functionality on top of ecto repos.

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
