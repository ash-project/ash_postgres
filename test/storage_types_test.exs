defmodule AshPostgres.StorageTypesTest do
  use AshPostgres.RepoCase, async: false

  alias Ash.BulkResult
  alias AshPostgres.Test.Author

  require Ash.Query

  test "can save {:array, :map} as jsonb" do
    %{id: id} =
      Author
      |> Ash.Changeset.for_create(
        :create,
        %{bios: [%{title: "bio1"}, %{title: "bio2"}]}
      )
      |> Ash.create!()

    # testing empty list edge case
    %BulkResult{records: [author]} =
      Author
      |> Ash.Query.filter(id == ^id)
      |> Ash.bulk_update(:update, %{bios: []},
        return_errors?: true,
        notify?: true,
        strategy: [:atomic, :stream, :atomic_batches],
        allow_stream_with: :full_read,
        return_records?: true
      )

    assert author.bios == []

    %BulkResult{records: [author]} =
      Author
      |> Ash.Query.filter(id == ^id)
      |> Ash.bulk_update(:update, %{bios: [%{a: 1}]},
        return_errors?: true,
        notify?: true,
        strategy: [:atomic, :stream, :atomic_batches],
        allow_stream_with: :full_read,
        return_records?: true
      )

    assert author.bios == [%{"a" => 1}]
  end
end
