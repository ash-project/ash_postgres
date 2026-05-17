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

  describe "Phase 3 — nested exists/2 over embedded arrays" do
    setup do
      with_tea =
        Estimate
        |> Ash.Changeset.for_create(:create, %{
          title: "drinks",
          options: [
            %{
              name: "tea-bundle",
              total_amt: Decimal.new("30"),
              tier: :basic,
              line_items: [
                %{name: "tea", quantity: 1, unit_price: Decimal.new("3")},
                %{name: "biscuit", quantity: 2, unit_price: Decimal.new("2")}
              ]
            }
          ]
        })
        |> Ash.create!()

      with_coffee =
        Estimate
        |> Ash.Changeset.for_create(:create, %{
          title: "drinks",
          options: [
            %{
              name: "coffee-bundle",
              total_amt: Decimal.new("80"),
              tier: :premium,
              line_items: [
                %{name: "coffee", quantity: 1, unit_price: Decimal.new("4")},
                %{name: "muffin", quantity: 1, unit_price: Decimal.new("5")}
              ]
            }
          ]
        })
        |> Ash.create!()

      %{with_tea: with_tea, with_coffee: with_coffee}
    end

    test "dotted nested path: exists(options.line_items, name == \"tea\")",
         %{with_tea: tea, with_coffee: coffee} do
      results =
        Estimate
        |> Ash.Query.filter(exists(options.line_items, name == "tea"))
        |> Ash.read!()
        |> Enum.map(& &1.id)

      assert tea.id in results
      refute coffee.id in results
    end

    test "innermost predicate combines fields of innermost element", %{with_coffee: coffee} do
      results =
        Estimate
        |> Ash.Query.filter(exists(options.line_items, name == "muffin" and quantity == 1))
        |> Ash.read!()
        |> Enum.map(& &1.id)

      assert coffee.id in results
    end

    test "explicit nested form auto-flattens to dotted form", %{with_tea: tea, with_coffee: coffee} do
      results =
        Estimate
        |> Ash.Query.filter(exists(options, exists(line_items, name == "tea")))
        |> Ash.read!()
        |> Enum.map(& &1.id)

      assert tea.id in results
      refute coffee.id in results
    end

    test "parent(...) reaches the calling Estimate scope", %{with_tea: tea, with_coffee: coffee} do
      # Both rows have title "drinks" — only tea has a line item named "tea".
      results =
        Estimate
        |> Ash.Query.filter(
          exists(options.line_items, name == "tea" and parent(title) == "drinks")
        )
        |> Ash.read!()
        |> Enum.map(& &1.id)

      assert tea.id in results
      refute coffee.id in results
    end
  end

  describe "Phase 4 — mixed paths (relationship → embedded array)" do
    alias AshPostgres.Test.EmbeddedArray.Company

    setup do
      cheap_company =
        Company
        |> Ash.Changeset.for_create(:create, %{name: "CheapCo"})
        |> Ash.create!()

      pricey_company =
        Company
        |> Ash.Changeset.for_create(:create, %{name: "PriceyCo"})
        |> Ash.create!()

      Estimate
      |> Ash.Changeset.for_create(:create, %{
        title: "for cheap",
        company_id: cheap_company.id,
        options: [%{name: "basic", total_amt: Decimal.new("50")}]
      })
      |> Ash.create!()

      Estimate
      |> Ash.Changeset.for_create(:create, %{
        title: "for pricey",
        company_id: pricey_company.id,
        options: [%{name: "premium", total_amt: Decimal.new("150")}]
      })
      |> Ash.create!()

      %{cheap_company: cheap_company, pricey_company: pricey_company}
    end

    test "exists(estimates.options, total_amt > 100) on Company", %{
      cheap_company: cheap,
      pricey_company: pricey
    } do
      results =
        Company
        |> Ash.Query.filter(exists(estimates.options, total_amt > 100))
        |> Ash.read!()
        |> Enum.map(& &1.id)

      assert pricey.id in results
      refute cheap.id in results
    end

    test "string equality through mixed path", %{cheap_company: cheap, pricey_company: pricey} do
      results =
        Company
        |> Ash.Query.filter(exists(estimates.options, name == "basic"))
        |> Ash.read!()
        |> Enum.map(& &1.id)

      assert cheap.id in results
      refute pricey.id in results
    end

    test "parent(...) reaches the calling Company scope", %{pricey_company: pricey} do
      results =
        Company
        |> Ash.Query.filter(
          exists(estimates.options, total_amt > 100 and parent(name) == "PriceyCo")
        )
        |> Ash.read!()
        |> Enum.map(& &1.id)

      assert pricey.id in results
    end
  end
end
