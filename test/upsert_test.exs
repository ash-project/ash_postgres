# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.UpsertTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Post

  test "empty upserts" do
    id = Ash.UUID.generate()

    new_post =
      Post
      |> Ash.Changeset.for_create(:create, %{
        id: id,
        title: "title2"
      })
      |> Ash.create!()

    assert new_post.id == id
    assert new_post.created_at == new_post.updated_at

    updated_post =
      Post
      |> Ash.Changeset.for_create(
        :create,
        %{
          id: id,
          title: "title2"
        },
        upsert?: true,
        upsert_fields: [],
        return_skipped_upsert?: true
      )
      |> Ash.create!()

    assert updated_post.id == id
    assert updated_post.updated_at == new_post.updated_at
  end

  test "upserting results in the same created_at timestamp, but a new updated_at timestamp" do
    id = Ash.UUID.generate()

    new_post =
      Post
      |> Ash.Changeset.for_create(:create, %{
        id: id,
        title: "title2"
      })
      |> Ash.create!(upsert?: true)

    assert new_post.id == id
    assert new_post.created_at == new_post.updated_at

    updated_post =
      Post
      |> Ash.Changeset.for_create(:create, %{
        id: id,
        title: "title2"
      })
      |> Ash.create!(upsert?: true)

    assert updated_post.id == id
    assert updated_post.created_at == new_post.created_at
    assert updated_post.created_at != updated_post.updated_at
  end

  test "upserting a field with a default sets to the new value" do
    id = Ash.UUID.generate()

    new_post =
      Post
      |> Ash.Changeset.for_create(:create, %{
        id: id,
        title: "title2"
      })
      |> Ash.create!(upsert?: true)

    assert new_post.id == id
    assert new_post.created_at == new_post.updated_at

    updated_post =
      Post
      |> Ash.Changeset.for_create(:create, %{
        id: id,
        title: "title2",
        decimal: Decimal.new(5)
      })
      |> Ash.create!(upsert?: true)

    assert updated_post.id == id
    assert Decimal.equal?(updated_post.decimal, Decimal.new(5))
  end

  test "upsert with touch_update_defaults? false does not update updated_at" do
    id = Ash.UUID.generate()
    past = DateTime.add(DateTime.utc_now(), -60, :second)

    Post
    |> Ash.Changeset.for_create(:create, %{
      id: id,
      title: "title",
      updated_at: past
    })
    |> Ash.create!()

    assert [%{updated_at: backdated}] = Ash.read!(Post)
    assert DateTime.compare(backdated, past) == :eq

    upserted =
      Post
      |> Ash.Changeset.for_create(:create, %{
        id: id,
        title: "title2"
      })
      |> Ash.create!(upsert?: true, touch_update_defaults?: false)

    assert DateTime.compare(upserted.updated_at, past) == :eq
  end

  test "upsert with empty upsert_fields does not update updated_at" do
    id = Ash.UUID.generate()
    past = DateTime.add(DateTime.utc_now(), -60, :second)

    Post
    |> Ash.Changeset.for_create(:create, %{
      id: id,
      title: "title",
      updated_at: past
    })
    |> Ash.create!()

    assert [%{updated_at: backdated}] = Ash.read!(Post)
    assert DateTime.compare(backdated, past) == :eq

    upserted =
      Post
      |> Ash.Changeset.for_create(:create, %{
        id: id,
        title: "title2"
      })
      |> Ash.create!(upsert?: true, upsert_fields: [])

    assert DateTime.compare(upserted.updated_at, past) == :eq
  end

  describe "upsert_action metadata (MERGE, PostgreSQL 17+)" do
    # Below PG 17, upserts use INSERT ... ON CONFLICT, which cannot report whether each row
    # was inserted or updated; this metadata is only populated on the MERGE path.
    @describetag :postgres_17

    test "a created record is tagged :insert and an updated record is tagged :update" do
      id = Ash.UUID.generate()

      created =
        Post
        |> Ash.Changeset.for_create(:create, %{id: id, title: "title"})
        |> Ash.create!(upsert?: true)

      assert Ash.Resource.get_metadata(created, :upsert_action) == :insert

      updated =
        Post
        |> Ash.Changeset.for_create(:create, %{id: id, title: "title2"})
        |> Ash.create!(upsert?: true)

      assert Ash.Resource.get_metadata(updated, :upsert_action) == :update
    end

    test "bulk upserts tag each record according to its action" do
      existing_id = Ash.UUID.generate()
      new_id = Ash.UUID.generate()

      Post
      |> Ash.Changeset.for_create(:create, %{id: existing_id, title: "existing"})
      |> Ash.create!()

      %Ash.BulkResult{records: records} =
        Ash.bulk_create!(
          [
            %{id: existing_id, title: "updated"},
            %{id: new_id, title: "brand new"}
          ],
          Post,
          :create,
          upsert?: true,
          upsert_fields: [:title],
          return_records?: true
        )

      actions =
        Map.new(records, fn record ->
          {record.id, Ash.Resource.get_metadata(record, :upsert_action)}
        end)

      assert actions[existing_id] == :update
      assert actions[new_id] == :insert
    end
  end
end
