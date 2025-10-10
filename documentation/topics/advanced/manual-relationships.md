<!--
SPDX-FileCopyrightText: 2020 Zach Daniel

SPDX-License-Identifier: MIT
-->

# Manual Relationships

See [Manual Relationships](https://hexdocs.pm/ash/relationships.html#manual-relationships) for an idea of manual relationships in general.
Manual relationships allow for expressing complex/non-typical relationships between resources in a standard way.
Individual data layers may interact with manual relationships in their own way, so see their corresponding guides.

## Example

```elixir
# in the resource

relationships do
  has_many :tickets_above_threshold, Helpdesk.Support.Ticket do
    manual Helpdesk.Support.Ticket.Relationships.TicketsAboveThreshold
  end
end

# implementation
defmodule Helpdesk.Support.Ticket.Relationships.TicketsAboveThreshold do
  use Ash.Resource.ManualRelationship
  use AshPostgres.ManualRelationship

  require Ash.Query
  require Ecto.Query

  def load(records, _opts, %{query: query, actor: actor, authorize?: authorize?}) do
    # Use existing records to limit resultds
    rep_ids = Enum.map(records, & &1.id)
     # Using Ash to get the destination records is ideal, so you can authorize access like normal
     # but if you need to use a raw ecto query here, you can. As long as you return the right structure.

    {:ok,
     query
     |> Ash.Query.filter(representative_id in ^rep_ids)
     |> Ash.Query.filter(priority > representative.priority_threshold)
     |> Helpdesk.Support.read!(actor: actor, authorize?: authorize?)
     # Return the items grouped by the primary key of the source, i.e representative.id => [...tickets above threshold]
     |> Enum.group_by(& &1.representative_id)}
  end

  # query is the "source" query that is being built.

  # _opts are options provided to the manual relationship, i.e `{Manual, opt: :val}`

  # current_binding is what the source of the relationship is bound to. Access fields with `as(^current_binding).field`

  # as_binding is the binding that your join should create. When you join, make sure you say `as: ^as_binding` on the
  # part of the query that represents the destination of the relationship

  # type is `:inner` or `:left`.
  # destination_query is what you should join to to add the destination to the query, i.e `join: dest in ^destination-query`
  def ash_postgres_join(query, _opts, current_binding, as_binding, :inner, destination_query) do
    {:ok,
     Ecto.Query.from(_ in query,
       join: dest in ^destination_query,
       as: ^as_binding,
       on: dest.representative_id == as(^current_binding).id,
       on: dest.priority > as(^current_binding).priority_threshold
     )}
  end

  def ash_postgres_join(query, _opts, current_binding, as_binding, :left, destination_query) do
    {:ok,
     Ecto.Query.from(_ in query,
       left_join: dest in ^destination_query,
       as: ^as_binding,
       on: dest.representative_id == as(^current_binding).id,
       on: dest.priority > as(^current_binding).priority_threshold
     )}
  end

  # _opts are options provided to the manual relationship, i.e `{Manual, opt: :val}`

  # current_binding is what the source of the relationship is bound to. Access fields with `parent_as(^current_binding).field`

  # as_binding is the binding that has already been created for your join. Access fields on it via `as(^as_binding)`

  # destination_query is what you should use as the basis of your query
  def ash_postgres_subquery(_opts, current_binding, as_binding, destination_query) do
    {:ok,
     Ecto.Query.from(_ in destination_query,
       where: parent_as(^current_binding).id == as(^as_binding).representative_id,
       where: as(^as_binding).priority > parent_as(^current_binding).priority_threshold
     )}
  end
end
```

## Recursive Relationships

Manual relationships can be _very_ powerful, as they can leverage the full power of Ecto to do arbitrarily complex things.
Here is an example of a recursive relationship that loads all employees under the purview of a given manager using a recursive CTE.

> ### Use ltree {: .info}
>
> While the below is very powerful, if at all possible we suggest using ltree for hierarchical data. Its built in to postgres
> and AshPostgres has built in support for it. For more, see: `AshPostgres.Ltree`.

Keep in mind this is an example of a very advanced use case, _not_ something you'd typically need to do.

```elixir
defmodule MyApp.Employee.ManagedEmployees do
  @moduledoc """
  A manual relationship which uses a recursive CTE to find all employees managed by a given employee.
  """

  use Ash.Resource.ManualRelationship
  use AshPostgres.ManualRelationship
  alias MyApp.Employee
  alias MyApp.Repo
  import Ecto.Query

  @doc false
  @impl true
  @spec load([Employee.t()], keyword, map) ::
          {:ok, %{Ash.UUID.t() => [Employee.t()]}} | {:error, any}
  def load(employees, _opts, context) do
    relationship_name = context.relationship.name

    employee_ids = Enum.map(employees, & &1.id)

    all_descendants =
      Employee
      |> where([l], l.manager_id in ^employee_ids)
      |> recursive_cte_query("employee_tree", Employee)
      |> Repo.all()
      |> Enum.group_by(& &1.manager_id, & &1)

    employees
    |> with_descendants(all_descendants, relationship_name)
    |> Map.new(&{&1.id, Map.get(&1, relationship_name)})
    |> then(&{:ok, &1})
  end

  defp with_descendants([], _, _), do: []

  defp with_descendants(employees, all_descendants, relationship_name) do
    Enum.map(employees, fn employee ->
      descendants = Map.get(all_descendants, employee.id, [])

      Map.put(employee, relationship_name, with_descendants(descendants, all_descendants, relationship_name))
    end)
  end

  @doc false
  @impl true
  @spec ash_postgres_join(
          Ecto.Query.t(),
          opts :: keyword,
          current_binding :: any,
          as_binding :: any,
          :inner | :left,
          Ecto.Query.t()
        ) ::
          {:ok, Ecto.Query.t()} | {:error, any}
  # Add a join from some binding in the query, producing *as_binding*.
  def ash_postgres_join(query, _opts, current_binding, as_binding, join_type, destination_query) do
    immediate_parents =
      from(destination in destination_query,
        where: parent_as(^current_binding).manager_id == destination.id
      )

    cte_name = "employees_#{as_binding}"

    descendant_query =
      recursive_cte_query_for_join(
        immediate_parents,
        cte_name,
        destination_query
      )

    case join_type do
      :inner ->
        {:ok,
         from(row in query,
           inner_lateral_join: descendant in subquery(descendant_query),
           on: true,
           as: ^as_binding
         )}

      :left ->
        {:ok,
         from(row in query,
           left_lateral_join: descendant in subquery(descendant_query),
           on: true,
           as: ^as_binding
         )}
    end
  end

  @impl true
  @spec ash_postgres_subquery(keyword, any, any, Ecto.Query.t()) ::
          {:ok, Ecto.Query.t()} | {:error, any}
  # Produce a subquery using which will use the given binding and will be
  def ash_postgres_subquery(_opts, current_binding, as_binding, destination_query) do
    immediate_descendants =
      from(destination in Employee,
        where: parent_as(^current_binding).id == destination.manager_id
      )

    cte_name = "employees_#{as_binding}"

    recursive_cte_query =
      recursive_cte_query_for_join(
        immediate_descendants,
        cte_name,
        Employee
      )

    other_query =
      from(row in subquery(recursive_cte_query),
        where:
          row.id in subquery(
            from(row in Ecto.Query.exclude(destination_query, :select), select: row.id)
          )
      )

    {:ok, other_query}
  end

  defp recursive_cte_query(immediate_parents, cte_name, query) do
    recursion_query =
      query
      |> join(:inner, [l], lt in ^cte_name, on: l.manager_id == lt.id)

    descendants_query =
      immediate_parents
      |> union(^recursion_query)

    {cte_name, Employee}
    |> recursive_ctes(true)
    |> with_cte(^cte_name, as: ^descendants_query)
  end

  defp recursive_cte_query_for_join(immediate_parents, cte_name, query) do
    # This is due to limitations in ecto's recursive CTE implementation
    # For more, see here:
    # https://elixirforum.com/t/ecto-cte-queries-without-a-prefix/33148/2
    # https://stackoverflow.com/questions/39458572/ecto-declare-schema-for-a-query
    employee_keys = Employee.__schema__(:fields)

    cte_name_ref =
      from(cte in fragment("?", identifier(^cte_name)), select: map(cte, ^employee_keys))

    recursion_query =
      query
      |> join(:inner, [l], lt in ^cte_name_ref, on: l.manager_id == lt.id)

    descendants_query =
      immediate_parents
      |> union(^recursion_query)

    cte_name_ref
    |> recursive_ctes(true)
    |> with_cte(^cte_name, as: ^descendants_query)
  end
end
```

With the above definition, employees could have a relationship like this:

```elixir
has_many :managed_employees, MyApp.Employee do
  manual MyApp.Employee.ManagedEmployees
end
```

And you could then use it in calculations and aggregates! For example, to see the count of employees managed by each employee:

```elixir
aggregates do
  count :count_of_managed_employees, :managed_employees
end
```
