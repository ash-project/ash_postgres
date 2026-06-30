# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.TemporalTest do
  @moduledoc """
  End-to-end temporal (bitemporal) tests against Postgres 19.

  Exercises `as_of` time-travel reads, `now()` anchoring (filters/calcs/atomics),
  the `Ash.Type.Range` <-> `Postgrex.Range` bridge, `FOR PORTION OF` mutations,
  `range_overlaps/2`, and `temporal_keys` relationships.

  Tagged `:temporal`; run with:

      ASH_VERSION=local ASH_SQL_VERSION=local mix test test/temporal_test.exs --include temporal
  """
  use AshPostgres.RepoCase, async: false

  @moduletag :temporal

  require Ash.Query
  require Ash.Expr
  alias AshPostgres.Test.Temporal.{Event, Subscription, Tier}
  alias AshPostgres.TestRepo

  @jan15 ~U[2026-01-15 00:00:00.000000Z]
  @mar1 ~U[2026-03-01 00:00:00.000000Z]

  setup do
    # tier first: the temporal PERIOD foreign key requires the referenced tier
    # period to exist (and cover the subscription's period) before insert.
    TestRepo.query!(
      "INSERT INTO tier (id, name, valid_at) VALUES (10, 'basic', tstzrange('2026-01-01','2026-06-01','[)'))"
    )

    TestRepo.query!("""
    INSERT INTO subscription (id, tier, tier_id, seats, activated_at, valid_at) VALUES
      (1, 'bronze', 10, 3, '2026-02-15', tstzrange('2026-01-01','2026-02-01','[)')),
      (1, 'gold',   10, 5, '2026-02-15', tstzrange('2026-02-01','2026-04-01','[)'))
    """)

    TestRepo.query!("""
    INSERT INTO event (id, name, created) VALUES
      (1, 'early', '2026-01-01'), (2, 'late', '2026-02-01')
    """)

    :ok
  end

  defp tiers(records), do: records |> Enum.map(& &1.tier) |> Enum.sort()

  defp subscription_timeline(id) do
    TestRepo.query!(
      "SELECT tier, lower(valid_at), upper(valid_at) FROM subscription WHERE id = $1 ORDER BY lower(valid_at)",
      [id]
    ).rows
  end

  defp seats_timeline(id) do
    TestRepo.query!(
      "SELECT tier, seats, lower(valid_at) FROM subscription WHERE id = $1 ORDER BY lower(valid_at)",
      [id]
    ).rows
  end

  describe "default as_of (reads are current-state by default)" do
    test "get / read without as_of returns the currently-valid period, not all history" do
      # id=8: a past period + a current open-ended one (tier_id NULL avoids the PERIOD FK)
      TestRepo.query!("""
      INSERT INTO subscription (id, tier, tier_id, valid_at) VALUES
        (8, 'old',     NULL, tstzrange('2020-01-01','2021-01-01','[)')),
        (8, 'current', NULL, tstzrange('2021-01-01', NULL, '[)'))
      """)

      # get-by-id with NO as_of -> the period valid now (no MultipleResults across periods)
      assert %{tier: "current"} = Ash.get!(Subscription, 8)

      # plain read with NO as_of -> only the current period
      assert ["current"] = Subscription |> Ash.Query.filter(id == 8) |> Ash.read!() |> tiers()
    end
  end

  describe "as_of reads" do
    test "returns the row valid at the as_of instant" do
      assert ["bronze"] =
               Subscription
               |> Ash.Query.filter(id == 1)
               |> Ash.Query.as_of(@jan15)
               |> Ash.read!()
               |> tiers()

      assert ["gold"] =
               Subscription
               |> Ash.Query.filter(id == 1)
               |> Ash.Query.as_of(@mar1)
               |> Ash.read!()
               |> tiers()
    end
  end

  describe "sorting through a temporal relationship" do
    setup do
      # tier 30 changes name across two adjacent periods; tier 40 is constant.
      TestRepo.query!("""
      INSERT INTO tier (id, name, valid_at) VALUES
        (30, 'mango',  tstzrange('2026-01-01','2026-03-01','[)')),
        (30, 'apple',  tstzrange('2026-03-01','2026-06-01','[)')),
        (40, 'cherry', tstzrange('2026-01-01','2026-06-01','[)'))
      """)

      # Each subscription spans the whole window (sub 5's span covers BOTH of tier 30's
      # periods — the as_of join must pick the single covering tier row, not both).
      TestRepo.query!("""
      INSERT INTO subscription (id, tier, tier_id, valid_at) VALUES
        (5, 'sub5', 30, tstzrange('2026-01-01','2026-06-01','[)')),
        (6, 'sub6', 40, tstzrange('2026-01-01','2026-06-01','[)'))
      """)

      :ok
    end

    defp ids(records), do: Enum.map(records, & &1.id)

    test "sort by `relationship.field` respects as_of (order flips across periods)" do
      # @jan15: sub5->mango, sub6->cherry  => asc: cherry(6) < mango(5)
      assert [6, 5] =
               Subscription
               |> Ash.Query.filter(id in [5, 6])
               |> Ash.Query.sort("tier_record.name")
               |> Ash.Query.as_of(@jan15)
               |> Ash.read!()
               |> ids()

      # @mar1: sub5->apple, sub6->cherry  => asc: apple(5) < cherry(6)
      assert [5, 6] =
               Subscription
               |> Ash.Query.filter(id in [5, 6])
               |> Ash.Query.sort("tier_record.name")
               |> Ash.Query.as_of(@mar1)
               |> Ash.read!()
               |> ids()
    end

    test "sort by an aggregate over the temporal relationship respects as_of" do
      assert [6, 5] =
               Subscription
               |> Ash.Query.filter(id in [5, 6])
               |> Ash.Query.sort(tier_name: :asc)
               |> Ash.Query.as_of(@jan15)
               |> Ash.read!()
               |> ids()

      assert [5, 6] =
               Subscription
               |> Ash.Query.filter(id in [5, 6])
               |> Ash.Query.sort(tier_name: :asc)
               |> Ash.Query.as_of(@mar1)
               |> Ash.read!()
               |> ids()
    end

    test "sorting by the relationship itself is a clean error (not a crash)" do
      assert_raise Ash.Error.Invalid, ~r/tier_record is not sortable/, fn ->
        Subscription
        |> Ash.Query.sort(tier_record: :asc)
        |> Ash.Query.as_of(@jan15)
        |> Ash.read!()
      end
    end
  end

  describe "Ash.load carries as_of (like tenant)" do
    setup do
      # tier 50 changes name across periods; subscription 7 spans both.
      TestRepo.query!("""
      INSERT INTO tier (id, name, valid_at) VALUES
        (50, 'old', tstzrange('2026-01-01','2026-03-01','[)')),
        (50, 'new', tstzrange('2026-03-01','2026-06-01','[)'))
      """)

      TestRepo.query!("""
      INSERT INTO subscription (id, tier, tier_id, valid_at) VALUES
        (7, 'sub7', 50, tstzrange('2026-01-01','2026-06-01','[)'))
      """)

      :ok
    end

    test "loading a temporal relationship reuses the originating read's instant" do
      # Read at @jan15 WITHOUT loading the relationship...
      sub =
        Subscription
        |> Ash.Query.filter(id == 7)
        |> Ash.Query.as_of(@jan15)
        |> Ash.read_one!()

      # ...the read stamped the resolved as_of onto the record.
      assert %DateTime{} = sub.__metadata__.as_of

      # Loading later with NO as_of reuses @jan15 -> 'old'. (A wall-clock `now()` default
      # would land in June 2026, past tier 50's last period, and return nil.)
      loaded = Ash.load!(sub, :tier_record)
      assert loaded.tier_record.name == "old"
    end

    test "an explicit as_of on load overrides the carried instant" do
      sub =
        Subscription
        |> Ash.Query.filter(id == 7)
        |> Ash.Query.as_of(@jan15)
        |> Ash.read_one!()

      loaded = Ash.load!(sub, :tier_record, as_of: @mar1)
      assert loaded.tier_record.name == "new"
    end

    test "a create with an explicit as_of stamps that instant onto the record" do
      # tier_id NULL avoids the PERIOD FK so we can write an open-ended [jan15, ∞) row.
      created =
        Subscription
        |> Ash.Changeset.for_create(:create, %{id: 77, tier: "x"})
        |> Ash.Changeset.as_of(@jan15)
        |> Ash.create!()

      assert created.__metadata__.as_of == @jan15
    end

    test "a default (now) write pins one instant for the period, timestamps, and metadata" do
      before = DateTime.utc_now()

      created =
        Subscription
        |> Ash.Changeset.for_create(:create, %{id: 78, tier: "x"})
        |> Ash.create!()

      # No explicit as_of: a single `now` is pinned for the write, stamped on the record...
      assert %DateTime{} = created.__metadata__.as_of
      assert DateTime.compare(created.__metadata__.as_of, before) in [:eq, :gt]

      # ...and it is the *same* instant as the validity period's lower bound — no skew
      # between core (timestamps) and the data layer (period).
      assert %Ash.Range{lower: lower} = created.valid_at
      assert lower == created.__metadata__.as_of
    end

    test "reload reuses the originating read's instant" do
      sub =
        Subscription
        |> Ash.Query.filter(id == 7)
        |> Ash.Query.as_of(@jan15)
        |> Ash.read_one!()

      # reload without an explicit as_of -> inherits @jan15 from the record metadata,
      # and re-stamps it on the reloaded record.
      reloaded = Ash.reload!(sub)
      assert reloaded.__metadata__.as_of == @jan15
    end
  end

  describe "combination queries on a temporal resource" do
    alias Ash.Query.Combination

    test "legs anchor now() to as_of, project the period, and back-join the right period" do
      # Legs select only [:id, :tier] — omitting valid_at (must still be projected for the
      # temporal `@>` + back-join) and seats (forces the back-join that fetches it).
      sel = [:id, :tier]

      query = fn ->
        Subscription
        |> Ash.Query.combination_of([
          Combination.base(filter: Ash.Expr.expr(id == 999), select: sel),
          Combination.union(
            filter: Ash.Expr.expr(id == 1 and activated_at < now()),
            select: sel
          )
        ])
      end

      # @jan15: now()->jan15, activated_at (feb15) < jan15 is false -> union empty -> [].
      # (Wall-clock now() would let the union match -> [bronze]; that's the #8 regression.)
      assert [] = query.() |> Ash.Query.as_of(@jan15) |> Ash.read!()

      # @mar1: now()->mar1, feb15 < mar1 true -> union returns the gold period. The back-join
      # must fetch *gold's* seats (5), not multiply across periods or pull bronze's 3.
      assert [%{tier: "gold", seats: 5}] = query.() |> Ash.Query.as_of(@mar1) |> Ash.read!()
    end
  end

  describe "FOR PORTION OF preserves an unbounded (NULL) upper" do
    test "updating a current row yields [as_of, ∞) with no 'infinity' upper or junk row" do
      # open-ended "current" row ([2026-01-01, ∞)); tier_id NULL avoids the PERIOD FK
      TestRepo.query!(
        "INSERT INTO subscription (id, tier, tier_id, seats, valid_at) VALUES (20, 'x', NULL, 1, tstzrange('2026-01-01', NULL, '[)'))"
      )

      # An atomic FOR PORTION OF update at @mar1 splits [jan,∞) -> [jan,mar1) + [mar1,∞).
      # Returning the new slice previously crashed (literal 'infinity' upper); now it's NULL.
      updated =
        Subscription
        |> Ash.get!(20, as_of: @jan15)
        |> Ash.Changeset.for_update(:add_seat, %{}, as_of: @mar1)
        |> Ash.update!()

      assert %Ash.Range{upper: nil} = updated.valid_at
      assert updated.seats == 2

      # exactly two contiguous periods, the later one unbounded, and NO [infinity, ) junk row
      rows =
        TestRepo.query!(
          "SELECT upper_inf(valid_at), seats FROM subscription WHERE id = 20 ORDER BY lower(valid_at)"
        ).rows

      assert rows == [[false, 1], [true, 2]]

      assert TestRepo.query!(
               "SELECT count(*) FROM subscription WHERE id = 20 AND lower(valid_at) = 'infinity'"
             ).rows == [[0]]
    end
  end

  describe "Ash.Seed / Ash.Generator with as_of" do
    test "Ash.Seed.seed! derives the period from as_of and stamps it on metadata" do
      rec = Ash.Seed.seed!(Subscription, %{id: 70, tier: "seeded"}, as_of: @jan15)

      assert %Ash.Range{lower: @jan15, upper: nil} = rec.valid_at
      assert rec.__metadata__.as_of == @jan15
    end

    test "Ash.Seed.seed! without as_of defaults the period to the wall clock" do
      rec = Ash.Seed.seed!(Subscription, %{id: 71, tier: "seeded"})

      assert %Ash.Range{lower: %DateTime{}, upper: nil} = rec.valid_at
      refute Map.has_key?(rec.__metadata__, :as_of)
    end

    test "Ash.Generator generates a temporal record at as_of (period not randomly generated)" do
      rec =
        Ash.Generator.seed_generator(
          {Subscription,
           %{
             id: StreamData.constant(72),
             tier: StreamData.constant("g"),
             # leave the PERIOD-FK column unset rather than a random (dangling) id
             tier_id: StreamData.constant(nil)
           }},
          as_of: @jan15
        )
        |> Enum.at(0)
        |> Ash.Generator.generate()

      assert %Ash.Range{lower: @jan15, upper: nil} = rec.valid_at
    end
  end

  describe "as_of :now (no time-travel)" do
    test "reads the rows valid at the current instant" do
      # An open-ended ([2020, ∞)) row that always covers the wall clock.
      # `tier_id` is NULL so it isn't subject to the temporal PERIOD FK.
      TestRepo.query!(
        "INSERT INTO subscription (id, tier, tier_id, valid_at) VALUES (9, 'current', NULL, tstzrange('2020-01-01', NULL, '[)'))"
      )

      assert ["current"] =
               Subscription
               |> Ash.Query.filter(id == 9)
               |> Ash.Query.as_of(:now)
               |> Ash.read!()
               |> tiers()
    end

    test "resolves now() to the wall clock rather than a fixed instant" do
      before = DateTime.utc_now()

      [event] =
        Event
        |> Ash.Query.filter(id == 1)
        |> Ash.Query.as_of(:now)
        |> Ash.Query.load(:now_val)
        |> Ash.read!()

      assert DateTime.compare(event.now_val, before) in [:gt, :eq]
      assert DateTime.diff(DateTime.utc_now(), event.now_val) <= 5
    end
  end

  describe "now() anchoring to as_of (core)" do
    test "anchors now() in a base filter" do
      # created jan-1 < as_of jan-15 -> only early; wall clock would match both
      assert ["early"] =
               Event
               |> Ash.Query.filter(created < now())
               |> Ash.Query.as_of(@jan15)
               |> Ash.read!()
               |> Enum.map(& &1.name)
               |> Enum.sort()
    end

    test "anchors now() inside a calculation" do
      [event] =
        Event
        |> Ash.Query.filter(id == 1)
        |> Ash.Query.as_of(@jan15)
        |> Ash.Query.load([:now_val, :is_past])
        |> Ash.read!()

      assert event.now_val == @jan15
      assert event.is_past == true
    end

    test "anchors ago()/from_now() inside a calculation (as_of, not the wall clock)" do
      load = [:within_a_year, :within_next_year]

      at = fn as_of ->
        Event
        |> Ash.Query.filter(id == 1)
        |> Ash.Query.as_of(as_of)
        |> Ash.Query.load(load)
        |> Ash.read_one!()
      end

      # event 1 created 2026-01-01
      assert %{within_a_year: true, within_next_year: true} = at.(@jan15)

      # `ago(1, :year)` anchored: as of 2027-06, created is >1yr old -> false.
      # (At the wall clock it would still be within the last year -> true.)
      assert %{within_a_year: false} = at.(~U[2027-06-01 00:00:00.000000Z])

      # `from_now(1, :year)` anchored: as of 2023-06, created is >1yr ahead -> false.
      # (At the wall clock it would be within the next year -> true.)
      assert %{within_next_year: false} = at.(~U[2023-06-01 00:00:00.000000Z])
    end

    test "anchors now() in an atomic update to the changeset as_of" do
      [event] = Event |> Ash.Query.filter(id == 1) |> Ash.read!()

      updated =
        event
        |> Ash.Changeset.for_update(:touch)
        |> Ash.Changeset.as_of(@jan15)
        |> Ash.update!()

      # anchored to jan-15, not the wall clock (june)
      assert DateTime.to_date(updated.created) == ~D[2026-01-15]
    end
  end

  describe "Ash.Type.Range <-> Postgrex.Range bridge" do
    test "create derives valid_at from as_of and round-trips it as an Ash.Range" do
      # `valid_at` is not an input — a temporal create writes `[as_of, ∞)`.
      created =
        Subscription
        |> Ash.Changeset.for_create(:create, %{id: 2, tier: "diamond"})
        |> Ash.Changeset.as_of(@jan15)
        |> Ash.create!()

      assert %Ash.Range{lower: @jan15, upper: nil, bounds: :"[)"} = created.valid_at

      [loaded] =
        Subscription
        |> Ash.Query.filter(id == 2)
        |> Ash.Query.as_of(@mar1)
        |> Ash.Query.select([:id, :valid_at])
        |> Ash.read!()

      assert %Ash.Range{lower: @jan15, upper: nil} = loaded.valid_at
    end
  end

  describe "FOR PORTION OF mutations" do
    test "update splits the row at as_of, applying the new value forward" do
      [gold] = Subscription |> Ash.Query.filter(id == 1) |> Ash.Query.as_of(@mar1) |> Ash.read!()

      updated =
        gold
        |> Ash.Changeset.for_update(:change_tier, %{tier: "platinum"})
        |> Ash.Changeset.as_of(@mar1)
        |> Ash.update!()

      # the returned record reflects the affected slice, not the pre-split range
      assert updated.tier == "platinum"

      assert %Ash.Range{lower: @mar1, upper: ~U[2026-04-01 00:00:00.000000Z]} =
               updated.valid_at

      assert [
               ["bronze", ~U[2026-01-01 00:00:00.000000Z], ~U[2026-02-01 00:00:00.000000Z]],
               ["gold", ~U[2026-02-01 00:00:00.000000Z], ~U[2026-03-01 00:00:00.000000Z]],
               ["platinum", ~U[2026-03-01 00:00:00.000000Z], ~U[2026-04-01 00:00:00.000000Z]]
             ] = subscription_timeline(1)
    end

    test "a non-atomic update also splits at as_of (single-row update/2 path)" do
      [gold] = Subscription |> Ash.Query.filter(id == 1) |> Ash.Query.as_of(@mar1) |> Ash.read!()

      gold
      |> Ash.Changeset.for_update(:change_tier_nonatomic, %{tier: "renamed"})
      |> Ash.Changeset.as_of(@mar1)
      |> Ash.update!()

      assert [
               ["bronze", ~U[2026-01-01 00:00:00.000000Z], ~U[2026-02-01 00:00:00.000000Z]],
               ["gold", ~U[2026-02-01 00:00:00.000000Z], ~U[2026-03-01 00:00:00.000000Z]],
               ["renamed", ~U[2026-03-01 00:00:00.000000Z], ~U[2026-04-01 00:00:00.000000Z]]
             ] = subscription_timeline(1)
    end

    test "destroy ends validity from as_of forward, preserving prior history" do
      [gold] = Subscription |> Ash.Query.filter(id == 1) |> Ash.Query.as_of(@mar1) |> Ash.read!()

      gold
      |> Ash.Changeset.for_destroy(:expire)
      |> Ash.Changeset.as_of(@mar1)
      |> Ash.destroy!()

      # bronze untouched; gold [Feb,Apr) truncated to [Feb,Mar)
      assert [
               ["bronze", ~U[2026-01-01 00:00:00.000000Z], ~U[2026-02-01 00:00:00.000000Z]],
               ["gold", ~U[2026-02-01 00:00:00.000000Z], ~U[2026-03-01 00:00:00.000000Z]]
             ] = subscription_timeline(1)
    end
  end

  describe "range_overlaps/2" do
    test "renders the && operator and filters by overlap" do
      probe = %Ash.Range{lower: @jan15, upper: ~U[2026-01-20 00:00:00.000000Z], bounds: :"[)"}

      assert ["bronze"] =
               Subscription
               |> Ash.Query.filter(id == 1 and range_overlaps(valid_at, ^probe))
               |> Ash.Query.as_of(@jan15)
               |> Ash.read!()
               |> tiers()
    end
  end

  describe "temporal relationships (temporal_keys)" do
    test "loading a temporal has_many at as_of overlaps periods and narrows to as_of" do
      [tier] =
        Tier
        |> Ash.Query.filter(id == 10)
        |> Ash.Query.as_of(@jan15)
        |> Ash.Query.load(:subscriptions)
        |> Ash.read!()

      assert ["bronze"] = tiers(tier.subscriptions)
    end
  end

  describe "atomics" do
    test "an atomic arithmetic update applies only to the affected slice" do
      [gold] = Subscription |> Ash.Query.filter(id == 1) |> Ash.Query.as_of(@mar1) |> Ash.read!()

      gold
      |> Ash.Changeset.for_update(:add_seat)
      |> Ash.Changeset.as_of(@mar1)
      |> Ash.update!()

      # gold [Feb,Apr) seats=5 split at mar-1: leftover [Feb,Mar) keeps 5, slice [Mar,Apr) -> 6
      assert [
               ["bronze", 3, ~U[2026-01-01 00:00:00.000000Z]],
               ["gold", 5, ~U[2026-02-01 00:00:00.000000Z]],
               ["gold", 6, ~U[2026-03-01 00:00:00.000000Z]]
             ] = seats_timeline(1)
    end
  end

  describe "validations anchored to as_of" do
    # A module-backed validation whose atomic condition uses now(): the now() is
    # anchored to the changeset's as_of (atomic condition rendered via the data
    # layer; eager path reads changeset.as_of).
    test "a now()-based atomic validation is evaluated at the changeset as_of" do
      # activated_at = feb-15 on every period.
      # as_of mar-1: feb-15 < now()(=mar-1) -> passes
      [gold] = Subscription |> Ash.Query.filter(id == 1) |> Ash.Query.as_of(@mar1) |> Ash.read!()

      assert {:ok, _} =
               gold
               |> Ash.Changeset.for_update(:validated_touch)
               |> Ash.Changeset.as_of(@mar1)
               |> Ash.update()

      # as_of jan-15: feb-15 < now()(=jan-15) is FALSE -> fails. (Wall-clock now would pass.)
      [bronze] =
        Subscription |> Ash.Query.filter(id == 1) |> Ash.Query.as_of(@jan15) |> Ash.read!()

      assert {:error, %Ash.Error.Invalid{}} =
               bronze
               |> Ash.Changeset.for_update(:validated_touch)
               |> Ash.Changeset.as_of(@jan15)
               |> Ash.update()
    end
  end

  describe "aggregates respect as_of" do
    test "a count over a temporal has_many counts only periods valid at as_of" do
      # add a second subscription (id=3) for tier 10, valid only [Mar,May)
      TestRepo.query!("""
      INSERT INTO subscription (id, tier, tier_id, seats, valid_at) VALUES
        (3, 'silver', 10, 1, tstzrange('2026-03-01','2026-05-01','[)'))
      """)

      count_at = fn as_of ->
        [tier] =
          Tier
          |> Ash.Query.filter(id == 10)
          |> Ash.Query.as_of(as_of)
          |> Ash.Query.load(:subscription_count)
          |> Ash.read!()

        tier.subscription_count
      end

      # jan-15: only id=1 bronze valid -> 1
      assert count_at.(@jan15) == 1
      # mar-15: id=1 gold + id=3 silver valid -> 2
      assert count_at.(~U[2026-03-15 00:00:00.000000Z]) == 2
    end
  end

  describe "bulk_create" do
    test "distinct keys succeed; same key at the same as_of raises the exclusion constraint" do
      # open-ended tier so each create's `[as_of, ∞)` satisfies the PERIOD FK
      TestRepo.query!(
        "INSERT INTO tier (id, name, valid_at) VALUES (20, 'open', tstzrange('2026-01-01', NULL, '[)'))"
      )

      # Each create writes `[as_of, ∞)`; distinct ids don't overlap.
      ok =
        Ash.bulk_create!(
          [%{id: 5, tier: "a", tier_id: 20}, %{id: 6, tier: "b", tier_id: 20}],
          Subscription,
          :create,
          as_of: @jan15,
          return_records?: true
        )

      assert length(ok.records) == 2

      # Two rows for the same id at the same as_of both want `[jan15, ∞)` -> overlap.
      overlapping =
        Ash.bulk_create(
          [%{id: 7, tier: "a", tier_id: 20}, %{id: 7, tier: "b", tier_id: 20}],
          Subscription,
          :create,
          as_of: @jan15,
          return_errors?: true,
          stop_on_error?: false
        )

      assert overlapping.error_count > 0
    end
  end

  describe "overlapping periods" do
    test "an overlapping create returns a clear error on the period field" do
      # id=1 already has bronze [jan,feb); creating it again at jan15 wants
      # `[jan15, ∞)`, which overlaps the existing period.
      assert {:error, %Ash.Error.Invalid{} = error} =
               Subscription
               |> Ash.Changeset.for_create(:create, %{id: 1, tier: "dup", tier_id: 10})
               |> Ash.Changeset.as_of(@jan15)
               |> Ash.create()

      assert Enum.any?(error.errors, fn
               %Ash.Error.Changes.InvalidAttribute{field: :valid_at, message: message} ->
                 message =~ "overlaps"

               _ ->
                 false
             end)
    end
  end

  describe "temporal upsert (atomic FOR-PORTION-OF-or-insert CTE)" do
    test "match: splits the period valid at as_of, applying new values forward" do
      # id=1: bronze [jan,feb), gold [feb,apr). Upsert at mar1 (inside gold).
      assert {:ok, result} =
               Subscription
               |> Ash.Changeset.for_create(:create, %{
                 id: 1,
                 tier: "platinum",
                 tier_id: 10,
                 seats: 9
               })
               |> Ash.Changeset.as_of(@mar1)
               |> Ash.create(upsert?: true)

      assert result.tier == "platinum"

      # gold truncated to [feb,mar); platinum [mar,apr) carries the new values; bronze intact.
      assert [["bronze", _, _], ["gold", 5, _], ["platinum", 9, _]] = seats_timeline(1)
    end

    test "match: future periods (that don't contain as_of) are untouched" do
      TestRepo.query!(
        "INSERT INTO subscription (id, tier, tier_id, seats, valid_at) VALUES (1,'future',10,1,tstzrange('2026-05-01','2026-06-01','[)'))"
      )

      assert {:ok, _} =
               Subscription
               |> Ash.Changeset.for_create(:create, %{
                 id: 1,
                 tier: "platinum",
                 tier_id: 10,
                 seats: 9
               })
               |> Ash.Changeset.as_of(@mar1)
               |> Ash.create(upsert?: true)

      assert [["future", 1]] =
               TestRepo.query!(
                 "SELECT tier, seats FROM subscription WHERE id=1 AND lower(valid_at)='2026-05-01'"
               ).rows
    end

    test "no match: inserts a new period gap-filled to infinity" do
      TestRepo.query!(
        "INSERT INTO tier (id, name, valid_at) VALUES (20, 'open', tstzrange('2026-01-01', NULL, '[)'))"
      )

      assert {:ok, result} =
               Subscription
               |> Ash.Changeset.for_create(:create, %{id: 2, tier: "new", tier_id: 20, seats: 1})
               |> Ash.Changeset.as_of(@jan15)
               |> Ash.create(upsert?: true)

      assert result.tier == "new"

      assert [["new", "2026-01-15 00:00:00+00", nil]] =
               TestRepo.query!(
                 "SELECT tier, lower(valid_at)::text, upper(valid_at) FROM subscription WHERE id=2"
               ).rows
    end

    test "bulk: upserts many keys in one statement (match splits, miss inserts)" do
      # open-ended tier so the new id=5 row's [mar1, ∞) satisfies the PERIOD FK
      TestRepo.query!(
        "INSERT INTO tier (id, name, valid_at) VALUES (20, 'open', tstzrange('2026-01-01', NULL, '[)'))"
      )

      # id=1 exists (bronze/gold). id=5 is new. Upsert both at mar1, one statement.
      assert %Ash.BulkResult{status: :success} =
               Ash.bulk_create!(
                 [
                   %{id: 1, tier: "platinum", tier_id: 10, seats: 9},
                   %{id: 5, tier: "fresh", tier_id: 20, seats: 2}
                 ],
                 Subscription,
                 :create,
                 upsert?: true,
                 upsert_fields: [:tier, :tier_id, :seats],
                 as_of: @mar1,
                 return_errors?: true
               )

      # id=1 gold split at mar1 -> platinum forward; id=5 inserted from mar1.
      assert [["bronze", _, _], ["gold", 5, _], ["platinum", 9, _]] = seats_timeline(1)
      assert [["fresh", 2, ~U[2026-03-01 00:00:00.000000Z]]] = seats_timeline(5)
    end
  end

  describe "bulk_update / update_many" do
    # The `FOR PORTION OF FROM` bound is sourced from the query context as_of
    # (via `temporal_from_bound`), which carries it for both single and bulk.
    test "each matched row is split at as_of (FOR PORTION OF, set-wide)" do
      Subscription
      |> Ash.Query.filter(id == 1)
      |> Ash.Query.as_of(@mar1)
      |> Ash.bulk_update!(:add_seat, %{}, strategy: :atomic)

      # gold valid at mar-1 split; bronze untouched
      assert [
               ["bronze", 3, ~U[2026-01-01 00:00:00.000000Z]],
               ["gold", 5, ~U[2026-02-01 00:00:00.000000Z]],
               ["gold", 6, ~U[2026-03-01 00:00:00.000000Z]]
             ] = seats_timeline(1)
    end
  end

  describe "bulk_destroy" do
    # FROM bound sourced from query context as_of (via `temporal_from_bound`).
    test "each matched row's validity is truncated at as_of (FOR PORTION OF DELETE)" do
      Subscription
      |> Ash.Query.filter(id == 1)
      |> Ash.Query.as_of(@mar1)
      |> Ash.bulk_destroy!(:expire, %{}, strategy: :atomic)

      assert [
               ["bronze", ~U[2026-01-01 00:00:00.000000Z], ~U[2026-02-01 00:00:00.000000Z]],
               ["gold", ~U[2026-02-01 00:00:00.000000Z], ~U[2026-03-01 00:00:00.000000Z]]
             ] = subscription_timeline(1)
    end
  end

  describe "temporal PERIOD foreign keys reject referential actions" do
    test "on_delete on a temporal relationship fails to compile (PG19: NO ACTION only)" do
      assert_raise Spark.Error.DslError, ~r/PERIOD|NO ACTION/, fn ->
        defmodule BadTemporalRef do
          use Ash.Resource,
            domain: nil,
            validate_domain_inclusion?: false,
            data_layer: AshPostgres.DataLayer

          postgres do
            table("bad_temporal_ref")
            repo(AshPostgres.TestRepo)

            references do
              reference(:tier_record, on_delete: :delete)
            end
          end

          temporal do
            strategy(:context)
            attribute(:valid_at)
          end

          attributes do
            attribute(:id, :integer, primary_key?: true, allow_nil?: false, public?: true)
            attribute(:tier_id, :integer, public?: true)

            attribute(:valid_at, Ash.Type.Range,
              constraints: [inner_type: :datetime],
              public?: true
            )
          end

          relationships do
            belongs_to :tier_record, AshPostgres.Test.Temporal.Tier do
              source_attribute(:tier_id)
              destination_attribute(:id)
              define_attribute?(false)
              attribute_type(:integer)
              temporal_keys({:valid_at, :valid_at})
            end
          end
        end
      end
    end
  end

  describe "the period attribute is not settable as input" do
    test "a resource that accepts the temporal attribute fails to compile" do
      assert_raise Spark.Error.DslError, ~r/must not be accepted as input/, fn ->
        defmodule BadTemporal do
          use Ash.Resource,
            domain: nil,
            validate_domain_inclusion?: false,
            data_layer: AshPostgres.DataLayer

          postgres do
            table("bad_temporal")
            repo(AshPostgres.TestRepo)
          end

          temporal do
            strategy(:context)
            attribute(:valid_at)
          end

          attributes do
            attribute(:id, :integer, primary_key?: true, allow_nil?: false, public?: true)

            attribute(:valid_at, Ash.Type.Range,
              constraints: [inner_type: :datetime],
              public?: true
            )
          end

          actions do
            defaults(create: [:id, :valid_at])
          end
        end
      end
    end
  end

  describe "cascade destroy threads as_of to children (child-first ordering)" do
    test "cascading a destroy at an as_of ends the children's validity at that instant" do
      # tier 10 [jan,jun); id=1 subs: bronze [jan,feb), gold [feb,apr)
      [tier] = Tier |> Ash.Query.filter(id == 10) |> Ash.Query.as_of(@mar1) |> Ash.read!()

      # as_of via the action opt so it's set before the cascade change captures context
      tier
      |> Ash.Changeset.for_destroy(:archive, %{}, as_of: @mar1)
      |> Ash.destroy!()

      # the period valid at mar1 (gold) is truncated to end at mar1; bronze intact
      assert [
               ["bronze", ~U[2026-01-01 00:00:00.000000Z], ~U[2026-02-01 00:00:00.000000Z]],
               ["gold", ~U[2026-02-01 00:00:00.000000Z], ~U[2026-03-01 00:00:00.000000Z]]
             ] = subscription_timeline(1)

      # and the tier itself ended at mar1
      assert [["2026-01-01 00:00:00+00", "2026-03-01 00:00:00+00"]] =
               TestRepo.query!(
                 "SELECT lower(valid_at)::text, upper(valid_at)::text FROM tier WHERE id = 10"
               ).rows
    end
  end

  describe "manage_relationship threads as_of to managed children" do
    test "a managed child is created at the parent's as_of, not now" do
      assert {:ok, _sub} =
               Subscription
               |> Ash.Changeset.for_create(:create_with_tier, %{
                 id: 30,
                 tier: "managed",
                 seats: 1,
                 new_tier: %{id: 30, name: "mtier"}
               })
               |> Ash.Changeset.as_of(@jan15)
               |> Ash.create()

      # The managed tier must have been written at jan-15 — its [jan15, ∞) has to cover
      # the subscription's [jan15, ∞) (the temporal PERIOD FK requires it). A child written
      # at "now" would be [now, ∞) and fail the FK / show the wrong lower bound.
      assert [["2026-01-15 00:00:00+00", nil]] =
               TestRepo.query!(
                 "SELECT lower(valid_at)::text, upper(valid_at) FROM tier WHERE id = 30"
               ).rows
    end
  end
end
