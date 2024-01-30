defmodule AshPostgres.SubqueryTest do
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.Subquery.{Access, Child, Parent, Through}

  test "joins are wrapped correctly wrapped in subqueries" do
    {:ok, child} = Child.create(%{})
    {:ok, parent} = Parent.create(%{visible: true})
    {:ok, access} = Access.create(%{parent_id: parent.id, email: "foo@bar.com"})
    Through.create(%{parent_id: parent.id, child_id: child.id})

    {:ok, children} =
      Child.read(actor: %{email: "foo@bar.com"})
  end
end
