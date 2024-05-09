# References

To configure the behavior of generated foreign keys on a resource, we use the `references` section.

For example:

```elixir
references do
  reference :post, on_delete: :delete, on_update: :update, name: "comments_to_posts_fkey"
end
```

> ### Actions are not used for this behavior {: .warning}
>
> No resource logic is applied with these operations! No authorization rules or validations take place, and no notifications are issued. This operation happens _directly_ in the database.

## Nothing vs Restrict

```elixir
references do
  reference :post, on_delete: :nothing
  # vs
  reference :post, on_delete: :restrict
end
```

The difference between `:nothing` and `:restrict` is subtle and, if you are unsure, choose `:nothing` (the default behavior). `:restrict` will prevent the deletion from happening _before_ the end of the database transaction, whereas `:nothing` allows the transaction to complete before doing so. This allows for things like updating or deleting the destination row and _then_ updating updating or deleting the reference(as long as you are in a transaction). The reason that `:nothing` still ultimately prevents deletion is because postgres enforces foreign key referential integrity.

## On Delete

This option is called `on_delete`, instead of `on_destroy`, because it is hooking into the database level deletion, _not_ a `destroy` action in your resource. See the warning above.
