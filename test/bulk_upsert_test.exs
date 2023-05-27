defmodule AshPostgres.BulkUpsertTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Api, Manager, Organization}

  describe "Massive Actions" do
    test "bulk creates can upsert with id" do
      org_id = Ash.UUID.generate()

      _new_org =
        Organization
        |> Ash.Changeset.for_create(:create, %{
          id: org_id,
          title: "Avengers"
        })
        |> Api.create!()

      assert [
        {:ok, %{name: "Bruce Banner", code: "BB01", must_be_present: "I am Hulk", organization_id: org_id}},
        {:ok, %{name: "Tony Stark", code: "TS01", must_be_present: "I am Iron Man", organization_id: org_id}},
      ] =
        Api.bulk_create!(
          [
            %{name: "Tony Stark", code: "TS01", must_be_present: "I am Iron Man", organization_id: org_id},
            %{name: "Bruce Banner", code: "BB01", must_be_present: "I am Hulk", organization_id: org_id}
          ],
          Manager,
          :create,
          return_stream?: true,
          return_records?: true
        )
        |> Enum.sort_by(fn {:ok, result} -> result.name end)

      assert [
        {:ok, %{name: "Bruce Banner", code: "BB01", must_be_present: "I am Hulk", organization_id: org_id, role: "bone breaker"}},
        {:ok, %{name: "Tony Stark", code: "TS01", must_be_present: "I am Iron Man", organization_id: org_id, role: "master in chief"}}
      ] =
        Api.bulk_create!(
          [
            %{name: "Tony Stark", code: "TS01", organization_id: org_id, role: "master in chief"},
            %{name: "Brice Brenner", code: "BB01", organization_id: org_id, role: "bone breaker"}
          ],
          Manager,
          :create,
          upsert?: true,
          upsert_identity: :uniq_code,
          upsert_fields: [:role],
          return_stream?: true,
          return_records?: true
        )
        |> Enum.sort_by(fn
          {:ok, result} ->
            result.name

          _ ->
            nil
        end)
    end
  end
end
