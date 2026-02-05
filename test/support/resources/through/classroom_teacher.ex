# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Through.ClassroomTeacher do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "classroom_teachers"
    repo AshPostgres.TestRepo
  end

  attributes do
    uuid_primary_key(:id)

    attribute :retired_at, :utc_datetime_usec do
      public?(true)
      allow_nil?(true)
    end
  end

  actions do
    default_accept(:*)
    defaults([:read, :destroy, update: :*])

    create :assign do
      primary?(true)
      upsert?(true)
      upsert_identity(:unique_classroom_teacher)

      change(fn changeset, _context ->
        Ash.Changeset.after_action(changeset, fn _changeset, record ->
          __MODULE__
          |> Ash.Query.filter(classroom_id == ^record.classroom_id and is_nil(retired_at))
          |> Ash.Query.filter(id != ^record.id)
          |> Ash.bulk_update!(:update, %{retired_at: DateTime.utc_now()},
            authorize?: false,
            return_records?: false
          )

          {:ok, record}
        end)
      end)
    end
  end

  relationships do
    belongs_to :classroom, AshPostgres.Test.Through.Classroom do
      public?(true)
      allow_nil?(false)
    end

    belongs_to :teacher, AshPostgres.Test.Through.Teacher do
      public?(true)
      allow_nil?(false)
    end
  end

  identities do
    identity(:unique_classroom_teacher, [:classroom_id, :teacher_id])
  end
end
