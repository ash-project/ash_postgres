# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.TestRepo do
  @moduledoc false
  use AshPostgres.Repo,
    otp_app: :ash_postgres

  def on_transaction_begin(data) do
    send(self(), data)
  end

  def prefer_transaction?, do: false

  def prefer_transaction_for_atomic_updates?, do: false

  def installed_extensions do
    [
      "ash-functions",
      "uuid-ossp",
      "pg_trgm",
      "citext",
      "btree_gist",
      AshPostgres.TestCustomExtension,
      AshPostgres.Extensions.ImmutableRaiseError,
      "ltree"
    ] --
      Application.get_env(:ash_postgres, :no_extensions, [])
  end

  # Default to the Ash `uuid_generate_v7()` function rather than PG18+'s native
  # `uuidv7()`, so bumping min_pg_version to 19 doesn't churn every snapshot.
  # Overridable per-test (e.g. the native-uuidv7 generator test opts in).
  def use_builtin_uuidv7_function?,
    do: Application.get_env(:ash_postgres, :test_use_builtin_uuidv7?, false)

  def min_pg_version do
    case System.get_env("PG_VERSION") do
      nil ->
        %Version{major: 19, minor: 0, patch: 0}

      version ->
        case Integer.parse(version) do
          {major, ""} -> %Version{major: major, minor: 0, patch: 0}
          _ -> Version.parse!(version)
        end
    end
  end

  def all_tenants do
    Code.ensure_compiled(AshPostgres.MultitenancyTest.Org)

    AshPostgres.MultitenancyTest.Org
    |> Ash.read!()
    |> Enum.map(&"org_#{&1.id}")
  end

  def immutable_expr_error? do
    Application.get_env(:ash_postgres, :test_repo_use_immutable_errors?, false)
  end
end
