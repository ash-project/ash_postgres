defmodule AshPostgres.ReferencesTest do
  use AshPostgres.RepoCase

  test "can't use match_type != :full when referencing an non-primary key index" do
    Code.compiler_options(ignore_module_conflict: true)
    on_exit(fn -> Code.compiler_options(ignore_module_conflict: false) end)

    defmodule Org do
      @moduledoc false
      use Ash.Resource,
        domain: nil,
        data_layer: AshPostgres.DataLayer

      attributes do
        uuid_primary_key(:id, writable?: true)
        attribute(:name, :string, public?: true)
      end

      multitenancy do
        strategy(:attribute)
        attribute(:id)
      end

      postgres do
        table("orgs")
        repo(AshPostgres.TestRepo)
      end

      actions do
        defaults([:create, :read, :update, :destroy])
      end
    end

    defmodule User do
      @moduledoc false
      use Ash.Resource,
        domain: nil,
        data_layer: AshPostgres.DataLayer

      attributes do
        uuid_primary_key(:id, writable?: true)
        attribute(:secondary_id, :uuid, public?: true)
        attribute(:foo_id, :uuid, public?: true)
        attribute(:name, :string, public?: true)
        attribute(:org_id, :uuid, public?: true)
      end

      multitenancy do
        strategy(:attribute)
        attribute(:org_id)
      end

      relationships do
        belongs_to(:org, Org) do
          public?(true)
        end
      end

      postgres do
        table("users")
        repo(AshPostgres.TestRepo)
      end

      actions do
        defaults([:create, :read, :update, :destroy])
      end
    end

    assert_raise Spark.Error.DslError, ~r/Unsupported match_type./, fn ->
      defmodule UserThing do
        @moduledoc false
        use Ash.Resource,
          domain: nil,
          data_layer: AshPostgres.DataLayer

        attributes do
          attribute(:id, :string, primary_key?: true, allow_nil?: false, public?: true)
          attribute(:name, :string, public?: true)
          attribute(:org_id, :uuid, public?: true)
          attribute(:foo_id, :uuid, public?: true)
        end

        multitenancy do
          strategy(:attribute)
          attribute(:org_id)
        end

        relationships do
          belongs_to(:org, Org)
          belongs_to(:user, User, destination_attribute: :secondary_id)
        end

        postgres do
          table("user_things")
          repo(AshPostgres.TestRepo)

          references do
            reference :user, match_with: [foo_id: :foo_id], match_type: :simple
          end
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end
      end
    end
  end

  test "named reference results in properly applied foreign_key_constraint/3 on the underlying changeset" do
    # Create a comment with an invalid post_id
    assert {:error, %Ash.Error.Invalid{errors: errors}} =
             AshPostgres.Test.Comment
             |> Ash.Changeset.for_create(:create, %{
               title: "Test Comment",
               # This post doesn't exist
               post_id: Ash.UUID.generate()
             })
             |> Ash.create()

    assert [
             %Ash.Error.Changes.InvalidAttribute{
               field: :post_id,
               message: "does not exist",
               private_vars: private_vars
             }
           ] = errors

    assert Keyword.get(private_vars, :constraint) == "special_name_fkey"
    assert Keyword.get(private_vars, :constraint_type) == :foreign_key
  end
end
