<!--
SPDX-FileCopyrightText: 2020 Zach Daniel

SPDX-License-Identifier: MIT
-->

# Foreign Key References

Use the `references` section to configure foreign key behavior:

```elixir
postgres do
  table "comments"
  repo MyApp.Repo

  references do
    # Simple reference with defaults
    reference :post

    # Fully configured reference
    reference :user,
      on_delete: :delete,      # What happens when referenced row is deleted
      on_update: :update,      # What happens when referenced row is updated
      name: "comments_to_users_fkey", # Custom constraint name
      deferrable: true,        # Make constraint deferrable
      initially_deferred: false # Defer constraint check to end of transaction
  end
end
```

## Foreign Key Actions

For `on_delete` and `on_update` options:

- `:nothing` or `:restrict` - Prevent the change to the referenced row
- `:delete` - Delete the row when the referenced row is deleted (for `on_delete` only)
- `:update` - Update the row according to changes in the referenced row (for `on_update` only)
- `:nilify` - Set all foreign key columns to NULL
- `{:nilify, columns}` - Set specific columns to NULL (Postgres 15.0+ only)

> **Warning**: These operations happen directly at the database level. No resource logic, authorization rules, validations, or notifications are triggered.