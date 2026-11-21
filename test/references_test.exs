# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.ReferencesTest do
  use AshPostgres.RepoCase
  import ExUnit.CaptureIO
  import Spark.Test

  defmodule PolymorphicComment do
    use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

    postgres do
      repo AshPostgres.TestRepo
      polymorphic? true
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:resource_id, :uuid)
    end
  end

  defp define_polymorphic_source(name, references, legacy \\ []) do
    name = Module.concat(__MODULE__, name)
    legacy_options = for {key, value} <- legacy, do: {key, [], [Macro.escape(value)]}

    Code.compile_quoted(
      quote location: :keep do
        defmodule unquote(name) do
          use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

          postgres do
            repo AshPostgres.TestRepo
            table "posts"

            references do
              (unquote_splicing(legacy_options))
            end
          end

          attributes do
            uuid_primary_key(:id)
          end

          relationships do
            has_many :comments, unquote(PolymorphicComment) do
              destination_attribute(:resource_id)

              relationship_context(%{
                data_layer: %{
                  table: "post_comments",
                  references: unquote(Macro.escape(references))
                }
              })
            end
          end
        end
      end,
      __ENV__.file
    )
  end

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

    {_, io} =
      with_io(:stderr, fn ->
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
      end)

    assert io =~ "Unsupported match_type"
  end

  test "raises error when reference is configured for a has_many relationship" do
    Code.compiler_options(ignore_module_conflict: true)
    on_exit(fn -> Code.compiler_options(ignore_module_conflict: false) end)

    {_, io} =
      with_io(:stderr, fn ->
        defmodule Parent do
          @moduledoc false
          use Ash.Resource,
            domain: nil,
            data_layer: AshPostgres.DataLayer

          attributes do
            uuid_primary_key(:id)
          end

          relationships do
            has_many(:children, AshPostgres.ReferencesTest.Child)
          end

          postgres do
            table("parents")
            repo(AshPostgres.TestRepo)

            references do
              reference :children, on_delete: :delete
            end
          end

          actions do
            defaults([:create, :read, :update, :destroy])
          end
        end

        defmodule Child do
          @moduledoc false
          use Ash.Resource,
            domain: nil,
            data_layer: AshPostgres.DataLayer

          attributes do
            uuid_primary_key(:id)
          end

          relationships do
            belongs_to(:parent, AshPostgres.ReferencesTest.Parent)
          end

          postgres do
            table("children")
            repo(AshPostgres.TestRepo)
          end

          actions do
            defaults([:create, :read, :update, :destroy])
          end
        end
      end)

    assert io =~ "References can only be configured for `belongs_to` relationships"
  end

  test "polymorphic references must be a map and the error identifies the relationship" do
    error =
      assert_dsl_error do
        define_polymorphic_source(InvalidPolymorphicReferences, "invalid")
      end

    assert error.path == [
             :relationships,
             :comments,
             :relationship_context,
             :data_layer,
             :references
           ]

    assert error.message =~ "map"
  end

  test "unknown polymorphic reference options are rejected" do
    for {name, references, key} <- [
          {UnknownPolymorphicReference, %{on_delet: :delete}, "on_delet"},
          {StringPolymorphicReference, %{"on_delete" => :delete}, "on_delete"}
        ] do
      error =
        assert_dsl_error do
          define_polymorphic_source(name, references)
        end

      assert error.message =~ key
    end
  end

  test "polymorphic reference values are validated" do
    for {name, option, value} <- [
          {InvalidPolymorphicDelete, :on_delete, :update},
          {InvalidPolymorphicUpdate, :on_update, :delete}
        ] do
      error =
        assert_dsl_error do
          define_polymorphic_source(name, %{option => value})
        end

      assert error.message =~ to_string(option)
    end

    refute_dsl_errors do
      define_polymorphic_source(NilifyPolymorphicReference, %{
        on_delete: {:nilify, :resource_id}
      })
    end
  end

  test "legacy and relationship polymorphic reference settings conflict per option" do
    for {name, option, value, legacy} <- [
          {DuplicatePolymorphicDelete, :on_delete, :delete, [polymorphic_on_delete: :delete]},
          {ConflictingPolymorphicUpdate, :on_update, :update, [polymorphic_on_update: :restrict]}
        ] do
      error =
        assert_dsl_error do
          define_polymorphic_source(name, %{option => value}, legacy)
        end

      assert error.message =~ "polymorphic_#{option}"
      assert error.message =~ "both"
    end

    refute_dsl_errors do
      define_polymorphic_source(MixedPolymorphicReferenceFormats, %{on_update: :update},
        polymorphic_on_delete: :delete
      )
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

  test "foreign_key_names message takes precedence over the relationship's foreign key on create" do
    assert {:error, %Ash.Error.Invalid{errors: errors}} =
             AshPostgres.Test.Permalink
             |> Ash.Changeset.for_create(:create, %{post_id: Ash.UUID.generate()})
             |> Ash.create()

    assert [
             %Ash.Error.Changes.InvalidAttribute{
               field: :post_id,
               message: "post must exist"
             }
           ] = errors
  end

  test "foreign_key_names message takes precedence over the related foreign key on destroy" do
    container = Ash.create!(AshPostgres.Test.Container, %{})
    Ash.create!(AshPostgres.Test.Item, %{container_id: container.id})

    assert {:error, %Ash.Error.Invalid{errors: errors}} = Ash.destroy(container)

    assert [
             %Ash.Error.Changes.InvalidAttribute{
               field: :id,
               message: "container still has items"
             }
           ] = errors
  end
end
