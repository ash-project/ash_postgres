# Setting AshPostgres up with an existing database

If you already have a postgres database and you'd like to get
started quickly, you can scaffold resources directly from your
database.

First, create an application with AshPostgres if you haven't already:

```bash
mix igniter.new my_app
  --install ash,ash_postgres
  --with phx.new # add this if you will be using phoenix too
```

Then, go into your `config/dev.exs` and configure your repo to use
your existing database.

Finally, run:

```bash
mix ash_postgres.gen.resources MyApp.MyDomain --tables table1,table2,table3
```

## More fine grained control

You may want to do multiple passes to separate your application into multiple domains. For example:

```bash
mix ash_postgres.gen.resources MyApp.Accounts --tables users,roles,tokens
mix ash_postgres.gen.resources MyApp.Blog --tables posts,comments
```

See the docs for `mix ash_postgres.gen.resources` for more information.
