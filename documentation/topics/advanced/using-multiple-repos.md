<!--
SPDX-FileCopyrightText: 2020 Zach Daniel

SPDX-License-Identifier: MIT
-->

# Using Multiple Repos

When scaling PostgreSQL you may want to setup _read_ replicas to improve
performance and availability. This can be achieved by configuring multiple
repositories in your application.

## Setup Read Replicas

Following the [ecto docs](https://hexdocs.pm/ecto/replicas-and-dynamic-repositories.html), change your Repo configuration:

```elixir
defmodule MyApp.Repo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Ecto.Adapters.Postgres

  @replicas [
    MyApp.Repo.Replica1,
    MyApp.Repo.Replica2,
    MyApp.Repo.Replica3,
    MyApp.Repo.Replica4
  ]

  def replica do
    case Process.get(:replica) do
      nil ->
        replica = Enum.random(@replicas)
        Process.put(:replica, replica)
        replica

      replica ->
        replica
    end
  end

  for repo <- @replicas do
    defmodule repo do
      use Ecto.Repo,
        otp_app: :my_app,
        adapter: Ecto.Adapters.Postgres,
        read_only: true
    end
  end
end
```

## Configure AshPostgres

Now change the `repo` argument for your `postgres` block as such:

```elixir
defmodule MyApp.MyDomain.MyResource do
  use Ash.Resource,
    date_layer: AshPostgres.DataLayer

  postgres do
    table "my_resources"
    repo fn
      _resource, :read -> MyApp.Repo.replica()
      _resource, :mutate -> MyApp.Repo
    end
  end
end
```

## The repo function must answer the same way for a whole query

The function is called every time a repo is needed, and separate calls are compared
against each other. `AshPostgres.DataLayer.can?(resource, {:join, other_resource})` requires
the two resources to share a data layer *and* `repo(resource, :read)` to equal
`repo(other_resource, :read)`, while `can?(resource, {:lateral_join, resources})` compares
every resource in the list against `repo(resource, :read)`. Nothing memoizes those lookups,
so a function that picks at random per call answers differently within a single query, and
any expression that reaches through a relationship fails:

```
** (Ash.Error.Query.InvalidExpression) cannot access multiple resources for a data layer
   that can't be joined from within a single expression
```

Lateral joins are chosen from the same comparison, and there the source resource is itself
part of the list being checked — so even loading a plain relationship asks about one resource
twice and compares the two answers. When they disagree, related records are loaded with a
different query plan, and there is no error to show for it.

This is why the example above remembers its choice in the process dictionary rather than
calling `Enum.random/1` each time. Two further points for a real application:

- A process that has just written should read from the primary until replication catches up.
  The `:read` branch of the `repo` function is where that belongs — return `MyApp.Repo`
  rather than a replica for a short while after a mutation.
- A long-lived process (a `Phoenix.LiveView`, a channel, a `GenServer`) keeps the repo it
  first chose. Clear it between units of work — at the start of a LiveView callback, or per
  request — so it can go back to a replica:

  ```elixir
  Process.delete(:replica)
  ```

  Never clear it while a query is being built.
