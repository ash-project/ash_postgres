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
