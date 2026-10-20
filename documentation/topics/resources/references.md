<!--
SPDX-FileCopyrightText: 2020 Zach Daniel

SPDX-License-Identifier: MIT
-->

# References

To configure the behavior of generated foreign keys on a resource, we use the `references` section, within the `postgres` configuration block.

For example:

```elixir
postgres do
  # other PostgreSQL config here

  references do
    reference :post, on_delete: :delete, on_update: :update, name: "comments_to_posts_fkey"
  end
end
```

All supported DSL options can be found in a [datalayer documentation](https://hexdocs.pm/ash_postgres/dsl-ashpostgres-datalayer.html#postgres-references).

> ### Actions are not used for this behavior {: .warning}
>
> No resource logic is applied with these operations! No authorization rules or validations take place, and no notifications are issued. This operation happens _directly_ in the database.

## On Delete

This option describes what to do if the referenced row is deleted.

The option is called `on_delete`, instead of `on_destroy`, because it is hooking into the database level deletion, _not_ a `destroy` action in your resource. See the warning above.

The possible values for the option are `:nothing`, `:restrict`, `:delete`, `:nilify`, `{:nilify, columns}`.

With `:nothing` or `:restrict` the deletion of the referenced row is prevented.

With `:delete` the row is deleted together with the referenced row.

With `:nilify` all columns of the foreign-key constraint are nilified.

With `{:nilify, columns}` a column list can specify which columns should be set to `nil`.
If you intend to use this option to nilify a subset of the columns, note that it cannot be used together with the `match: :full` option otherwise a mix of nil and non-nil values would fail the constraint and prevent the deletion of the referenced row.
In addition, keep into consideration that this option is only supported from Postgres v15.0 onwards.

## On Update

This option describes what to do if the referenced row is updated.

The possible values for the option are `:nothing`, `:restrict`, `:update`, `:nilify`.

With `:nothing` or `:restrict` the update of the referenced row is prevented.

With `:update` the row is updated according to the referenced row.

With `:nilify` all columns of the foreign-key constraint are nilified.

## Nothing vs Restrict

```elixir
references do
  reference :post, on_delete: :nothing
  # vs
  reference :post, on_delete: :restrict
end
```

The difference between `:nothing` and `:restrict` is subtle and, if you are unsure, choose `:nothing` (the default behavior). `:restrict` will immediately check the foreign-key constraint and prevent the update or deletion from happening, whereas `:nothing` allows the check to be deferred until later in the transaction. This allows for things like updating or deleting the destination row and _then_ updating updating or deleting the reference (as long as you are in a transaction). The reason that `:nothing` still ultimately prevents the update or deletion is because postgres enforces foreign key referential integrity.

## Matching Tenants

With attribute multitenancy, a foreign key to another multitenant resource's primary key only references that key, so a row can point at a record that belongs to a different tenant. Set `match_tenant?: true` to add the tenant attribute to the foreign key, so that the referenced row must belong to the same tenant:

```elixir
references do
  reference :project, match_tenant?: true
end
```

This generates a composite foreign key, for example `(project_id, organization_id)` referencing `projects (id, organization_id)`. Postgres requires the referenced columns to be covered by a unique index, so the destination table needs one on its tenant attribute and primary key. Identities and custom indexes on multitenant resources include the tenant attribute automatically, so a unique custom index on the primary key generates it.

When the relationship allows `nil`, the foreign key uses `match: :simple`, because `match: :full` would reject any row where the reference is `nil` while the tenant attribute is set. Set `match_type` explicitly to override this.

Since the tenant attribute is part of the foreign key, `on_delete: :nilify` would set it to `nil` as well and fail on a `NOT NULL` tenant column. Use `{:nilify, columns}` to nilify only the reference:

```elixir
references do
  reference :project, match_tenant?: true, on_delete: {:nilify, [:project_id]}
end
```
