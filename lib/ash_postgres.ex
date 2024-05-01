defmodule AshPostgres do
  @moduledoc """
  The AshPostgres extension gives you tools to map a resource to a postgres database table.

  For more, check out the [getting started guide](/documentation/tutorials/get-started-with-ash-postgres.md)
  """

  @deprecated "use AshPostgres.DataLayer.Info.repo/1"
  defdelegate repo(resource), to: AshPostgres.DataLayer.Info

  @deprecated "use AshPostgres.DataLayer.Info.table/1"
  defdelegate table(resource), to: AshPostgres.DataLayer.Info

  @deprecated "use AshPostgres.DataLayer.Info.schema/1"
  defdelegate schema(resource), to: AshPostgres.DataLayer.Info

  @deprecated "use AshPostgres.DataLayer.Info.references/1"
  defdelegate references(resource), to: AshPostgres.DataLayer.Info

  @deprecated "use AshPostgres.DataLayer.Info.migration_types/1"
  defdelegate migration_types(resource), to: AshPostgres.DataLayer.Info

  @deprecated "use AshPostgres.DataLayer.Info.check_constraints/1"
  defdelegate check_constraints(resource), to: AshPostgres.DataLayer.Info

  @deprecated "use AshPostgres.DataLayer.Info.custom_indexes/1"
  defdelegate custom_indexes(resource), to: AshPostgres.DataLayer.Info

  @deprecated "use AshPostgres.DataLayer.Info.custom_statements/1"
  defdelegate custom_statements(resource), to: AshPostgres.DataLayer.Info

  @deprecated "use AshPostgres.DataLayer.Info.polymorphic_on_delete/1"
  defdelegate polymorphic_on_delete(resource), to: AshPostgres.DataLayer.Info

  @deprecated "use AshPostgres.DataLayer.Info.polymorphic_on_update/1"
  defdelegate polymorphic_on_update(resource), to: AshPostgres.DataLayer.Info

  @deprecated "use AshPostgres.DataLayer.Info.polymorphic_name/1"
  defdelegate polymorphic_name(resource), to: AshPostgres.DataLayer.Info

  @deprecated "use AshPostgres.DataLayer.Info.polymorphic?/1"
  defdelegate polymorphic?(resource), to: AshPostgres.DataLayer.Info

  @deprecated "use AshPostgres.DataLayer.Info.unique_index_names/1"
  defdelegate unique_index_names(resource), to: AshPostgres.DataLayer.Info

  @deprecated "use AshPostgres.DataLayer.Info.exclusion_constraint_names/1"
  defdelegate exclusion_constraint_names(resource), to: AshPostgres.DataLayer.Info

  @deprecated "use AshPostgres.DataLayer.Info.identity_index_names/1"
  defdelegate identity_index_names(resource), to: AshPostgres.DataLayer.Info

  @deprecated "use AshPostgres.DataLayer.Info.foreign_key_names/1"
  defdelegate foreign_key_names(resource), to: AshPostgres.DataLayer.Info

  @deprecated "use AshPostgres.DataLayer.Info.migrate?/1"
  defdelegate migrate?(resource), to: AshPostgres.DataLayer.Info

  @deprecated "use AshPostgres.DataLayer.Info.base_filter_sql/1"
  defdelegate base_filter_sql(resource), to: AshPostgres.DataLayer.Info

  @deprecated "use AshPostgres.DataLayer.Info.skip_unique_indexes/1"
  defdelegate skip_unique_indexes(resource), to: AshPostgres.DataLayer.Info

  @deprecated "use AshPostgres.DataLayer.Info.manage_tenant_template/1"
  defdelegate manage_tenant_template(resource), to: AshPostgres.DataLayer.Info

  @deprecated "use AshPostgres.DataLayer.Info.manage_tenant_create?/1"
  defdelegate manage_tenant_create?(resource), to: AshPostgres.DataLayer.Info

  @deprecated "use AshPostgres.DataLayer.Info.manage_tenant_update?/1"
  defdelegate manage_tenant_update?(resource), to: AshPostgres.DataLayer.Info
end
