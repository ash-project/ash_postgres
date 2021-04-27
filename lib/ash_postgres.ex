defmodule AshPostgres do
  @moduledoc """
  A postgres extension library for `Ash`.

  `AshPostgres.DataLayer` provides a DataLayer, and a DSL extension to configure that data layer.

  The dsl extension exposes the `postgres` section. See: `AshPostgres.DataLayer` for more.
  """

  alias Ash.Dsl.Extension

  @doc "The configured repo for a resource"
  def repo(resource) do
    Extension.get_opt(resource, [:postgres], :repo, nil, true)
  end

  @doc "The configured table for a resource"
  def table(resource) do
    Extension.get_opt(resource, [:postgres], :table, nil, true)
  end

  @doc "The configured references for a resource"
  def references(resource) do
    Extension.get_entities(resource, [:postgres, :references])
  end

  @doc "The configured check_constraints for a resource"
  def check_constraints(resource) do
    Extension.get_entities(resource, [:postgres, :check_constraints])
  end

  @doc "The configured polymorphic_reference_on_delete for a resource"
  def polymorphic_on_delete(resource) do
    Extension.get_opt(resource, [:postgres, :references], :polymorphic_on_delete, nil, true)
  end

  @doc "The configured polymorphic_reference_on_update for a resource"
  def polymorphic_on_update(resource) do
    Extension.get_opt(resource, [:postgres, :references], :polymorphic_on_update, nil, true)
  end

  @doc "The configured polymorphic_reference_name for a resource"
  def polymorphic_name(resource) do
    Extension.get_opt(resource, [:postgres, :references], :polymorphic_on_delete, nil, true)
  end

  @doc "The configured polymorphic? for a resource"
  def polymorphic?(resource) do
    Extension.get_opt(resource, [:postgres], :polymorphic?, nil, true)
  end

  @doc "The configured unique_index_names"
  def unique_index_names(resource) do
    Extension.get_opt(resource, [:postgres], :unique_index_names, [], true)
  end

  @doc "The configured identity_index_names"
  def identity_index_names(resource) do
    Extension.get_opt(resource, [:postgres], :identity_index_names, [], true)
  end

  @doc "The configured foreign_key_names"
  def foreign_key_names(resource) do
    Extension.get_opt(resource, [:postgres], :foreign_key_names, [], true)
  end

  @doc "Whether or not the resource should be included when generating migrations"
  def migrate?(resource) do
    Extension.get_opt(resource, [:postgres], :migrate?, nil, true)
  end

  @doc "A stringified version of the base_filter, to be used in a where clause when generating unique indexes"
  def base_filter_sql(resource) do
    Extension.get_opt(resource, [:postgres], :base_filter_sql, nil)
  end

  @doc "Skip generating unique indexes when generating migrations"
  def skip_unique_indexes?(resource) do
    Extension.get_opt(resource, [:postgres], :skip_unique_indexes?, [])
  end

  @doc "The template for a managed tenant"
  def manage_tenant_template(resource) do
    Extension.get_opt(resource, [:postgres, :manage_tenant], :template, nil)
  end

  @doc "Whether or not to create a tenant for a given resource"
  def manage_tenant_create?(resource) do
    Extension.get_opt(resource, [:postgres, :manage_tenant], :create?, false)
  end

  @doc "Whether or not to update a tenant for a given resource"
  def manage_tenant_update?(resource) do
    Extension.get_opt(resource, [:postgres, :manage_tenant], :update?, false)
  end
end
