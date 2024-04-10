# Manual Relationships

See [Defining Manual Relationships](https://hexdocs.pm/ash/defining-manual-relationships.html) for an idea of manual relationships in general.
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
