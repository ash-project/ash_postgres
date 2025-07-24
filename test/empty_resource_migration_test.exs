defmodule TestEmptyResourceMigration do
  use ExUnit.Case, async: true

  defp resource_has_meaningful_content?(snapshot) do
    [
      snapshot.attributes,
      snapshot.identities,
      snapshot.custom_indexes,
      snapshot.custom_statements,
      snapshot.check_constraints
    ]
    |> Enum.any?(&Enum.any?/1)
  end

  defp simulate_do_fetch_operations(snapshot, _prev_snapshot, _opts, acc) do
    if resource_has_meaningful_content?(snapshot) do
      [:create_table_operation | acc]
    else
      acc
    end
  end

  describe "simulate_do_fetch_operations/4" do
    test "skips empty resource when not quiet" do
      snapshot = %{
        table: "empty_posts",
        attributes: [],
        identities: [],
        custom_indexes: [],
        custom_statements: [],
        check_constraints: []
      }

      opts = %{quiet: false}
      assert simulate_do_fetch_operations(snapshot, nil, opts, []) == []
    end

    test "creates operation when resource has attributes" do
      snapshot = %{
        table: "posts_with_attrs",
        attributes: [%{source: "id", type: :uuid}],
        identities: [],
        custom_indexes: [],
        custom_statements: [],
        check_constraints: []
      }

      opts = %{quiet: false}
      assert simulate_do_fetch_operations(snapshot, nil, opts, []) == [:create_table_operation]
    end

    test "skips empty resource when quiet" do
      snapshot = %{
        table: "empty_posts",
        attributes: [],
        identities: [],
        custom_indexes: [],
        custom_statements: [],
        check_constraints: []
      }

      opts = %{quiet: true}
      assert simulate_do_fetch_operations(snapshot, nil, opts, []) == []
    end
  end
end
