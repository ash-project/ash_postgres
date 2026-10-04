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
end
