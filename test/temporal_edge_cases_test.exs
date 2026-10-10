# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.TemporalEdgeCasesTest do
  @moduledoc "Temporal writes against tables set up in less common ways."
  use AshPostgres.RepoCase, async: false

  @moduletag :temporal
  @moduletag :postgres_18

  require Ash.Query
  alias AshPostgres.TemporalTestRepo

  defmodule Domain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource(AshPostgres.TemporalEdgeCasesTest.PlainKeyed)
      resource(AshPostgres.TemporalEdgeCasesTest.Tenanted)
      resource(AshPostgres.TemporalEdgeCasesTest.SecondsPrecision)
    end
  end

  defmodule PlainKeyed do
    @moduledoc false
    use Ash.Resource, domain: Domain, data_layer: AshPostgres.DataLayer

    postgres do
      table("temporal_plain_keyed")
      repo(AshPostgres.TemporalTestRepo)
    end

    temporal do
      strategy(:context)
      attribute(:valid_at)
    end

    attributes do
      attribute(:id, :integer, primary_key?: true, allow_nil?: false, public?: true)
      attribute(:note, :string, public?: true)
    end

    actions do
      defaults([:read, update: [:note]])
    end
  end

  defmodule Tenanted do
    @moduledoc false
    use Ash.Resource, domain: Domain, data_layer: AshPostgres.DataLayer

    postgres do
      table("temporal_tenanted")
      repo(AshPostgres.TemporalTestRepo)
    end

    multitenancy do
      strategy(:context)
    end

    temporal do
      strategy(:context)
      attribute(:valid_at)
    end

    attributes do
      attribute(:id, :integer, primary_key?: true, allow_nil?: false, public?: true)
      attribute(:note, :string, public?: true)
    end

    actions do
      defaults([:read, create: [:id, :note], update: [:note]])
    end
  end

  # A period declared at seconds precision, so every write's `as_of` is cast to the second.
  defmodule SecondsPrecision do
    @moduledoc false
    use Ash.Resource, domain: Domain, data_layer: AshPostgres.DataLayer

    postgres do
      table("temporal_seconds_precision")
      repo(AshPostgres.TemporalTestRepo)
    end

    temporal do
      strategy(:context)
      attribute(:valid_at)
    end

    attributes do
      attribute(:id, :integer, primary_key?: true, allow_nil?: false, public?: true)
      attribute(:note, :string, public?: true)

      attribute(:valid_at, Ash.Type.Range,
        allow_nil?: false,
        constraints: [
          inner_type: :utc_datetime,
          lower: [inclusive?: true],
          upper: [inclusive?: false]
        ],
        public?: true
      )
    end

    actions do
      defaults([:read, :destroy, create: [:id, :note]])

      update :update do
        primary?(true)
        require_atomic?(true)
        accept([:note])
      end

      update :update_nonatomic do
        require_atomic?(false)
        accept([:note])
      end
    end
  end

  @jan1 ~U[2026-01-01 00:00:00.000000Z]
  @feb1 ~U[2026-02-01 00:00:00.000000Z]
  @mar1 ~U[2026-03-01 00:00:00.000000Z]

  defp rows(table) do
    TemporalTestRepo.query!(
      "SELECT note, lower(valid_at), upper(valid_at) FROM #{table} ORDER BY lower(valid_at)"
    ).rows
  end

  describe "a table with a plain primary key" do
    setup do
      # What migrations generated before 2.14.1 created on PostgreSQL 18
      TemporalTestRepo.query!("""
      CREATE TABLE temporal_plain_keyed (
        id integer PRIMARY KEY,
        note text,
        valid_at tstzrange NOT NULL
      )
      """)

      TemporalTestRepo.query!(
        "INSERT INTO temporal_plain_keyed VALUES (1, 'a', tstzrange('2026-01-01', NULL))"
      )

      :ok
    end

    test "a split fails with an error that says what's wrong with the table" do
      [record] =
        PlainKeyed |> Ash.Query.filter(id == 1) |> Ash.Query.as_of(@mar1) |> Ash.read!()

      assert {:error, error} =
               record
               |> Ash.Changeset.for_update(:update, %{note: "b"})
               |> Ash.Changeset.as_of(@mar1)
               |> Ash.update()

      assert Exception.message(error) =~ "isn't `WITHOUT OVERLAPS`"
      assert [["a", @jan1, nil]] = rows("temporal_plain_keyed")
    end
  end

  describe "schema-based multitenancy" do
    setup do
      TemporalTestRepo.query!("CREATE SCHEMA tenant_a")

      TemporalTestRepo.query!("""
      CREATE TABLE tenant_a.temporal_tenanted (
        id integer NOT NULL,
        note text,
        valid_at tstzrange NOT NULL,
        PRIMARY KEY (id, valid_at WITHOUT OVERLAPS)
      )
      """)

      TemporalTestRepo.query!(
        "INSERT INTO tenant_a.temporal_tenanted VALUES (1, 'a', tstzrange('2026-01-01', NULL))"
      )

      :ok
    end

    test "an update splits the row in the tenant's schema" do
      [record] =
        Tenanted
        |> Ash.Query.filter(id == 1)
        |> Ash.Query.as_of(@mar1)
        |> Ash.Query.set_tenant("tenant_a")
        |> Ash.read!()

      record
      |> Ash.Changeset.for_update(:update, %{note: "b"}, tenant: "tenant_a")
      |> Ash.Changeset.as_of(@mar1)
      |> Ash.update!()

      assert [["a", @jan1, @mar1], ["b", @mar1, nil]] = rows("tenant_a.temporal_tenanted")
    end

    test "an upsert splits the row in the tenant's schema" do
      Tenanted
      |> Ash.Changeset.for_create(:create, %{id: 1, note: "b"}, tenant: "tenant_a")
      |> Ash.Changeset.as_of(@feb1)
      |> Ash.create!(upsert?: true)

      assert [["a", @jan1, @feb1], ["b", @feb1, nil]] = rows("tenant_a.temporal_tenanted")
    end
  end

  describe "a period declared at seconds precision" do
    # Two instants within the same second
    @early ~U[2026-03-01 00:00:12.100000Z]
    @late ~U[2026-03-01 00:00:12.900000Z]
    @second ~U[2026-03-01 00:00:12.000000Z]

    setup do
      TemporalTestRepo.query!("""
      CREATE TABLE temporal_seconds_precision (
        id integer NOT NULL,
        note text,
        valid_at tstzrange NOT NULL,
        PRIMARY KEY (id, valid_at WITHOUT OVERLAPS)
      )
      """)

      :ok
    end

    defp seconds_precision_at(as_of) do
      SecondsPrecision
      |> Ash.Query.filter(id == 1)
      |> Ash.Query.as_of(as_of)
      |> Ash.read_one!()
    end

    test "a write that isn't back-dated is visible at the current second" do
      Ash.create!(SecondsPrecision, %{id: 1, note: "a"})

      assert %{note: "a", valid_at: %{lower: lower}} =
               seconds_precision_at(DateTime.truncate(DateTime.utc_now(), :second))

      assert lower.microsecond == {0, 0}
    end

    test "a create's period starts at the second its as_of falls in" do
      created = Ash.create!(SecondsPrecision, %{id: 1, note: "a"}, as_of: @early)
      assert created.valid_at.lower == ~U[2026-03-01 00:00:12Z]
    end

    for action <- [:update, :update_nonatomic] do
      test "#{action} in the same second as the create replaces it without an empty period" do
        Ash.create!(SecondsPrecision, %{id: 1, note: "a"}, as_of: @early)

        @late
        |> seconds_precision_at()
        |> Ash.Changeset.for_update(unquote(action), %{note: "b"}, as_of: @late)
        |> Ash.update!()

        assert [["b", @second, nil]] = rows("temporal_seconds_precision")
      end
    end

    test "two updates in the same second leave one version from that second" do
      Ash.create!(SecondsPrecision, %{id: 1, note: "a"}, as_of: @jan1)

      for {note, as_of} <- [{"b", @early}, {"c", @late}] do
        as_of
        |> seconds_precision_at()
        |> Ash.Changeset.for_update(:update, %{note: note}, as_of: as_of)
        |> Ash.update!()
      end

      assert [["a", @jan1, @second], ["c", @second, nil]] = rows("temporal_seconds_precision")
    end

    test "a destroy in the same second as the create leaves no version behind" do
      SecondsPrecision
      |> Ash.create!(%{id: 1, note: "a"}, as_of: @early)
      |> Ash.Changeset.for_destroy(:destroy, %{}, as_of: @late)
      |> Ash.destroy!()

      assert [] = rows("temporal_seconds_precision")
    end

    test "an upsert in the same second as the create replaces it without an empty period" do
      Ash.create!(SecondsPrecision, %{id: 1, note: "a"}, as_of: @early)

      assert %Ash.BulkResult{status: :success} =
               Ash.bulk_create!([%{id: 1, note: "b"}], SecondsPrecision, :create,
                 upsert?: true,
                 upsert_fields: [:note],
                 as_of: @late,
                 return_errors?: true
               )

      assert [["b", @second, nil]] = rows("temporal_seconds_precision")
    end
  end
end
