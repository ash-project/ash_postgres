# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.UpsertTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Post

  require Ash.Expr

  defmodule Domain do
    @moduledoc false
    use Ash.Domain

    resources do
      allow_unregistered?(true)
    end
  end

  # Deliberately kept out of the configured domains (and so out of
  # `test_priv/test_repo/migrations`): its unique index needs `NULLS NOT DISTINCT`,
  # which PostgreSQL 14 can't parse. The test creates the table itself.
  defmodule NullableIdentityRecord do
    @moduledoc false
    use Ash.Resource,
      domain: Domain,
      data_layer: AshPostgres.DataLayer

    postgres do
      table("nullable_identity_records")
      repo(AshPostgres.TestRepo)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:uniq_one, :string, public?: true)
      attribute(:uniq_two, :string, public?: true)
      attribute(:price, :integer, public?: true)
    end

    identities do
      # `nils_distinct?: false` matches the `NULLS NOT DISTINCT` index, so two
      # nil `uniq_two` values conflict. Both upsert implementations need it:
      # `INSERT ... ON CONFLICT` renders a conflict target Postgres resolves
      # against that index, and `MERGE` (17+) widens its `ON` comparison to be
      # nil-safe.
      identity(:uniq_one_and_two, [:uniq_one, :uniq_two]) do
        nils_distinct?(false)
      end
    end

    actions do
      default_accept(:*)
      defaults([:read, create: :*])
    end
  end

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

  # `NULLS NOT DISTINCT` (which is what makes two nil keys conflict at all)
  # requires PostgreSQL 15+.
  @tag :postgres_15
  test "returns a skipped upsert whose identity contains nil" do
    AshPostgres.TestRepo.query!("""
    CREATE TABLE nullable_identity_records (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      uniq_one text,
      uniq_two text,
      price bigint
    )
    """)

    AshPostgres.TestRepo.query!("""
    CREATE UNIQUE INDEX nullable_identity_records_uniq_one_and_two_index
    ON nullable_identity_records (uniq_one, uniq_two) NULLS NOT DISTINCT
    """)

    original =
      NullableIdentityRecord
      |> Ash.Changeset.for_create(:create, %{
        uniq_one: "one",
        uniq_two: nil,
        price: 10
      })
      |> Ash.create!()

    skipped =
      NullableIdentityRecord
      |> Ash.Changeset.for_create(
        :create,
        %{uniq_one: "one", uniq_two: nil, price: 20},
        upsert?: true,
        upsert_identity: :uniq_one_and_two,
        upsert_fields: [:price],
        upsert_condition: Ash.Expr.expr(false),
        return_skipped_upsert?: true
      )
      |> Ash.create!()

    assert skipped.id == original.id
    assert skipped.price == 10
    assert Ash.Resource.get_metadata(skipped, :upsert_skipped)
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
