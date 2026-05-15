# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.EmbeddedArrayExistsTest do
  @moduledoc """
  Phase 2 (SPIKE / CRITICAL) — verifies `exists/2` over `{:array, EmbeddedResource}`
  attributes is translated to correct PostgreSQL SQL via `jsonb_array_elements`.

  See `../ash/specs/embedded-array-exists.md`.
  """
  use AshPostgres.RepoCase, async: false

  require Ash.Query

  alias AshPostgres.Test.EmbeddedArray.Estimate

  setup do
    cheap =
      Estimate
      |> Ash.Changeset.for_create(:create, %{
        title: "cheap",
        options: [
          %{
            name: "basic",
            total_amt: Decimal.new("50"),
            quantity: 1,
            active: true,
            tier: :basic,
            valid_until: ~U[2026-12-31 23:59:59Z]
          }
        ]
      })
      |> Ash.create!()

    expensive =
      Estimate
      |> Ash.Changeset.for_create(:create, %{
        title: "expensive",
        options: [
          %{
            name: "premium",
            total_amt: Decimal.new("150"),
            quantity: 10,
            active: true,
            tier: :premium,
            valid_until: ~U[2027-06-30 23:59:59Z]
          }
        ]
      })
      |> Ash.create!()

    mixed =
      Estimate
      |> Ash.Changeset.for_create(:create, %{
        title: "mixed",
        options: [
          %{name: "a", total_amt: Decimal.new("10"), tier: :basic, active: false},
          %{name: "b", total_amt: Decimal.new("200"), tier: :enterprise, active: true}
        ]
      })
      |> Ash.create!()

    %{cheap: cheap, expensive: expensive, mixed: mixed}
  end

  describe "exists/2 over embedded array, cast coverage by attribute type" do
    test ":decimal — total_amt > 100", %{cheap: cheap, expensive: expensive, mixed: mixed} do
      results =
        Estimate
        |> Ash.Query.filter(exists(options, total_amt > 100))
        |> Ash.read!()
        |> Enum.map(& &1.id)

      assert expensive.id in results
      assert mixed.id in results
      refute cheap.id in results
    end

    test ":string — name == \"basic\"", %{cheap: cheap, expensive: expensive} do
      results =
        Estimate
        |> Ash.Query.filter(exists(options, name == "basic"))
        |> Ash.read!()
        |> Enum.map(& &1.id)

      assert cheap.id in results
      refute expensive.id in results
    end

    test ":integer — quantity > 5", %{cheap: cheap, expensive: expensive} do
      results =
        Estimate
        |> Ash.Query.filter(exists(options, quantity > 5))
        |> Ash.read!()
        |> Enum.map(& &1.id)

      assert expensive.id in results
      refute cheap.id in results
    end

    test ":boolean — active == false", %{cheap: cheap, mixed: mixed} do
      results =
        Estimate
        |> Ash.Query.filter(exists(options, active == false))
        |> Ash.read!()
        |> Enum.map(& &1.id)

      assert mixed.id in results
      refute cheap.id in results
    end

    test ":atom — tier == :premium", %{expensive: expensive, cheap: cheap} do
      results =
        Estimate
        |> Ash.Query.filter(exists(options, tier == :premium))
        |> Ash.read!()
        |> Enum.map(& &1.id)

      assert expensive.id in results
      refute cheap.id in results
    end

    test ":utc_datetime — valid_until > ~U[2027-01-01 00:00:00Z]", %{
      expensive: expensive,
      cheap: cheap
    } do
      cutoff = ~U[2027-01-01 00:00:00Z]

      results =
        Estimate
        |> Ash.Query.filter(exists(options, valid_until > ^cutoff))
        |> Ash.read!()
        |> Enum.map(& &1.id)

      assert expensive.id in results
      refute cheap.id in results
    end
  end

  describe "exists/2 composition" do
    test "and/or with outer predicates", %{expensive: expensive, mixed: mixed} do
      results =
        Estimate
        |> Ash.Query.filter(active == true and exists(options, total_amt > 100))
        |> Ash.read!()
        |> Enum.map(& &1.id)

      assert expensive.id in results
      assert mixed.id in results
    end

    test "not exists", %{cheap: cheap, expensive: expensive} do
      results =
        Estimate
        |> Ash.Query.filter(not exists(options, total_amt > 100))
        |> Ash.read!()
        |> Enum.map(& &1.id)

      assert cheap.id in results
      refute expensive.id in results
    end

    test "parameter interpolation via ^", %{expensive: expensive} do
      threshold = Decimal.new("100")

      results =
        Estimate
        |> Ash.Query.filter(exists(options, total_amt > ^threshold))
        |> Ash.read!()
        |> Enum.map(& &1.id)

      assert expensive.id in results
    end
  end
end
