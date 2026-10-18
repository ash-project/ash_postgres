# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Yugabyte.Repo do
  @moduledoc false
  use AshPostgres.Repo, otp_app: :ash_postgres, warn_on_missing_ash_functions?: false

  @impl AshPostgres.Repo
  def include_upsert_action?, do: false

  @impl AshPostgres.Repo
  def min_pg_version, do: %Version{major: 15, minor: 0, patch: 0}

  @impl AshPostgres.Repo
  def installed_extensions, do: []
end
