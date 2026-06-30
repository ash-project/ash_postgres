# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.TemporalIdentityTest do
  @moduledoc "Identities on temporal resources: period-aware uniqueness + as_of-anchored eager checks (PG19)."
  use AshPostgres.RepoCase, async: false
  @moduletag :temporal

  require Ash.Query
  alias AshPostgres.TestRepo

  defmodule Domain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource(AshPostgres.TemporalIdentityTest.Thing)
    end
  end

  defmodule Thing do
    @moduledoc false
    use Ash.Resource, domain: Domain, data_layer: AshPostgres.DataLayer

    postgres do
      table("temporal_id_thing")
      repo(AshPostgres.TestRepo)
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
        constraints: [inner_type: :datetime, inner_constraints: [precision: :microsecond]],
        public?: true
      )
    end

    identities do
      identity(:unique_name, [:name], eager_check?: true)
    end

    actions do
      defaults([:read, create: [:id, :name, :note]])

      update :touch do
        require_atomic?(true)
        accept([:note])
      end
    end
  end

  @jan ~U[2026-01-01 00:00:00.000000Z]
  @feb ~U[2026-02-01 00:00:00.000000Z]
  @mar ~U[2026-03-01 00:00:00.000000Z]
  @apr ~U[2026-04-01 00:00:00.000000Z]

  setup do
    # Mirror what the migration generator now emits for an identity on a temporal
    # resource: a period-aware GiST exclusion rather than a plain unique index.
    TestRepo.query!("""
    CREATE TABLE temporal_id_thing (
      id integer NOT NULL,
      name text,
      note text,
      valid_at tstzrange NOT NULL,
      PRIMARY KEY (id, valid_at WITHOUT OVERLAPS),
      CONSTRAINT temporal_id_thing_unique_name_index
        EXCLUDE USING gist (name WITH =, valid_at WITH &&)
    )
    """)

    :ok
  end

  # `as_of` is passed as the create opt (not a post-`for_create` call) so it's set before
  # the identity eager check runs during changeset construction.
  defp create(attrs, as_of) do
    Thing
    |> Ash.Changeset.for_create(:create, attrs, as_of: as_of)
    |> Ash.create()
  end

  test "an identity allows the same value across non-overlapping periods (history)" do
    # bounded historical "x" in [jan, mar) (the prior period of entity 1)
    TestRepo.query!(
      "INSERT INTO temporal_id_thing (id, name, valid_at) VALUES (1, 'x', tstzrange('2026-01-01','2026-03-01','[)'))"
    )

    # create the next, contiguous period for the SAME name -> [mar, ∞). A plain unique(name)
    # would reject this; the period-aware exclusion allows it (non-overlapping).
    assert {:ok, _} = create(%{id: 1, name: "x"}, @mar)

    rows =
      TestRepo.query!(
        "SELECT name FROM temporal_id_thing WHERE id = 1 ORDER BY lower(valid_at)"
      ).rows

    assert rows == [["x"], ["x"]]
  end

  test "eager_check at as_of avoids a false-reject (row valid now, but not at the as_of)" do
    # This is the definitive proof the check is anchored at `as_of`, not the wall clock:
    # "z" is valid right NOW but its period ends before `far_future`. Relative to the wall
    # clock so it holds whenever the suite runs.
    now = DateTime.utc_now()
    past = DateTime.add(now, -365, :day)
    near_future = DateTime.add(now, 365, :day)
    far_future = DateTime.add(now, 730, :day)

    TestRepo.query!(
      "INSERT INTO temporal_id_thing (id, name, valid_at) VALUES (9, 'z', tstzrange($1, $2, '[)'))",
      [past, near_future]
    )

    # At `far_future` no "z" is valid, so the eager check (anchored at the write's as_of)
    # passes and the non-overlapping insert succeeds. Read at `now()` it would still see
    # the live "z" and wrongly reject.
    assert {:ok, _} = create(%{id: 10, name: "z"}, far_future)
  end

  test "eager_check is anchored at as_of: a create conflicting at that instant is rejected" do
    # "z" valid across [jan, jun)
    TestRepo.query!(
      "INSERT INTO temporal_id_thing (id, name, valid_at) VALUES (9, 'z', tstzrange('2026-01-01','2026-06-01','[)'))"
    )

    # "z" IS valid at @feb -> the eager check (anchored at @feb) rejects it.
    assert {:error, %Ash.Error.Invalid{}} = create(%{id: 10, name: "z"}, @feb)
  end
end
