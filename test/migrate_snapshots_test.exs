# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshPostgres.MigrateSnapshotsTest do
  use ExUnit.Case, async: true
  @moduletag :tmp_dir

  alias AshPostgres.MigrationGenerator.Operation.Codec

  defp legacy_snapshot_json(table, attributes \\ []) do
    Jason.encode!(%{
      attributes: attributes,
      base_filter: nil,
      check_constraints: [],
      custom_indexes: [],
      custom_statements: [],
      has_create_action: true,
      hash: "ABCDEF",
      identities: [],
      multitenancy: %{attribute: nil, global: nil, strategy: nil},
      repo: "Elixir.AshPostgres.TestRepo",
      schema: nil,
      table: table
    })
  end

  defp legacy_attribute(source, type) do
    %{
      source: source,
      type: type,
      default: "nil",
      size: nil,
      precision: nil,
      scale: nil,
      primary_key?: false,
      allow_nil?: true,
      generated?: false,
      references: nil
    }
  end

  test "converts a directory of legacy snapshots into a single v2 delta", %{tmp_dir: tmp_dir} do
    resource_dir = Path.join([tmp_dir, "test_repo", "authors"])
    File.mkdir_p!(resource_dir)

    attrs = [
      legacy_attribute(:id, :uuid),
      legacy_attribute(:email, :text)
    ]

    earlier = Path.join(resource_dir, "20260101000000.json")
    latest = Path.join(resource_dir, "20260215120000.json")

    File.write!(earlier, legacy_snapshot_json("authors"))
    File.write!(latest, legacy_snapshot_json("authors", attrs))

    Mix.Tasks.AshPostgres.MigrateSnapshots.run([
      "--snapshot-path",
      tmp_dir,
      "--quiet"
    ])

    assert File.exists?(latest)
    assert Codec.delta?(File.read!(latest))

    # Legacy earlier file was moved out to .legacy_backup
    refute File.exists?(earlier)
    backup_files = Path.wildcard(Path.join([tmp_dir, ".legacy_backup", "**/*.json"]))
    assert Enum.any?(backup_files, &String.ends_with?(&1, "20260101000000.json"))

    # The new delta reduces to two attributes
    decoded = latest |> File.read!() |> Codec.decode_delta()

    sources =
      decoded.operations
      |> Enum.filter(&match?(%AshPostgres.MigrationGenerator.Operation.AddAttribute{}, &1))
      |> Enum.map(& &1.attribute.source)

    assert :id in sources
    assert :email in sources
  end

  test "is a no-op for directories already containing v2 deltas", %{tmp_dir: tmp_dir} do
    resource_dir = Path.join([tmp_dir, "test_repo", "v2_only"])
    File.mkdir_p!(resource_dir)

    v2_path = Path.join(resource_dir, "20260101000000.json")
    File.write!(v2_path, Codec.encode_delta([]))

    # Running against an already-v2 directory should leave the file untouched.
    before = File.read!(v2_path)

    Mix.Tasks.AshPostgres.MigrateSnapshots.run([
      "--snapshot-path",
      tmp_dir,
      "--quiet"
    ])

    assert File.read!(v2_path) == before
  end

  test "--dry-run does not modify files", %{tmp_dir: tmp_dir} do
    resource_dir = Path.join([tmp_dir, "test_repo", "dryrun"])
    File.mkdir_p!(resource_dir)

    latest = Path.join(resource_dir, "20260101000000.json")
    File.write!(latest, legacy_snapshot_json("dryrun"))

    before = File.read!(latest)

    Mix.Tasks.AshPostgres.MigrateSnapshots.run([
      "--snapshot-path",
      tmp_dir,
      "--dry-run",
      "--quiet"
    ])

    assert File.read!(latest) == before
  end

  test "--keep-legacy preserves old files alongside the new v2 delta", %{tmp_dir: tmp_dir} do
    resource_dir = Path.join([tmp_dir, "test_repo", "keep_legacy"])
    File.mkdir_p!(resource_dir)

    earlier = Path.join(resource_dir, "20260101000000.json")
    latest = Path.join(resource_dir, "20260201000000.json")

    File.write!(earlier, legacy_snapshot_json("keep_legacy"))
    File.write!(latest, legacy_snapshot_json("keep_legacy"))

    Mix.Tasks.AshPostgres.MigrateSnapshots.run([
      "--snapshot-path",
      tmp_dir,
      "--keep-legacy",
      "--quiet"
    ])

    # Latest is now v2
    assert Codec.delta?(File.read!(latest))
    # Earlier is preserved
    assert File.exists?(earlier)
    refute Codec.delta?(File.read!(earlier))
  end

  describe "mix ash_postgres.squash_snapshots (delta mode)" do
    test "reduces multiple delta files into a single initial delta", %{tmp_dir: tmp_dir} do
      resource_dir = Path.join([tmp_dir, "test_repo", "squash_me"])
      File.mkdir_p!(resource_dir)

      # First delta: creates table with id + title
      ops1 = [
        %AshPostgres.MigrationGenerator.Operation.CreateTable{
          table: "squash_me",
          schema: nil,
          multitenancy: %{attribute: nil, strategy: nil, global: nil},
          old_multitenancy: %{attribute: nil, strategy: nil, global: nil},
          repo: AshPostgres.TestRepo,
          create_table_options: nil
        },
        %AshPostgres.MigrationGenerator.Operation.AddAttribute{
          table: "squash_me",
          schema: nil,
          multitenancy: %{attribute: nil, strategy: nil, global: nil},
          old_multitenancy: %{attribute: nil, strategy: nil, global: nil},
          attribute: %{
            source: :id,
            type: :uuid,
            default: "fragment(\"gen_random_uuid()\")",
            size: nil,
            precision: nil,
            scale: nil,
            primary_key?: true,
            allow_nil?: false,
            generated?: false,
            references: nil
          }
        },
        %AshPostgres.MigrationGenerator.Operation.AddAttribute{
          table: "squash_me",
          schema: nil,
          multitenancy: %{attribute: nil, strategy: nil, global: nil},
          old_multitenancy: %{attribute: nil, strategy: nil, global: nil},
          attribute: %{
            source: :title,
            type: :text,
            default: "nil",
            size: nil,
            precision: nil,
            scale: nil,
            primary_key?: false,
            allow_nil?: true,
            generated?: false,
            references: nil
          }
        }
      ]

      # Second delta: adds body
      ops2 = [
        %AshPostgres.MigrationGenerator.Operation.AddAttribute{
          table: "squash_me",
          schema: nil,
          multitenancy: %{attribute: nil, strategy: nil, global: nil},
          old_multitenancy: %{attribute: nil, strategy: nil, global: nil},
          attribute: %{
            source: :body,
            type: :text,
            default: "nil",
            size: nil,
            precision: nil,
            scale: nil,
            primary_key?: false,
            allow_nil?: true,
            generated?: false,
            references: nil
          }
        }
      ]

      File.write!(
        Path.join(resource_dir, "20260101000000.json"),
        Codec.encode_delta(ops1, %{resulting_hash: "A"})
      )

      File.write!(
        Path.join(resource_dir, "20260201000000.json"),
        Codec.encode_delta(ops2, %{previous_hash: "A", resulting_hash: "B"})
      )

      Mix.Tasks.AshPostgres.SquashSnapshots.run([
        "--snapshot-path",
        tmp_dir,
        "--quiet"
      ])

      # Only one file remains, named after the latest (per --into last default)
      files = File.ls!(resource_dir) |> Enum.sort()
      assert files == ["20260201000000.json"]

      # That single file is a v2 delta and reduces to state with id + title + body.
      contents = resource_dir |> Path.join("20260201000000.json") |> File.read!()
      assert Codec.delta?(contents)

      decoded = Codec.decode_delta(contents)

      sources =
        decoded.operations
        |> Enum.filter(&match?(%AshPostgres.MigrationGenerator.Operation.AddAttribute{}, &1))
        |> Enum.map(& &1.attribute.source)
        |> Enum.sort()

      assert :body in sources
      assert :id in sources
      assert :title in sources
    end

    test "aborts on folder containing both legacy and delta formats", %{tmp_dir: tmp_dir} do
      resource_dir = Path.join([tmp_dir, "test_repo", "mixed"])
      File.mkdir_p!(resource_dir)

      File.write!(Path.join(resource_dir, "20260101000000.json"), legacy_snapshot_json("mixed"))
      File.write!(Path.join(resource_dir, "20260201000000.json"), Codec.encode_delta([]))

      assert_raise RuntimeError, ~r/mix of legacy full-state and v2 delta/, fn ->
        Mix.Tasks.AshPostgres.SquashSnapshots.run([
          "--snapshot-path",
          tmp_dir,
          "--quiet"
        ])
      end
    end
  end
end
