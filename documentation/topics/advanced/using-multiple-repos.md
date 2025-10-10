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
    Enum.random(@replicas)
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
