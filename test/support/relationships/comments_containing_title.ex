defmodule AshPostgres.Test.Post.CommentsContainingTitle do
  @moduledoc false

  use Ash.Resource.ManualRelationship
  use AshPostgres.ManualRelationship
  require Ash.Query
  require Ecto.Query

  def load(posts, _opts, %{query: query, actor: actor, authorize?: authorize?}) do
    post_ids = Enum.map(posts, & &1.id)

    {:ok,
     query
     |> Ash.Query.filter(post_id in ^post_ids)
     |> Ash.Query.filter(contains(title, post.title))
     |> Ash.read!(actor: actor, authorize?: authorize?)
     |> Enum.group_by(& &1.post_id)}
  end

  def ash_postgres_join(query, _opts, current_binding, as_binding, :inner, destination_query) do
    {:ok,
     Ecto.Query.from(_ in query,
       join: dest in ^destination_query,
       as: ^as_binding,
       on: dest.post_id == as(^current_binding).id,
       on: fragment("strpos(?, ?) > 0", dest.title, as(^current_binding).title)
     )}
  end

  def ash_postgres_join(query, _opts, current_binding, as_binding, :left, destination_query) do
    {:ok,
     Ecto.Query.from(_ in query,
       left_join: dest in ^destination_query,
       as: ^as_binding,
       on: dest.post_id == as(^current_binding).id,
       on: fragment("strpos(?, ?) > 0", dest.title, as(^current_binding).title)
     )}
  end

  def ash_postgres_subquery(_opts, current_binding, as_binding, destination_query) do
    {:ok,
     Ecto.Query.from(_ in destination_query,
       where: parent_as(^current_binding).id == as(^as_binding).post_id,
       where:
         fragment("strpos(?, ?) > 0", as(^as_binding).title, parent_as(^current_binding).title)
     )}
  end
end
