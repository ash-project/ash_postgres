# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.MultitenancyTest.DepartmentTenant do
  @moduledoc false
  defstruct [:id, :organization_id]

  defimpl Ash.ToTenant do
    def to_tenant(department, _resource), do: department.id
  end

  defimpl Ash.ToAncestorTenants do
    def to_ancestor_tenants(department, _resource), do: [department.organization_id]
  end
end
