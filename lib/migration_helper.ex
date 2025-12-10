# SPDX-FileCopyrightText: 2025 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.MigrationHelper do
  @moduledoc """
  Helper functions for AshPostgres migrations.

  This module provides utilities for migrations, particularly for handling
  concurrent index creation in various scenarios.
  """

  @doc """
  Determines whether a concurrent index should be used.

  Returns `false` (disables concurrent) in three scenarios:
  1. When running in test environment
  2. When inside a transaction
  3. When the table has no existing records (for tenant migrations)

  ## Examples

      # In a regular migration:
      create index(:posts, [:title], concurrently: maybe_index_concurrently?(:posts, repo()))

      # In a tenant migration:
      create index(:posts, [:title], concurrently: maybe_index_concurrently?(:posts, repo(), prefix()))

  """
  def maybe_index_concurrently?(table, repo, prefix \\ nil) do
    cond do
      Mix.env() == :test ->
        false

      repo.in_transaction?() ->
        false

      table_empty?(repo, table, prefix) ->
        false

      true ->
        true
    end
  end

  defp table_empty?(repo, table, prefix) do
    table_name = to_string(table)

    quoted_table =
      if prefix do
        Ecto.Adapters.SQL.quote_name({prefix, table_name})
      else
        Ecto.Adapters.SQL.quote_name(table_name)
      end

    [[exists]] =
      Ecto.Adapters.SQL.query!(repo, "SELECT EXISTS(SELECT 1 FROM #{quoted_table} LIMIT 1)", [])

    !exists
  end

  defp quote_name({schema, table}) do
    quote_name(schema) <> "." <> quote_name(table)
  end

  defp quote_name(name) do
    name = name |> to_string()
    ~s("#{String.replace(name, ~s("), ~s(""))}")
  end
end
