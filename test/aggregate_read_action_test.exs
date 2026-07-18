# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.AggregateReadActionTest do
  @moduledoc """
  Regression tests for aggregate `read_action` handling in ash_sql.

  `Ticket`'s primary read hides `:draft` rows via a preparation; aggregates
  pointing `read_action: :read_all` at the unfiltered action must bypass that
  preparation on every SQL path: aggregates over a single relationship, over a
  many-to-many relationship, over a relationship path with multiple
  relationships (where the read action applies to the last relationship in the
  path), and `:first` aggregates that would otherwise take the optimized
  left-join path.

  The resources are local to this test (backed by the hand-written
  20260716200000_add_read_action_aggregate_tables migration) rather than
  registered in AshPostgres.Test.Domain.
  """

  use AshPostgres.RepoCase, async: false

  require Ash.Query
  require Ash.Sort
  import Ash.Expr

  defmodule Domain do
    use Ash.Domain

    resources do
      allow_unregistered?(true)
    end
  end

  defmodule Ticket do
    @moduledoc false
    use Ash.Resource,
      domain: AshPostgres.AggregateReadActionTest.Domain,
      data_layer: AshPostgres.DataLayer,
      primary_read_warning?: false

    postgres do
      table("read_action_tickets")
      repo(AshPostgres.TestRepo)
    end

    actions do
      default_accept(:*)
      defaults([:create])

      read :read do
        primary?(true)
        prepare(build(filter: expr(status != :draft)))
      end

      read(:read_all)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, public?: true)

      attribute(:status, :atom,
        public?: true,
        allow_nil?: false,
        default: :open,
        constraints: [one_of: [:draft, :open]]
      )
    end

    relationships do
      belongs_to(:ticket_list, AshPostgres.AggregateReadActionTest.TicketList, public?: true)
    end
  end

  defmodule TicketList do
    @moduledoc false
    use Ash.Resource,
      domain: AshPostgres.AggregateReadActionTest.Domain,
      data_layer: AshPostgres.DataLayer

    postgres do
      table("read_action_ticket_lists")
      repo(AshPostgres.TestRepo)
    end

    actions do
      default_accept(:*)
      defaults([:create, :read])
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:name, :string, public?: true)
    end

    relationships do
      belongs_to(:ticket_folder, AshPostgres.AggregateReadActionTest.TicketFolder, public?: true)

      has_many(:tickets, AshPostgres.AggregateReadActionTest.Ticket, public?: true)
    end

    calculations do
      calculate(:ticket_count_default, :integer, expr(count(tickets)))

      calculate(:ticket_count_all, :integer, expr(count(tickets, read_action: :read_all)))

      calculate(
        :draft_count_all,
        :integer,
        expr(count(tickets, read_action: :read_all, query: [filter: expr(status == :draft)]))
      )
    end
  end

  defmodule TicketShare do
    @moduledoc false
    use Ash.Resource,
      domain: AshPostgres.AggregateReadActionTest.Domain,
      data_layer: AshPostgres.DataLayer

    postgres do
      table("read_action_ticket_shares")
      repo(AshPostgres.TestRepo)
    end

    actions do
      default_accept(:*)
      defaults([:create, :read])
    end

    attributes do
      uuid_primary_key(:id)
    end

    relationships do
      belongs_to(:ticket_folder, AshPostgres.AggregateReadActionTest.TicketFolder,
        public?: true,
        allow_nil?: false
      )

      belongs_to(:ticket, AshPostgres.AggregateReadActionTest.Ticket,
        public?: true,
        allow_nil?: false
      )
    end
  end

  defmodule TicketFolder do
    @moduledoc false
    use Ash.Resource,
      domain: AshPostgres.AggregateReadActionTest.Domain,
      data_layer: AshPostgres.DataLayer

    postgres do
      table("read_action_ticket_folders")
      repo(AshPostgres.TestRepo)
    end

    actions do
      default_accept(:*)
      defaults([:create, :read])
    end

    attributes do
      uuid_primary_key(:id)
    end

    relationships do
      has_many(:ticket_lists, AshPostgres.AggregateReadActionTest.TicketList, public?: true)

      many_to_many :shared_tickets, AshPostgres.AggregateReadActionTest.Ticket do
        through(AshPostgres.AggregateReadActionTest.TicketShare)
        source_attribute_on_join_resource(:ticket_folder_id)
        destination_attribute_on_join_resource(:ticket_id)
        public?(true)
      end
    end

    calculations do
      calculate(
        :deep_ticket_count_default,
        :integer,
        expr(count(ticket_lists.tickets))
      )

      calculate(
        :deep_ticket_count_all,
        :integer,
        expr(count(ticket_lists.tickets, read_action: :read_all))
      )

      calculate(:shared_ticket_count_default, :integer, expr(count(shared_tickets)))

      calculate(
        :shared_ticket_count_all,
        :integer,
        expr(count(shared_tickets, read_action: :read_all))
      )
    end
  end

  defmodule TicketNote do
    @moduledoc false
    use Ash.Resource,
      domain: AshPostgres.AggregateReadActionTest.Domain,
      data_layer: AshPostgres.DataLayer

    postgres do
      table("read_action_ticket_notes")
      repo(AshPostgres.TestRepo)
    end

    actions do
      default_accept(:*)
      defaults([:create, :read])
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:body, :string, public?: true)
    end

    relationships do
      belongs_to(:ticket, AshPostgres.AggregateReadActionTest.Ticket, public?: true)
    end

    calculations do
      calculate(:ticket_title_default, :string, expr(first(ticket, field: :title)))

      calculate(
        :ticket_title_all,
        :string,
        expr(first(ticket, field: :title, read_action: :read_all))
      )
    end
  end

  setup do
    folder = Ash.Seed.seed!(TicketFolder, %{})
    list = Ash.Seed.seed!(TicketList, %{name: "a list", ticket_folder_id: folder.id})

    open =
      Ash.Seed.seed!(Ticket, %{title: "open ticket", status: :open, ticket_list_id: list.id})

    draft =
      Ash.Seed.seed!(Ticket, %{title: "draft ticket", status: :draft, ticket_list_id: list.id})

    Ash.Seed.seed!(TicketShare, %{ticket_folder_id: folder.id, ticket_id: open.id})
    Ash.Seed.seed!(TicketShare, %{ticket_folder_id: folder.id, ticket_id: draft.id})

    %{folder: folder, list: list, open: open, draft: draft}
  end

  describe "aggregates over a single relationship" do
    test "count without read_action keeps primary read preparations", %{list: list} do
      assert %{ticket_count_default: 1} =
               Ash.load!(list, :ticket_count_default)
    end

    test "count with read_action bypasses primary read preparations", %{list: list} do
      assert %{ticket_count_all: 2} = Ash.load!(list, :ticket_count_all)
    end

    test "count with read_action and filter can count prepare-hidden rows", %{list: list} do
      assert %{draft_count_all: 1} = Ash.load!(list, :draft_count_all)
    end
  end

  describe "aggregates over a many-to-many relationship" do
    test "count without read_action keeps primary read preparations", %{folder: folder} do
      assert %{shared_ticket_count_default: 1} =
               Ash.load!(folder, :shared_ticket_count_default)
    end

    test "count with read_action bypasses primary read preparations", %{folder: folder} do
      assert %{shared_ticket_count_all: 2} = Ash.load!(folder, :shared_ticket_count_all)
    end
  end

  describe "aggregates over a relationship path with multiple relationships" do
    test "count without read_action keeps primary read preparations", %{folder: folder} do
      assert %{deep_ticket_count_default: 1} = Ash.load!(folder, :deep_ticket_count_default)
    end

    test "count with read_action bypasses primary read preparations on the last relationship",
         %{
           folder: folder
         } do
      assert %{deep_ticket_count_all: 2} = Ash.load!(folder, :deep_ticket_count_all)
    end
  end

  describe "optimized first aggregates" do
    setup %{draft: draft} do
      %{note: Ash.Seed.seed!(TicketNote, %{body: "note on draft", ticket_id: draft.id})}
    end

    test "first without read_action keeps primary read preparations", %{note: note} do
      assert %{ticket_title_default: nil} = Ash.load!(note, :ticket_title_default)
    end

    test "first with read_action bypasses primary read preparations", %{note: note} do
      assert %{ticket_title_all: "draft ticket"} = Ash.load!(note, :ticket_title_all)
    end

    test "sibling default and read_action first aggregates keep distinct values", %{note: note} do
      assert %{ticket_title_default: nil, ticket_title_all: "draft ticket"} =
               Ash.load!(note, [:ticket_title_default, :ticket_title_all])
    end

    test "read_action first aggregate survives an outer query joining the same path", %{
      note: note
    } do
      assert [%{ticket_title_all: "draft ticket"}] =
               TicketNote
               |> Ash.Query.filter(id == ^note.id)
               |> Ash.Query.sort([{Ash.Sort.expr_sort(ticket.title, :string), :asc_nils_last}])
               |> Ash.Query.load(:ticket_title_all)
               |> Ash.read!()
    end
  end
end
