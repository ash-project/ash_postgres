# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Cast targets for column references whose columns are migrated with second
# precision (e.g. `:utc_datetime` -> `timestamp(0)`). Casting such a column
# to its typmod-less name (`::timestamp`) is a typmod change that postgres'
# parser must keep as a coercion node, which blinds the planner to
# partial-index predicates and expression indexes on the bare column. These
# types render the typmod-accurate name, making the cast an identity cast
# that is deleted at parse time.
defmodule AshPostgres.Type.Timestamp0 do
  @moduledoc false
  use Ecto.Type

  @impl true
  def type, do: :"timestamp(0)"

  @impl true
  def cast(value), do: Ecto.Type.cast(:utc_datetime, value)

  @impl true
  def dump(value), do: Ecto.Type.dump(:utc_datetime, value)

  @impl true
  def load(value), do: Ecto.Type.load(:utc_datetime, value)
end

defmodule AshPostgres.Type.NaiveTimestamp0 do
  @moduledoc false
  use Ecto.Type

  @impl true
  def type, do: :"timestamp(0)"

  @impl true
  def cast(value), do: Ecto.Type.cast(:naive_datetime, value)

  @impl true
  def dump(value), do: Ecto.Type.dump(:naive_datetime, value)

  @impl true
  def load(value), do: Ecto.Type.load(:naive_datetime, value)
end

defmodule AshPostgres.Type.Time0 do
  @moduledoc false
  use Ecto.Type

  @impl true
  def type, do: :"time(0)"

  @impl true
  def cast(value), do: Ecto.Type.cast(:time, value)

  @impl true
  def dump(value), do: Ecto.Type.dump(:time, value)

  @impl true
  def load(value), do: Ecto.Type.load(:time, value)
end
