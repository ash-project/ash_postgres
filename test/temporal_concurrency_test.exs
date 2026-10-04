# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.TemporalConcurrencyTest do
  @moduledoc """
  Concurrent temporal writes under READ COMMITTED. A write that blocks on a version
  another transaction is splitting must still apply once that transaction commits, even
  though the version it found has moved and the leftovers are newer than its snapshot.

  These need real, committed transactions on separate connections, so they run outside
  the sandbox and clean up after themselves.
  """
  use ExUnit.Case, async: false

  @moduletag :temporal
  @moduletag :postgres_18

  require Ash.Query
  alias AshPostgres.TemporalTestRepo
  alias AshPostgres.Test.Temporal.Subscription
  alias Ecto.Adapters.SQL.Sandbox

  defmodule Domain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource(AshPostgres.TemporalConcurrencyTest.Named)
    end
  end

  # A temporal resource with an identity, for upserts keyed on it rather than the primary key
  defmodule Named do
    @moduledoc false
    use Ash.Resource, domain: Domain, data_layer: AshPostgres.DataLayer

    postgres do
      table("temporal_named")
      repo(AshPostgres.TemporalTestRepo)
    end

    temporal do
      strategy(:context)
      attribute(:valid_at)
    end

    attributes do
      attribute(:id, :integer, primary_key?: true, allow_nil?: false, public?: true)
      attribute(:name, :string, public?: true)
      attribute(:note, :string, public?: true)

      attribute(:valid_at, Ash.Type.Range,
        allow_nil?: false,
        constraints: [
          inner_type: :datetime,
          inner_constraints: [precision: :microsecond],
          lower: [inclusive?: true],
          upper: [inclusive?: false]
        ],
        public?: true
      )
    end

    identities do
      identity(:unique_name, [:name])
    end

    actions do
      defaults([:read, create: [:id, :name, :note]])
    end
  end

  @jan1 ~U[2026-01-01 00:00:00.000000Z]
  @jan15 ~U[2026-01-15 00:00:00.000000Z]
  @feb1 ~U[2026-02-01 00:00:00.000000Z]
  @mar1 ~U[2026-03-01 00:00:00.000000Z]

  setup do
    :ok = Sandbox.checkout(TemporalTestRepo, sandbox: false)
    cleanup()

    TemporalTestRepo.query!(
      "INSERT INTO tier (id, name, valid_at) VALUES (100, 'basic', tstzrange('2026-01-01', NULL))"
    )

    TemporalTestRepo.query!("""
    INSERT INTO subscription (id, tier, tier_id, seats, valid_at) VALUES
      (101, 'orig', 100, 1, tstzrange('2026-01-01', NULL)),
      (102, 'orig', 100, 1, tstzrange('2026-01-01', NULL))
    """)

    on_exit(fn ->
      checkout_unsandboxed()
      cleanup()
    end)
  end

  # `on_exit` callbacks share a process, so a later one finds the connection checked out.
  defp checkout_unsandboxed do
    case Sandbox.checkout(TemporalTestRepo, sandbox: false) do
      :ok -> :ok
      {:already, :owner} -> :ok
    end
  end

  defp cleanup do
    TemporalTestRepo.query!("DELETE FROM subscription WHERE id IN (101, 102, 103)")
    TemporalTestRepo.query!("DELETE FROM tier WHERE id = 100")
  end

  # Runs `fun` in a transaction on its own connection and holds it open until released.
  defp hold_open(fun) do
    parent = self()

    task =
      Task.async(fn ->
        :ok = Sandbox.checkout(TemporalTestRepo, sandbox: false)

        TemporalTestRepo.transaction(fn ->
          fun.()
          send(parent, :written)

          receive do
            :commit -> :ok
          end
        end)
      end)

    assert_receive :written, 5_000
    task
  end

  # Starts `fun` on its own connection, lets it block on the held transaction, then
  # commits that transaction so `fun` resumes.
  defp race(held, fun) do
    task =
      Task.async(fn ->
        :ok = Sandbox.checkout(TemporalTestRepo, sandbox: false)
        fun.()
      end)

    Process.sleep(300)
    send(held.pid, :commit)
    Task.await(held)
    Task.await(task)
  end

  defp change_tier(id, tier, as_of) do
    Subscription
    |> Ash.Query.filter(id == ^id)
    |> Ash.Query.as_of(as_of)
    |> Ash.read_one!()
    |> Ash.Changeset.for_update(:change_tier, %{tier: tier})
    |> Ash.Changeset.as_of(as_of)
    |> Ash.update!()
  end

  defp add_seat_to_all(as_of) do
    Subscription
    |> Ash.Query.filter(id in [101, 102])
    |> Ash.Query.as_of(as_of)
    |> Ash.bulk_update!(:add_seat, %{}, strategy: :atomic)
  end

  defp upsert(id, tier, as_of) do
    Subscription
    |> Ash.Changeset.for_create(:create, %{id: id, tier: tier, tier_id: 100, seats: 1})
    |> Ash.Changeset.as_of(as_of)
    |> Ash.create!(upsert?: true)
  end

  defp timeline(id, column) do
    TemporalTestRepo.query!(
      "SELECT lower(valid_at), upper(valid_at), #{column} FROM subscription " <>
        "WHERE id = $1 ORDER BY lower(valid_at)",
      [id]
    ).rows
  end

  test "an update isn't lost when the version it found is split under it" do
    held = hold_open(fn -> change_tier(101, "a", @feb1) end)
    race(held, fn -> change_tier(101, "b", @jan15) end)

    assert [[@jan1, @jan15, "orig"], [@jan15, @feb1, "b"], [@feb1, nil, "a"]] =
             timeline(101, "tier")
  end

  test "an update isn't lost when the version it found is ended under it" do
    held =
      hold_open(fn ->
        Subscription
        |> Ash.Query.filter(id == 101)
        |> Ash.Query.as_of(@feb1)
        |> Ash.bulk_destroy!(:expire, %{}, strategy: :atomic)
      end)

    race(held, fn -> change_tier(101, "b", @jan15) end)

    assert [[@jan1, @jan15, "orig"], [@jan15, @feb1, "b"]] = timeline(101, "tier")
  end

  test "a bulk update isn't lost on any record whose version is split under it" do
    held = hold_open(fn -> add_seat_to_all(@feb1) end)
    race(held, fn -> add_seat_to_all(@jan15) end)

    for id <- [101, 102] do
      assert [[@jan1, @jan15, 1], [@jan15, @feb1, 2], [@feb1, nil, 2]] = timeline(id, "seats")
    end
  end

  test "two upserts inserting the same new record both apply" do
    held = hold_open(fn -> upsert(103, "a", @jan1) end)
    race(held, fn -> upsert(103, "b", @feb1) end)

    assert [[@jan1, @feb1, "a"], [@feb1, nil, "b"]] = timeline(103, "tier")
  end

  test "a bulk upsert retries just the record that lost an insert race" do
    held = hold_open(fn -> upsert(103, "a", @jan1) end)

    result =
      race(held, fn ->
        Ash.bulk_create!(
          [
            %{id: 101, tier: "b", tier_id: 100, seats: 1},
            %{id: 103, tier: "b", tier_id: 100, seats: 1}
          ],
          Subscription,
          :create,
          upsert?: true,
          upsert_fields: [:tier],
          as_of: @feb1,
          return_records?: true,
          return_errors?: true
        )
      end)

    assert %Ash.BulkResult{status: :success, records: records} = result
    assert records |> Enum.map(& &1.id) |> Enum.sort() == [101, 103]
    assert [[@jan1, @feb1, "orig"], [@feb1, nil, "b"]] = timeline(101, "tier")
    assert [[@jan1, @feb1, "a"], [@feb1, nil, "b"]] = timeline(103, "tier")
  end

  test "two upserts on an identity, creating the same new record, both apply" do
    TemporalTestRepo.query!("""
    CREATE TABLE temporal_named (
      id integer NOT NULL,
      name text,
      note text,
      valid_at tstzrange NOT NULL,
      PRIMARY KEY (id, valid_at WITHOUT OVERLAPS),
      CONSTRAINT temporal_named_unique_name_index
        EXCLUDE USING gist (name WITH =, valid_at WITH &&)
    )
    """)

    on_exit(fn ->
      checkout_unsandboxed()
      TemporalTestRepo.query!("DROP TABLE IF EXISTS temporal_named")
    end)

    upsert = fn id, note, as_of ->
      Named
      |> Ash.Changeset.for_create(:create, %{id: id, name: "x", note: note}, as_of: as_of)
      |> Ash.create!(upsert?: true, upsert_identity: :unique_name, upsert_fields: [:note])
    end

    held = hold_open(fn -> upsert.(301, "a", @jan1) end)
    race(held, fn -> upsert.(302, "b", @feb1) end)

    assert [[301, "a", @jan1, @feb1], [301, "b", @feb1, nil]] =
             TemporalTestRepo.query!(
               "SELECT id, note, lower(valid_at), upper(valid_at) FROM temporal_named " <>
                 "ORDER BY lower(valid_at)"
             ).rows
  end

  test "a write over a range isn't lost when a version it found is split under it" do
    held = hold_open(fn -> change_tier(101, "a", @feb1) end)

    [record] =
      Subscription |> Ash.Query.filter(id == 101) |> Ash.Query.as_of(@jan15) |> Ash.read!()

    range = %Ash.Range{lower: @jan15, upper: @mar1, bounds: :"[)"}

    race(held, fn ->
      Ash.bulk_update!([record], :add_seat, %{}, as_of: range, strategy: [:atomic])
    end)

    assert [
             [@jan1, @jan15, "orig", 1],
             [@jan15, @feb1, "orig", 2],
             [@feb1, @mar1, "a", 2],
             [@mar1, nil, "a", 1]
           ] = timeline(101, "tier, seats")
  end
end
