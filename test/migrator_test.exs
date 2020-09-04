defmodule AshPostgres.MigratorTest do
  use AshPostgres.RepoCase, async: false

  defmodule Post do
    use Ash.Resource,
      data_layer: AshPostgres.DataLayer

    postgres do
      table "posts"
      repo AshPostgres.TestRepo
    end

    actions do
      read(:read)
      create(:create)
    end

    resource do
      identities do
        identity(:public_title, [:title, :public])
      end
    end

    attributes do
      attribute(:id, :uuid, primary_key?: true, default: &Ecto.UUID.generate/0)
      attribute(:title, :string)
      attribute(:score, :integer)
      attribute(:public, :boolean)
    end

    relationships do
      has_many(:comments, AshPostgres.MigratorTest.Comment, destination_field: :post_id)
    end
  end

  defmodule Comment do
    use Ash.Resource,
      data_layer: AshPostgres.DataLayer

    postgres do
      table "comments"
      repo AshPostgres.TestRepo
    end

    actions do
      read(:read)
      create(:create)
    end

    attributes do
      attribute(:id, :uuid, primary_key?: true, default: &Ecto.UUID.generate/0)
      attribute(:title, :string)
    end

    relationships do
      belongs_to(:post, Post)
    end
  end

  defmodule Api do
    use Ash.Api

    resources do
      resource(Post)
      resource(Comment)
    end
  end

  test "if the snapshot path doesn't exist, it raises" do
    assert_raise Mix.Error, ~r/Could not find snapshots directory/, fn ->
      AshPostgres.Migrator.take_snapshots(Api, snapshot_path: "alskjdfhalsdkjfh")
    end
  end

  test "if the `init` flag is set, the path is created" do
    on_exit(fn ->
      "test_snapshots_path/*"
      |> Path.wildcard()
      |> File.rm!()

      "test_migration_path/**/*"
      |> Path.wildcard()
      |> File.rm!()

      "test_migration_path/*"
      |> Path.wildcard()
      |> File.rmdir!()

      File.rmdir!("test_snapshots_path") |> IO.inspect()
      File.rmdir!("test_migration_path") |> IO.inspect()
    end)

    AshPostgres.Migrator.take_snapshots(Api,
      snapshot_path: "test_snapshots_path",
      migration_path: "test_migration_path",
      init: true
    )

    assert File.exists?("test_snapshots_path")
    # assert File.exists?("test_migration_path")
  end
end
