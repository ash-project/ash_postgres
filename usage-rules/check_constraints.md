<!--
SPDX-FileCopyrightText: 2020 Zach Daniel

SPDX-License-Identifier: MIT
-->

# Check Constraints

Define database check constraints:

```elixir
postgres do
  check_constraints do
    check_constraint :positive_amount,
      check: "amount > 0",
      name: "positive_amount_check",
      message: "Amount must be positive"

    check_constraint :status_valid,
      check: "status IN ('pending', 'active', 'completed')"
  end
end
```