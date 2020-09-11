defmodule AshPostgres do
  @moduledoc """
  A postgres extension library for `Ash`.

  `AshPostgres.DataLayer` provides a DataLayer, and a DSL extension to configure that data layer.

  The dsl extension exposes the `postgres` section. See: `AshPostgres.DataLayer.postgres/1` for more.
  """

  alias Ash.Dsl.Extension

  @doc "Fetch the configured repo for a resource"
  def repo(resource) do
    Extension.get_opt(resource, [:postgres], :repo, nil, true)
  end

  @doc "Fetch the configured table for a resource"
  def table(resource) do
    Extension.get_opt(resource, [:postgres], :table, nil, true)
  end

  @doc "Whether or not the resource should be included when generating migrations"
  def migrate?(resource) do
    Extension.get_opt(resource, [:postgres], :migrate?, nil, true)
  end
end
