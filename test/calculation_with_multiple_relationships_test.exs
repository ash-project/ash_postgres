# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.CalculationWithMultipleRelationshipsTest do
  @moduledoc """
  Tests for calculations using multiple relationships to the same resource
  with different read actions on the Postgres data layer.

  Bug verification: When two relationships are defined to the same resource with different
  read actions, calculations using each relationship should respect the correct read_action.

  This tests the same behavior as Ash.Test.CalculationWithMultipleRelationshipsTest
  but with the Postgres data layer to ensure SQL generation is correct.
  """
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.{Container, Item}

  test "calculations use correct read actions from their respective relationships" do
    container = Ash.Seed.seed!(Container, %{})

    item =
      Ash.Seed.seed!(Item, %{
        container_id: container.id,
        name: "Inactive Item",
        active: false
      })

    loaded_container = Ash.load!(container, [:item_all])
    assert item.id == loaded_container.item_all.id

    loaded_container = Ash.load!(container, [:item_active])
    assert nil == loaded_container.item_active

    loaded_container = Ash.load!(container, [:active_item_name, :all_item_name])

    assert loaded_container.active_item_name == nil

    assert loaded_container.all_item_name == "Inactive Item"
  end

  test "loading calculations one at a time works" do
    container = Ash.Seed.seed!(Container, %{})

    item =
      Ash.Seed.seed!(Item, %{
        container_id: container.id,
        name: "Inactive Item",
        active: false
      })

    loaded_container = Ash.load!(container, [:item_all])
    assert item.id == loaded_container.item_all.id

    loaded_container = Ash.load!(container, [:item_active])
    assert nil == loaded_container.item_active

    loaded_container = Ash.load!(container, [:active_item_name])
    assert loaded_container.active_item_name == nil

    loaded_container = Ash.load!(container, [:all_item_name])
    assert loaded_container.all_item_name == "Inactive Item"
  end

  test "with active item, both calculations return values" do
    container = Ash.Seed.seed!(Container, %{})

    item =
      Ash.Seed.seed!(Item, %{
        container_id: container.id,
        name: "Active Item",
        active: true
      })

    loaded_container = Ash.load!(container, [:item_all])
    assert item.id == loaded_container.item_all.id

    loaded_container = Ash.load!(container, [:item_active])
    assert item.id == loaded_container.item_active.id

    loaded_container = Ash.load!(container, [:active_item_name, :all_item_name])

    assert loaded_container.active_item_name == "Active Item"
    assert loaded_container.all_item_name == "Active Item"
  end

  test "multiple containers with mixed active/inactive items" do
    container1 = Ash.Seed.seed!(Container, %{})

    Ash.Seed.seed!(Item, %{
      container_id: container1.id,
      name: "Inactive Item 1",
      active: false
    })

    container2 = Ash.Seed.seed!(Container, %{})

    Ash.Seed.seed!(Item, %{
      container_id: container2.id,
      name: "Active Item 2",
      active: true
    })

    _container3 = Ash.Seed.seed!(Container, %{})

    containers =
      Container
      |> Ash.Query.sort(:id)
      |> Ash.Query.load([:active_item_name, :all_item_name])
      |> Ash.read!()

    [loaded1, loaded2, loaded3] = containers

    assert loaded1.active_item_name == nil
    assert loaded1.all_item_name == "Inactive Item 1"

    assert loaded2.active_item_name == "Active Item 2"
    assert loaded2.all_item_name == "Active Item 2"

    assert loaded3.active_item_name == nil
    assert loaded3.all_item_name == nil
  end
end
