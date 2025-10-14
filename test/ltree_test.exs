# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.LtreeTest do
  use AshPostgres.RepoCase, async: true
  use ExUnitProperties

  alias AshPostgres.Ltree
  alias AshPostgres.Test.Post

  require Ash.Query

  doctest AshPostgres.Ltree

  describe inspect(&Ltree.storage_type/1) do
    test "correct" do
      assert :ltree = Ltree.storage_type([])
    end
  end

  describe inspect(&Ltree.matches_type?/2) do
    test "correct" do
      assert Ltree.matches_type?(["1", "2"], [])
      assert Ltree.matches_type?("1.2", [])
      refute Ltree.matches_type?("1.2", escape?: true)
    end
  end

  describe inspect(&Ltee.generator/1) do
    property "generates valid ltrees" do
      check all(
              constraints <- constraints_generator(),
              ltree <- Ltree.generator(constraints)
            ) do
        assert :ok = Ltree.apply_constraints(ltree, constraints)
      end
    end
  end

  describe inspect(&Ltree.apply_constraints/2) do
    test "checks min length" do
      assert :ok = Ltree.apply_constraints(["1", "2"], min_length: 2)

      assert {:error, [message: "must have %{min} or more items", min: 2]} =
               Ltree.apply_constraints(["1"], min_length: 2)
    end

    test "checks max length" do
      assert :ok = Ltree.apply_constraints(["1", "2"], max_length: 2)

      assert {:error, [message: "must have %{max} or less items", max: 1]} =
               Ltree.apply_constraints(["1", "2"], max_length: 1)
    end

    test "checks UTF-8" do
      assert :ok = Ltree.apply_constraints(["1", "2"], [])

      assert {:error,
              [message: "Ltree segments must be valid UTF-8 strings.", value: <<0xFFFF::16>>]} =
               Ltree.apply_constraints([<<0xFFFF::16>>, "2"], [])
    end

    test "checks empty string" do
      assert {:error, [message: "Ltree segments can't be empty.", value: ""]} =
               Ltree.apply_constraints(["", "2"], [])
    end

    test ~S|can't contain "." when escape? is not enabled| do
      assert :ok = Ltree.apply_constraints(["1", "2"], [])

      assert {:error,
              [
                message: ~S|Ltree segments can't contain "." if :escape? is not enabled.|,
                value: "1.2"
              ]} = Ltree.apply_constraints(["1.2"], [])

      assert :ok = Ltree.apply_constraints(["1.2"], escape?: true)
    end
  end

  describe inspect(&Ltree.cast_input/2) do
    test "casts nil" do
      assert {:ok, nil} = Ltree.cast_input(nil, [])
    end

    test "casts list" do
      assert {:ok, ["1", "2"]} = Ltree.cast_input(["1", "2"], [])
    end

    test "casts binary if escaped?" do
      assert {:ok, ["1", "2"]} = Ltree.cast_input("1.2", [])

      assert {:error,
              "String input casting is not supported when the :escape? constraint is enabled"} =
               Ltree.cast_input("1.2", escape?: true)
    end
  end

  describe inspect(&Ltree.cast_stored/2) do
    test "casts nil" do
      assert {:ok, nil} = Ltree.cast_stored(nil, [])
    end

    test "casts binary" do
      assert {:ok, ["1", "2"]} = Ltree.cast_stored("1.2", [])
    end

    test "unescapes segments" do
      assert {:ok, ["1.", "2"]} = Ltree.cast_stored("1_2E.2", escape?: true)
    end
  end

  describe inspect(&Ltree.dump_to_native/2) do
    test "dumps nil" do
      assert {:ok, nil} = Ltree.dump_to_native(nil, [])
    end

    test "dumps list" do
      assert {:ok, "1.2"} = Ltree.dump_to_native(["1", "2"], [])
    end

    test "escapes segments" do
      assert {:ok, "1_2E.2"} = Ltree.dump_to_native(["1.", "2"], escape?: true)
    end
  end

  describe inspect(&Ltree.shared_root/2) do
    test "works when they share a root" do
      assert ["1"] = Ltree.shared_root(["1", "1"], ["1", "2"])
    end

    test "returns empty list if they do not share a root" do
      assert [] = Ltree.shared_root(["1", "2"], ["2", "1"])
    end
  end

  describe "escape/unescape" do
    property "escape |> unescape results in same value" do
      check all(ltree <- Ltree.generator(escape?: true)) do
        assert {:ok, stored} = Ltree.dump_to_native(ltree, escape?: true)
        assert {:ok, loaded} = Ltree.cast_stored(stored, escape?: true)

        assert loaded == ltree
      end
    end
  end

  describe "integration" do
    test "can serialize / underialize to db" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{
          title: "title",
          ltree_unescaped: ["1", "2"],
          ltree_escaped: ["1.", "2"]
        })
        |> Ash.create!()

      assert %Post{id: id, ltree_unescaped: ["1", "2"], ltree_escaped: ["1.", "2"]} = post

      assert %Post{id: ^id} =
               Post |> Ash.Query.filter(ltree_unescaped == ["1", "2"]) |> Ash.read_one!()

      assert %Post{id: ^id} =
               Post |> Ash.Query.filter(ltree_escaped == ["1.", "2"]) |> Ash.read_one!()
    end
  end

  defp constraints_generator do
    [
      StreamData.tuple({StreamData.constant(:escape?), StreamData.boolean()}),
      StreamData.tuple({StreamData.constant(:min_length), StreamData.non_negative_integer()}),
      StreamData.tuple({StreamData.constant(:max_length), StreamData.positive_integer()})
    ]
    |> StreamData.one_of()
    |> StreamData.list_of(max_length: 3)
    |> StreamData.filter(&(not (&1[:min_length] > &1[:max_length])))
  end
end
