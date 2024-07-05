defmodule AshPostgres.StorageTypesTest do
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.Author
  alias Ash.BulkResult

  require Ash.Query

  test "can save {:array, :map} as jsonb" do
    %{id: id} =
      Author
      |> Ash.Changeset.for_create(
        :create,
        %{bios: [%{title: "bio1"}, %{title: "bio2"}]}
      )
      |> Ash.create!()

    Logger.configure(level: :debug)

    {:ok, %BulkResult{records: [author]}} =
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
  end
end
