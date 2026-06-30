# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.TemporalMigrationGeneratorTest do
  @moduledoc "Asserts the migration generator emits temporal DDL (PG19)."
  use AshPostgres.RepoCase, async: false
  @moduletag :temporal
  @moduletag :tmp_dir

  defmodule GenTier do
    @moduledoc false
    use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

    postgres do
      table("gen_tier")
      repo(AshPostgres.TestRepo)
    end

    temporal do
      strategy(:context)
      attribute(:valid_at)
    end

    attributes do
      attribute(:id, :integer, primary_key?: true, allow_nil?: false, public?: true)
      attribute(:name, :string, public?: true)

      attribute(:valid_at, Ash.Type.Range,
        constraints: [inner_type: :datetime, inner_constraints: [precision: :microsecond]],
        public?: true
      )
    end

    identities do
      # On a temporal resource this must be emitted as a period-aware (WITHOUT OVERLAPS)
      # exclusion, not a plain unique index — see the migration assertions below.
      identity(:unique_name, [:name])
    end
  end

  defmodule GenSub do
    @moduledoc false
    use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

    postgres do
      table("gen_sub")
      repo(AshPostgres.TestRepo)
    end

    temporal do
      strategy(:context)
      attribute(:valid_at)
    end

    attributes do
      attribute(:id, :integer, primary_key?: true, allow_nil?: false, public?: true)
      attribute(:tier_id, :integer, public?: true)

      attribute(:valid_at, Ash.Type.Range,
        constraints: [inner_type: :datetime, inner_constraints: [precision: :microsecond]],
        public?: true
      )
    end

    relationships do
      belongs_to :tier_record, AshPostgres.TemporalMigrationGeneratorTest.GenTier do
        source_attribute(:tier_id)
        destination_attribute(:id)
        temporal_keys({:valid_at, :valid_at})
        define_attribute?(false)
        public?(true)
      end
    end
  end

  defmodule Domain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource(AshPostgres.TemporalMigrationGeneratorTest.GenTier)
      resource(AshPostgres.TemporalMigrationGeneratorTest.GenSub)
    end
  end

  setup %{tmp_dir: tmp_dir} do
    %{
      snapshot_path: Path.join(tmp_dir, "snapshots"),
      migration_path: Path.join(tmp_dir, "migrations")
    }
  end

  test "emits range column, WITHOUT OVERLAPS PK, PERIOD FK and btree_gist, version-guarded", %{
    snapshot_path: snapshot_path,
    migration_path: migration_path
  } do
    AshPostgres.MigrationGenerator.generate(Domain,
      snapshot_path: snapshot_path,
      migration_path: migration_path,
      quiet: true,
      format: false,
      auto_name: true
    )

    migration =
      "#{migration_path}/**/*_migrate_resources*.exs"
      |> Path.wildcard()
      |> Enum.reject(&String.contains?(&1, "extensions"))
      |> Enum.at(0)
      |> File.read!()

    # range period column
    assert migration =~ ":tstzrange"

    # temporal WITHOUT OVERLAPS primary key, version-guarded with a plain-PK fallback
    assert migration =~ "ADD PRIMARY KEY (id, valid_at WITHOUT OVERLAPS)"
    assert migration =~ "ADD PRIMARY KEY (id)"
    assert migration =~ "server_version_num"
    assert migration =~ "190_000"

    # temporal PERIOD foreign key (also version-guarded)
    assert migration =~ "FOREIGN KEY (tier_id, PERIOD valid_at)"
    assert migration =~ "PERIOD valid_at)"

    # identity on a temporal resource -> period-aware exclusion (WITHOUT OVERLAPS),
    # version-guarded with a plain unique-index fallback on pre-PG19 servers.
    assert migration =~ "EXCLUDE USING gist (name WITH =, valid_at WITH &&)"
    assert migration =~ ~r/create unique_index\(:gen_tier, \[:name\]/

    # btree_gist installed via the extensions migration, not inline
    refute migration =~ "btree_gist"

    extensions =
      "#{migration_path}/**/*extensions*.exs"
      |> Path.wildcard()
      |> Enum.at(0)

    assert extensions, "expected an extensions migration"
    assert File.read!(extensions) =~ "btree_gist"
  end
end
