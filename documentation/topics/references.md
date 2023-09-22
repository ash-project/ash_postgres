# References

To configure the foreign keys on a resource, we use the `references` block.

For example:

```elixir
references do
  reference :post, on_delete: :delete, on_update: :update, name: "comments_to_posts_fkey"
end
```

## Important

No resource logic is applied with these operations! No authorization rules or validations take place, and no notifications are issued. This operation happens *directly* in the database. That

## Nothing vs Restrict

The difference between `:nothing` and `:restrict` is subtle and, if you are unsure, choose `:nothing` (the default behavior). `:restrict` will prevent the deletion from happening *before* the end of the database transaction, whereas `:nothing` allows the transaction to complete before doing so. This allows for things like updating or deleting the destination row and *then* updating updating or deleting the reference(as long as you are in a transaction).

## On Delete

This option is called `on_delete`, instead of `on_destroy`, because it is hooking into the database level deletion, *not* a `destroy` action in your resource.
