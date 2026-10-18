# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Yugabyte.CompatibilityTest do
  use ExUnit.Case, async: false

  alias AshPostgres.Yugabyte.{Item, Repo}

  require Ash.Expr

  setup do
    Repo.delete_all(Item)
    on_exit(fn -> Repo.delete_all(Item) end)
    :ok
  end

  test "ordinary creates, reads, updates and destroys persist their results" do
    item = create!(%{key: "ordinary", value: "created"})
    assert item.id
    assert Ash.get!(Item, item.id).value == "created"

    updated = item |> Ash.Changeset.for_update(:update, %{value: "updated"}) |> Ash.update!()
    assert updated.value == "updated"
    assert Ash.get!(Item, item.id).value == "updated"

    Ash.destroy!(updated)
    assert Ash.read!(Item) == []
  end

  test "identity upserts return inserted and updated fields without action metadata" do
    inserted = upsert!(%{key: "single", value: "inserted"})
    updated = upsert!(%{key: "single", value: "updated"})

    assert inserted.value == "inserted"
    assert updated.id == inserted.id
    assert updated.value == "updated"
    assert Ash.get!(Item, inserted.id).value == "updated"
    assert length(Ash.read!(Item)) == 1
    assert_no_action_metadata([inserted, updated])
  end

  test "bulk identity upserts return both inserted and updated records" do
    existing = create!(%{key: "existing", value: "before"})

    assert %Ash.BulkResult{status: :success, records: records} =
             Ash.bulk_create!(
               [%{key: "existing", value: "updated"}, %{key: "new", value: "inserted"}],
               Item,
               :create,
               upsert?: true,
               upsert_identity: :unique_key,
               upsert_fields: [:value],
               return_records?: true
             )

    assert Map.new(records, &{&1.key, &1.value}) ==
             %{"existing" => "updated", "new" => "inserted"}

    assert Enum.find(records, &(&1.key == "existing")).id == existing.id

    assert Map.new(Ash.read!(Item), &{&1.key, &1.value}) ==
             %{"existing" => "updated", "new" => "inserted"}

    assert_no_action_metadata(records)
  end

  test "primary key upserts honor selected fields" do
    id = Ash.UUID.generate()

    for value <- ["inserted", "updated"] do
      item =
        Item
        |> Ash.Changeset.for_create(:create, %{id: id, key: "selected", value: value, score: 10})
        |> Ash.Changeset.select([:id, :value])
        |> Ash.create!(upsert?: true, upsert_fields: [:value])

      assert item.id == id
      assert item.value == value
      assert %Ash.NotLoaded{} = item.score
      assert_no_action_metadata([item])
    end

    assert Ash.get!(Item, id).value == "updated"
  end

  test "conditional upserts retain skipped metadata and the existing value" do
    original = create!(%{key: "skipped", value: "original", score: 10})

    skipped =
      Item
      |> Ash.Changeset.for_create(:create, %{key: "skipped", value: "replacement", score: 10},
        upsert_condition: Ash.Expr.expr(score != upsert_conflict(:score))
      )
      |> Ash.create!(
        upsert?: true,
        upsert_identity: :unique_key,
        upsert_fields: [:value],
        return_skipped_upsert?: true
      )

    assert skipped.id == original.id
    assert skipped.value == "original"
    assert Ash.Resource.get_metadata(skipped, :upsert_skipped)
    assert_no_action_metadata([skipped])
    assert Ash.get!(Item, original.id).value == "original"
  end

  test "bulk upserts persist updates when records are not requested" do
    for value <- ["inserted", "updated"] do
      assert %Ash.BulkResult{status: :success, records: nil} =
               Ash.bulk_create!([%{key: "no-return", value: value}], Item, :create,
                 upsert?: true,
                 upsert_identity: :unique_key,
                 upsert_fields: [:value],
                 return_records?: false
               )
    end

    assert [%{key: "no-return", value: "updated"}] = Ash.read!(Item)
  end

  test "rolling back a transaction undoes an upsert and an ordinary create" do
    original = create!(%{key: "rollback", value: "original"})

    assert {:error, :cancelled} =
             Repo.transaction(fn ->
               upsert!(%{key: "rollback", value: "changed"})
               create!(%{key: "rolled-back", value: "new"})
               Repo.rollback(:cancelled)
             end)

    assert [%{id: id, value: "original"}] = Ash.read!(Item)
    assert id == original.id
  end

  test "unique constraint errors are translated to Ash errors" do
    create!(%{key: "duplicate", value: "original"})

    assert {:error, %Ash.Error.Invalid{}} =
             Item
             |> Ash.Changeset.for_create(:create, %{key: "duplicate", value: "conflict"})
             |> Ash.create()

    assert [%{value: "original"}] = Ash.read!(Item)
    assert create!(%{key: "after-error"}).key == "after-error"
  end

  defp create!(attributes) do
    Item |> Ash.Changeset.for_create(:create, attributes) |> Ash.create!()
  end

  defp upsert!(attributes) do
    Item
    |> Ash.Changeset.for_create(:create, attributes)
    |> Ash.create!(upsert?: true, upsert_identity: :unique_key, upsert_fields: [:value])
  end

  defp assert_no_action_metadata(records) do
    for record <- records do
      refute Map.has_key?(record.__metadata__, :upsert_action)
    end
  end
end
