defmodule AshPostgres.Test.MultiDomainCalculationsTest do
  use AshPostgres.RepoCase, async: false

  require Ash.Query

  test "total is returned correctly" do
    item =
      AshPostgres.Test.MultiDomainCalculations.DomainOne.Item
      |> Ash.Changeset.for_create(:create, %{})
      |> Ash.create!()

    other_item =
      AshPostgres.Test.MultiDomainCalculations.DomainTwo.OtherItem
      |> Ash.Changeset.for_create(:create, %{item_id: item.id})
      |> Ash.create!()

    for i <- 0..2 do
      AshPostgres.Test.MultiDomainCalculations.DomainTwo.SubItem
      |> Ash.Changeset.for_create(:create, %{other_item_id: other_item.id, amount: i})
      |> Ash.create!()
    end

    assert [%{total_amount: 3}] =
             Ash.read!(AshPostgres.Test.MultiDomainCalculations.DomainOne.Item,
               load: [:total_amount]
             )
  end

  test "total using relationship is returned correctly" do
    item =
      AshPostgres.Test.MultiDomainCalculations.DomainOne.Item
      |> Ash.Changeset.for_create(:create, %{key: "key"})
      |> Ash.create!()

    Ash.read!(AshPostgres.Test.MultiDomainCalculations.DomainOne.Item,
      load: [:total_amount_relationship]
    )

    _relationship_item =
      AshPostgres.Test.MultiDomainCalculations.DomainThree.RelationshipItem
      |> Ash.Changeset.for_create(:create, %{key: "key", value: 1})
      |> Ash.create!()

    other_item =
      AshPostgres.Test.MultiDomainCalculations.DomainTwo.OtherItem
      |> Ash.Changeset.for_create(:create, %{item_id: item.id})
      |> Ash.create!()

    for i <- 0..2 do
      AshPostgres.Test.MultiDomainCalculations.DomainTwo.SubItem
      |> Ash.Changeset.for_create(:create, %{other_item_id: other_item.id, amount: i})
      |> Ash.create!()
    end

    assert [%{total_amount_relationship: 3}] =
             Ash.read!(AshPostgres.Test.MultiDomainCalculations.DomainOne.Item,
               load: [:total_amount_relationship]
             )
  end
end
