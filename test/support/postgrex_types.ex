# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# The test repos configure this exactly as the `AshPostgres.Repo` docs tell users to,
# so `interval_decode_type: Duration` is exercised rather than only described.
Postgrex.Types.define(
  AshPostgres.Test.PostgrexTypes,
  Ecto.Adapters.Postgres.extensions(),
  interval_decode_type: Duration
)
