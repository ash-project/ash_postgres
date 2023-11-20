defmodule AshPostgres.ReferencesTest do
  use ExUnit.Case

  test "can't use match_type != :full when referencing an non-primary key index" do
    Code.compiler_options(ignore_module_conflict: true)
    on_exit(fn -> Code.compiler_options(ignore_module_conflict: false) end)

    defmodule Org do
      @moduledoc false
      use Ash.Resource,
        data_layer: AshPostgres.DataLayer

      attributes do
        uuid_primary_key(:id, writable?: true)
        attribute(:name, :string)
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
        data_layer: AshPostgres.DataLayer

      attributes do
        uuid_primary_key(:id, writable?: true)
        attribute(:secondary_id, :uuid)
        attribute(:foo_id, :uuid)
        attribute(:name, :string)
        attribute(:org_id, :uuid)
      end

      multitenancy do
        strategy(:attribute)
        attribute(:org_id)
      end

      relationships do
        belongs_to(:org, Org)
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
          data_layer: AshPostgres.DataLayer

        attributes do
          attribute(:id, :string, primary_key?: true, allow_nil?: false)
          attribute(:name, :string)
          attribute(:org_id, :uuid)
          attribute(:foo_id, :uuid)
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
end
