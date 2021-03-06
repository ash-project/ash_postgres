defmodule AshPostgres.TestRepo.Migrations.MigrateResources5 do
  @moduledoc """
  Updates resources based on their most recent snapshots.

  This file was autogenerated with `mix ash_postgres.generate_migrations`
  """

  use Ecto.Migration

  def up do
    alter table(:posts) do
      modify :id, :uuid, default: fragment("uuid_generate_v4()")
    end

    alter table(:post_ratings) do
      modify :id, :uuid, default: fragment("uuid_generate_v4()")
    end

    alter table(:multitenant_orgs) do
      modify :id, :uuid, default: fragment("uuid_generate_v4()")
    end

    alter table(:comments) do
      modify :id, :uuid, default: fragment("uuid_generate_v4()")
    end

    alter table(:comment_ratings) do
      modify :id, :uuid, default: fragment("uuid_generate_v4()")

      modify :resource_id,
             references(:comments, type: :uuid, column: :id, name: "comment_ratings_id_fkey")
    end

    alter table(:comments) do
      modify :post_id,
             references(:posts,
               type: :uuid,
               column: :id,
               name: "special_name_fkey",
               on_delete: :delete_all,
               on_update: :update_all
             )
    end

    alter table(:post_ratings) do
      modify :resource_id,
             references(:posts, type: :uuid, column: :id, name: "post_ratings_id_fkey")
    end
  end

  def down do
    alter table(:post_ratings) do
      modify :resource_id,
             references(:posts, type: :binary_id, column: :id, name: "post_ratings_resource_id")
    end

    alter table(:comments) do
      modify :post_id, references(:posts, type: :binary_id, column: :id, name: "comments_post_id")
    end

    alter table(:comment_ratings) do
      modify :resource_id,
             references(:comments,
               type: :binary_id,
               column: :id,
               name: "comment_ratings_resource_id"
             )

      modify :id, :binary_id, default: nil
    end

    alter table(:comments) do
      modify :id, :binary_id, default: nil
    end

    alter table(:multitenant_orgs) do
      modify :id, :binary_id, default: nil
    end

    alter table(:post_ratings) do
      modify :id, :binary_id, default: nil
    end

    alter table(:posts) do
      modify :id, :binary_id, default: nil
    end
  end
end