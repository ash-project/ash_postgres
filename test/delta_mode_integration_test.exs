# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.DeltaModeIntegrationTest do
  use AshPostgres.RepoCase, async: false
  @moduletag :migration
  @moduletag :tmp_dir

  alias AshPostgres.MigrationGenerator
  alias AshPostgres.MigrationGenerator.Operation
  alias AshPostgres.MigrationGenerator.Operation.Codec
  alias AshPostgres.MigrationGenerator.Reducer

  @mt %{strategy: nil, attribute: nil, global: nil}

  setup %{tmp_dir: tmp_dir} do
    current_shell = Mix.shell()
    :ok = Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(current_shell) end)

    %{
      snapshot_path: Path.join(tmp_dir, "snapshots"),
      migration_path: Path.join(tmp_dir, "migrations"),
      tenant_migration_path: Path.join(tmp_dir, "tenant_migrations")
    }
  end

  # ===================================================================
  # Test helpers
  # ===================================================================

  defmacrop defresource(mod, do: body) do
    quote do
      Code.compiler_options(ignore_module_conflict: true)

      defmodule unquote(mod) do
        use Ash.Resource,
          domain: nil,
          data_layer: AshPostgres.DataLayer

        unquote(body)
      end

      Code.compiler_options(ignore_module_conflict: false)
    end
  end

  defmacrop defdomain(resources) do
    quote do
      Code.compiler_options(ignore_module_conflict: true)

      defmodule Domain do
        use Ash.Domain

        resources do
          for resource <- unquote(resources) do
            resource(resource)
          end
        end
      end

      Code.compiler_options(ignore_module_conflict: false)
    end
  end

  defp run_codegen(domain, snapshot_path, migration_path, extra \\ []) do
    MigrationGenerator.generate(
      domain,
      [
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        tenant_migration_path: Path.join(Path.dirname(migration_path), "tenant_migrations"),
        quiet: true,
        format: false,
        auto_name: true,
        snapshot_format: :delta
      ] ++ extra
    )
  end

  defp delta_files(snapshot_path, table) do
    "#{snapshot_path}/**/#{table}/*.json"
    |> Path.wildcard()
    |> Enum.sort()
  end

  defp read_delta(path), do: path |> File.read!() |> Codec.decode_delta()

  defp migration_files(migration_path) do
    "#{migration_path}/**/*_migrate_resources*.exs"
    |> Path.wildcard()
    |> Enum.reject(&String.contains?(&1, "extensions"))
    |> Enum.sort()
  end

  defp ops_of_type(delta, module) do
    Enum.filter(delta.operations, &(&1.__struct__ == module))
  end

  defp reduce_dir(snapshot_path, table, schema \\ nil) do
    snapshot = %{
      table: table,
      schema: schema,
      repo: AshPostgres.TestRepo,
      multitenancy: @mt
    }

    opts = %MigrationGenerator{snapshot_path: snapshot_path, dev: false, quiet: true}
    Reducer.load_reduced_state(snapshot, opts)
  end

  # ===================================================================
  # Basic codegen — initial + follow-up
  # ===================================================================

  describe "basic codegen" do
    test "initial codegen produces a v2 delta with CreateTable + AddAttribute ops", %{
      snapshot_path: sp,
      migration_path: mp
    } do
      defresource DeltaPostA do
        postgres do
          table("delta_posts_a")
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true)
        end
      end

      defdomain([DeltaPostA])
      run_codegen(Domain, sp, mp)

      [delta_file] = delta_files(sp, "delta_posts_a")
      delta = read_delta(delta_file)

      assert delta.version == 2
      assert length(ops_of_type(delta, Operation.CreateTable)) == 1

      sources =
        delta
        |> ops_of_type(Operation.AddAttribute)
        |> Enum.map(& &1.attribute.source)

      assert :id in sources
      assert :title in sources
    end

    test "adding an attribute in a follow-up codegen produces a minimal delta", %{
      snapshot_path: sp,
      migration_path: mp
    } do
      defresource DeltaPostB do
        postgres do
          table("delta_posts_b")
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true)
        end
      end

      defdomain([DeltaPostB])
      run_codegen(Domain, sp, mp)

      defresource DeltaPostB do
        postgres do
          table("delta_posts_b")
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true)
          attribute(:body, :string, public?: true)
        end
      end

      defdomain([DeltaPostB])
      run_codegen(Domain, sp, mp)

      files = delta_files(sp, "delta_posts_b")
      assert length(files) == 2

      second = List.last(files) |> read_delta()
      adds = ops_of_type(second, Operation.AddAttribute)
      assert [%{attribute: %{source: :body}}] = adds
      # Shouldn't contain CreateTable in a follow-up
      assert ops_of_type(second, Operation.CreateTable) == []
    end

    test "codegen with no changes does not emit any new delta files", %{
      snapshot_path: sp,
      migration_path: mp
    } do
      defresource DeltaPostC do
        postgres do
          table("delta_posts_c")
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
        end
      end

      defdomain([DeltaPostC])
      run_codegen(Domain, sp, mp)
      [_initial] = delta_files(sp, "delta_posts_c")

      # Second call with identical resource
      run_codegen(Domain, sp, mp)
      assert length(delta_files(sp, "delta_posts_c")) == 1
    end
  end

  # ===================================================================
  # Structural changes: remove, rename, references
  # ===================================================================

  describe "structural changes" do
    test "removing an attribute produces a RemoveAttribute op that reduces correctly", %{
      snapshot_path: sp,
      migration_path: mp
    } do
      defresource DeltaPostD do
        postgres do
          table("delta_posts_d")
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true)
          attribute(:body, :string, public?: true)
        end
      end

      defdomain([DeltaPostD])
      run_codegen(Domain, sp, mp)

      # Remove :body
      defresource DeltaPostD do
        postgres do
          table("delta_posts_d")
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true)
        end
      end

      defdomain([DeltaPostD])
      run_codegen(Domain, sp, mp)

      second = delta_files(sp, "delta_posts_d") |> List.last() |> read_delta()
      removes = ops_of_type(second, Operation.RemoveAttribute)
      assert [%{attribute: %{source: :body}}] = removes

      # Reduced state: :body gone, :id + :title remain
      state = reduce_dir(sp, "delta_posts_d")
      sources = Enum.map(state.attributes, & &1.source)
      assert :id in sources
      assert :title in sources
      refute :body in sources
    end

    test "renaming an attribute produces a RenameAttribute op", %{
      snapshot_path: sp,
      migration_path: mp
    } do
      defresource DeltaPostE do
        postgres do
          table("delta_posts_e")
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true)
        end
      end

      defdomain([DeltaPostE])
      run_codegen(Domain, sp, mp)

      defresource DeltaPostE do
        postgres do
          table("delta_posts_e")
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:name, :string, public?: true)
        end
      end

      defdomain([DeltaPostE])

      # "Yes" to "Are you renaming :title to :name?"
      send(self(), {:mix_shell_input, :yes?, true})
      run_codegen(Domain, sp, mp)

      second = delta_files(sp, "delta_posts_e") |> List.last() |> read_delta()
      renames = ops_of_type(second, Operation.RenameAttribute)
      assert [%{old_attribute: %{source: :title}, new_attribute: %{source: :name}}] = renames

      state = reduce_dir(sp, "delta_posts_e")
      sources = Enum.map(state.attributes, & &1.source)
      assert :name in sources
      refute :title in sources
    end

    test "altering an attribute (type change) produces an AlterAttribute op", %{
      snapshot_path: sp,
      migration_path: mp
    } do
      defresource DeltaPostF do
        postgres do
          table("delta_posts_f")
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true, allow_nil?: true)
        end
      end

      defdomain([DeltaPostF])
      run_codegen(Domain, sp, mp)

      defresource DeltaPostF do
        postgres do
          table("delta_posts_f")
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true, allow_nil?: false)
        end
      end

      defdomain([DeltaPostF])
      run_codegen(Domain, sp, mp)

      second = delta_files(sp, "delta_posts_f") |> List.last() |> read_delta()
      alters = ops_of_type(second, Operation.AlterAttribute)

      assert Enum.any?(alters, fn op ->
               op.new_attribute.source == :title and op.new_attribute.allow_nil? == false
             end)
    end

    test "renaming a table produces a RenameTable op", %{
      snapshot_path: sp,
      migration_path: mp
    } do
      defresource DeltaPostG do
        postgres do
          table("delta_posts_g_old")
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
        end
      end

      defdomain([DeltaPostG])
      run_codegen(Domain, sp, mp)

      defresource DeltaPostG do
        postgres do
          table("delta_posts_g_new")
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
        end
      end

      defdomain([DeltaPostG])

      # First prompt: "Are you renaming delta_posts_g_old to delta_posts_g_new?"
      send(self(), {:mix_shell_input, :yes?, true})
      run_codegen(Domain, sp, mp)

      # The rename is emitted against the NEW table directory, with ops
      # containing a RenameTable for old→new.
      new_files = delta_files(sp, "delta_posts_g_new")
      assert length(new_files) >= 1

      all_ops =
        new_files
        |> Enum.flat_map(fn f -> read_delta(f).operations end)

      renames = Enum.filter(all_ops, &match?(%Operation.RenameTable{}, &1))

      assert Enum.any?(renames, fn op ->
               op.old_table == "delta_posts_g_old" and op.new_table == "delta_posts_g_new"
             end)
    end
  end

  # ===================================================================
  # Indexes, identities, constraints, references
  # ===================================================================

  describe "identities, indexes, constraints, references" do
    test "adding an identity (unique constraint) produces AddUniqueIndex ops", %{
      snapshot_path: sp,
      migration_path: mp
    } do
      defresource DeltaAuthor do
        postgres do
          table("delta_authors")
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:email, :string, public?: true)
        end

        identities do
          identity(:unique_email, [:email])
        end
      end

      defdomain([DeltaAuthor])
      run_codegen(Domain, sp, mp)

      [file] = delta_files(sp, "delta_authors")
      delta = read_delta(file)

      unique_indexes = ops_of_type(delta, Operation.AddUniqueIndex)

      assert Enum.any?(unique_indexes, fn op ->
               op.identity.name == :unique_email and op.identity.keys == [:email]
             end)

      # Reducer tracks the identity
      state = reduce_dir(sp, "delta_authors")
      assert Enum.any?(state.identities, &(&1.name == :unique_email))
    end

    test "adding a custom index produces an AddCustomIndex op", %{
      snapshot_path: sp,
      migration_path: mp
    } do
      defresource DeltaProduct do
        postgres do
          table("delta_products")
          repo(AshPostgres.TestRepo)

          custom_indexes do
            index(["title"], name: "delta_products_title_idx")
          end
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true)
        end
      end

      defdomain([DeltaProduct])
      run_codegen(Domain, sp, mp)

      [file] = delta_files(sp, "delta_products")
      delta = read_delta(file)

      custom_indexes = ops_of_type(delta, Operation.AddCustomIndex)

      assert Enum.any?(custom_indexes, fn op ->
               op.index.name == "delta_products_title_idx"
             end)

      state = reduce_dir(sp, "delta_products")
      assert Enum.any?(state.custom_indexes, &(&1.name == "delta_products_title_idx"))
    end

    test "adding a check constraint produces an AddCheckConstraint op", %{
      snapshot_path: sp,
      migration_path: mp
    } do
      defresource DeltaInvoice do
        postgres do
          table("delta_invoices")
          repo(AshPostgres.TestRepo)

          check_constraints do
            check_constraint(:amount, "positive_amount", check: "amount > 0")
          end
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:amount, :integer, public?: true)
        end
      end

      defdomain([DeltaInvoice])
      run_codegen(Domain, sp, mp)

      [file] = delta_files(sp, "delta_invoices")
      delta = read_delta(file)

      checks = ops_of_type(delta, Operation.AddCheckConstraint)

      assert Enum.any?(checks, fn op ->
               op.constraint.name == "positive_amount" and op.constraint.check == "amount > 0"
             end)

      state = reduce_dir(sp, "delta_invoices")
      assert Enum.any?(state.check_constraints, &(&1.name == "positive_amount"))
    end

    test "references (belongs_to) round-trip through delta encode + reduce", %{
      snapshot_path: sp,
      migration_path: mp
    } do
      defresource DeltaAuthor2 do
        postgres do
          table("delta_authors_2")
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
        end
      end

      defresource DeltaPost2Ref do
        postgres do
          table("delta_posts_with_ref")
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
        end

        relationships do
          belongs_to(:author, DeltaAuthor2, public?: true, allow_nil?: false)
        end
      end

      defdomain([DeltaAuthor2, DeltaPost2Ref])
      run_codegen(Domain, sp, mp)

      [delta_file] = delta_files(sp, "delta_posts_with_ref")
      delta = read_delta(delta_file)

      # The generator emits: AddAttribute (references=nil) → AlterAttribute
      # (adds the FK). So the reference info lives on the AlterAttribute op's
      # new_attribute, not the AddAttribute.
      adds = ops_of_type(delta, Operation.AddAttribute)
      assert Enum.any?(adds, &(&1.attribute.source == :author_id))

      alters = ops_of_type(delta, Operation.AlterAttribute)

      author_alter =
        Enum.find(alters, fn op -> op.new_attribute.source == :author_id end)

      assert author_alter != nil
      assert is_map(author_alter.new_attribute.references)
      assert author_alter.new_attribute.references.table == "delta_authors_2"
      assert author_alter.new_attribute.references.destination_attribute == :id

      # End-to-end: the reducer propagates the reference into state.
      state = reduce_dir(sp, "delta_posts_with_ref")

      reduced_ref =
        state.attributes
        |> Enum.find(&(&1.source == :author_id))
        |> Map.get(:references)

      assert reduced_ref.table == "delta_authors_2"
      assert reduced_ref.destination_attribute == :id
    end
  end

  # ===================================================================
  # Multi-tenancy
  # ===================================================================

  describe "multitenancy" do
    test "resources with context multitenancy store deltas under tenants/", %{
      snapshot_path: sp,
      migration_path: mp
    } do
      defresource DeltaTenantThing do
        postgres do
          table("delta_tenant_thing")
          repo(AshPostgres.TestRepo)
        end

        multitenancy do
          strategy(:context)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:name, :string, public?: true)
        end
      end

      defdomain([DeltaTenantThing])
      run_codegen(Domain, sp, mp)

      tenant_deltas = Path.wildcard("#{sp}/**/tenants/delta_tenant_thing/*.json")
      assert length(tenant_deltas) == 1

      delta = tenant_deltas |> List.first() |> read_delta()
      assert Codec.delta?(File.read!(List.first(tenant_deltas)))

      create_table = Enum.find(delta.operations, &match?(%Operation.CreateTable{}, &1))
      assert create_table.multitenancy.strategy == :context
    end

    test "attribute multitenancy persists the tenancy attribute in ops", %{
      snapshot_path: sp,
      migration_path: mp
    } do
      defresource DeltaOrg do
        postgres do
          table("delta_orgs")
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
        end
      end

      defresource DeltaMember do
        postgres do
          table("delta_members")
          repo(AshPostgres.TestRepo)
        end

        multitenancy do
          strategy(:attribute)
          attribute(:organization_id)
          global?(false)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:name, :string, public?: true)
        end

        relationships do
          belongs_to(:organization, DeltaOrg, public?: true, allow_nil?: false)
        end
      end

      defdomain([DeltaOrg, DeltaMember])
      run_codegen(Domain, sp, mp)

      [file] = delta_files(sp, "delta_members")
      delta = read_delta(file)

      create_table = Enum.find(delta.operations, &match?(%Operation.CreateTable{}, &1))
      assert create_table.multitenancy.strategy == :attribute
      assert create_table.multitenancy.attribute == :organization_id
    end
  end

  # ===================================================================
  # Parallel-branch merge scenarios (the whole point of deltas)
  # ===================================================================

  describe "parallel branches — merge-friendly deltas" do
    test "two deltas from separate 'branches' merge cleanly and reduce to combined state",
         %{snapshot_path: sp, migration_path: mp} do
      # Initial state (main branch): a resource with id + title
      defresource DeltaBranch1 do
        postgres do
          table("delta_branch_1")
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true)
        end
      end

      defdomain([DeltaBranch1])
      run_codegen(Domain, sp, mp)

      [initial_file] = delta_files(sp, "delta_branch_1")
      initial_delta = read_delta(initial_file)

      # Simulate Dev A's branch delta: adds :body
      delta_dir = Path.dirname(initial_file)

      dev_a_ops = [
        %Operation.AddAttribute{
          table: "delta_branch_1",
          schema: nil,
          multitenancy: @mt,
          old_multitenancy: @mt,
          attribute: %{
            source: :body,
            type: :text,
            default: "nil",
            size: nil,
            precision: nil,
            scale: nil,
            primary_key?: false,
            allow_nil?: true,
            generated?: false,
            references: nil
          }
        }
      ]

      # Simulate Dev B's branch delta: adds :tags
      dev_b_ops = [
        %Operation.AddAttribute{
          table: "delta_branch_1",
          schema: nil,
          multitenancy: @mt,
          old_multitenancy: @mt,
          attribute: %{
            source: :tags,
            type: :text,
            default: "nil",
            size: nil,
            precision: nil,
            scale: nil,
            primary_key?: false,
            allow_nil?: true,
            generated?: false,
            references: nil
          }
        }
      ]

      File.write!(
        Path.join(delta_dir, "20990101000000.json"),
        Codec.encode_delta(dev_a_ops, %{previous_hash: initial_delta.resulting_hash})
      )

      File.write!(
        Path.join(delta_dir, "20990101000001.json"),
        Codec.encode_delta(dev_b_ops, %{previous_hash: initial_delta.resulting_hash})
      )

      # Reducing should include id, title, body, tags — no conflict
      state = reduce_dir(sp, "delta_branch_1")
      sources = Enum.map(state.attributes, & &1.source) |> Enum.sort()
      assert :id in sources
      assert :title in sources
      assert :body in sources
      assert :tags in sources

      # Codegen on the post-merge main (resource reflects both additions)
      defresource DeltaBranch1 do
        postgres do
          table("delta_branch_1")
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true)
          attribute(:body, :string, public?: true)
          attribute(:tags, :string, public?: true)
        end
      end

      defdomain([DeltaBranch1])
      before_files = delta_files(sp, "delta_branch_1")
      before_migrations = migration_files(mp)

      run_codegen(Domain, sp, mp)

      # No new deltas, no new migrations — reducer already reflects the state
      # implied by both branch deltas.
      assert delta_files(sp, "delta_branch_1") == before_files
      assert migration_files(mp) == before_migrations
    end

    test "conflicting deltas (same attribute added in two 'branches') raise ConflictError",
         %{snapshot_path: sp, migration_path: mp} do
      defresource DeltaBranch2 do
        postgres do
          table("delta_branch_2")
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
        end
      end

      defdomain([DeltaBranch2])
      run_codegen(Domain, sp, mp)

      [initial_file] = delta_files(sp, "delta_branch_2")
      delta_dir = Path.dirname(initial_file)

      dup_op = fn type ->
        %Operation.AddAttribute{
          table: "delta_branch_2",
          schema: nil,
          multitenancy: @mt,
          old_multitenancy: @mt,
          attribute: %{
            source: :clashing_name,
            type: type,
            default: "nil",
            size: nil,
            precision: nil,
            scale: nil,
            primary_key?: false,
            allow_nil?: true,
            generated?: false,
            references: nil
          }
        }
      end

      File.write!(
        Path.join(delta_dir, "20990101000000.json"),
        Codec.encode_delta([dup_op.(:text)])
      )

      File.write!(
        Path.join(delta_dir, "20990101000001.json"),
        Codec.encode_delta([dup_op.(:integer)])
      )

      assert_raise Reducer.ConflictError,
                   ~r/AddAttribute: attribute :clashing_name already exists/,
                   fn ->
                     reduce_dir(sp, "delta_branch_2")
                   end
    end
  end

  # ===================================================================
  # Squash round-trip
  # ===================================================================

  describe "squash in delta mode" do
    test "generate → squash → generate yields no drift", %{snapshot_path: sp, migration_path: mp} do
      defresource DeltaSquashThing do
        postgres do
          table("delta_squash_thing")
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true)
        end
      end

      defdomain([DeltaSquashThing])
      run_codegen(Domain, sp, mp)

      # Two more changes → two more deltas
      defresource DeltaSquashThing do
        postgres do
          table("delta_squash_thing")
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true)
          attribute(:body, :string, public?: true)
        end
      end

      defdomain([DeltaSquashThing])
      run_codegen(Domain, sp, mp)

      defresource DeltaSquashThing do
        postgres do
          table("delta_squash_thing")
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true)
          attribute(:body, :string, public?: true)
          attribute(:tags, :string, public?: true)
        end
      end

      defdomain([DeltaSquashThing])
      run_codegen(Domain, sp, mp)

      files_before = delta_files(sp, "delta_squash_thing")
      assert length(files_before) == 3

      state_before = reduce_dir(sp, "delta_squash_thing")

      # Squash
      Mix.Tasks.AshPostgres.SquashSnapshots.run(["--snapshot-path", sp, "--quiet"])

      files_after = delta_files(sp, "delta_squash_thing")
      assert length(files_after) == 1

      state_after = reduce_dir(sp, "delta_squash_thing")

      # State preserved across the squash
      assert Enum.sort(Enum.map(state_before.attributes, & &1.source)) ==
               Enum.sort(Enum.map(state_after.attributes, & &1.source))

      # Codegen with unchanged resource should produce no new files or migrations
      migrations_before = migration_files(mp)

      run_codegen(Domain, sp, mp)

      assert delta_files(sp, "delta_squash_thing") == files_after
      assert migration_files(mp) == migrations_before
    end
  end

  # ===================================================================
  # Drop table opt-out
  # ===================================================================

  describe "drop table opt-out in delta mode" do
    test "answering 'no' to the drop prompt writes an OptOutDropTable delta", %{
      snapshot_path: sp,
      migration_path: mp
    } do
      # We need at least one resource to remain so the generator walks the
      # orphan-detection path (it short-circuits when no resources are
      # produced at all).
      defresource DeltaKeepMe do
        postgres do
          table("delta_keep_me")
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
        end
      end

      defresource DeltaDroppable do
        postgres do
          table("delta_droppable")
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
        end
      end

      defdomain([DeltaKeepMe, DeltaDroppable])
      run_codegen(Domain, sp, mp)

      # Remove the droppable resource; keep the other.
      defdomain([DeltaKeepMe])

      # Prompt: "Table delta_droppable no longer has a resource. Generate a
      # migration to DROP this table?" → answer "no".
      send(self(), {:mix_shell_input, :yes?, false})

      run_codegen(Domain, sp, mp)

      files = delta_files(sp, "delta_droppable")

      opt_outs =
        files
        |> Enum.flat_map(fn f -> read_delta(f).operations end)
        |> Enum.filter(&match?(%Operation.OptOutDropTable{}, &1))

      assert length(opt_outs) >= 1

      state = reduce_dir(sp, "delta_droppable")
      assert state.drop_table_opted_out == true
    end
  end

  # ===================================================================
  # migrate_snapshots: legacy → delta, then delta codegen stays quiet
  # ===================================================================

  describe "migrate_snapshots" do
    test "converting a legacy repo then running codegen in delta mode emits no migration",
         %{snapshot_path: sp, migration_path: mp} do
      # Step 1: generate in legacy full-state mode.
      defresource DeltaMigrated do
        postgres do
          table("delta_migrated")
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true)
        end
      end

      defdomain([DeltaMigrated])

      MigrationGenerator.generate(Domain,
        snapshot_path: sp,
        migration_path: mp,
        quiet: true,
        format: false,
        auto_name: true,
        snapshot_format: :full
      )

      files = delta_files(sp, "delta_migrated")
      assert length(files) == 1
      refute Codec.delta?(File.read!(List.first(files)))

      migrations_before = migration_files(mp)

      # Step 2: migrate snapshots to v2.
      Mix.Tasks.AshPostgres.MigrateSnapshots.run(["--snapshot-path", sp, "--quiet"])

      post_migrate = delta_files(sp, "delta_migrated")
      assert length(post_migrate) == 1
      assert Codec.delta?(File.read!(List.first(post_migrate)))

      # Step 3: run codegen in delta mode with NO resource changes — should be a
      # no-op (no new deltas, no new migrations).
      run_codegen(Domain, sp, mp)

      assert delta_files(sp, "delta_migrated") == post_migrate
      assert migration_files(mp) == migrations_before
    end
  end

  # ===================================================================
  # Migration-content parity — delta mode must emit the same migration
  # files as full mode. If this breaks, the feature is wrong.
  # ===================================================================

  describe "migration-content parity (delta vs full)" do
    setup %{tmp_dir: tmp_dir} do
      full_root = Path.join(tmp_dir, "full")
      delta_root = Path.join(tmp_dir, "delta")
      File.mkdir_p!(full_root)
      File.mkdir_p!(delta_root)

      %{
        full_sp: Path.join(full_root, "snapshots"),
        full_mp: Path.join(full_root, "migrations"),
        delta_sp: Path.join(delta_root, "snapshots"),
        delta_mp: Path.join(delta_root, "migrations")
      }
    end

    defp migration_body_only(path) do
      # Strip the defmodule header (whose name includes a counter that differs
      # between runs) and trailing whitespace. What's left is the `def up do`,
      # `def down do`, and `@moduledoc` — all of which should be byte-identical
      # between full and delta modes for the same resource definition.
      path
      |> File.read!()
      |> String.split("\n")
      |> Enum.reject(fn line ->
        trimmed = String.trim_leading(line)
        String.starts_with?(trimmed, "defmodule ")
      end)
      |> Enum.join("\n")
      |> String.replace(~r/\s+$/, "")
      |> String.trim()
    end

    defp resource_migration_content(mp) do
      mp
      |> migration_files()
      |> Enum.map(&migration_body_only/1)
    end

    test "creating a resource produces identical migrations in full and delta modes", %{
      full_sp: full_sp,
      full_mp: full_mp,
      delta_sp: delta_sp,
      delta_mp: delta_mp,
      tmp_dir: tmp_dir
    } do
      defresource DeltaParity1 do
        postgres do
          table("delta_parity_1")
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true)
          attribute(:body, :string, public?: true)
        end

        identities do
          identity(:unique_title, [:title])
        end
      end

      defdomain([DeltaParity1])

      MigrationGenerator.generate(Domain,
        snapshot_path: full_sp,
        migration_path: full_mp,
        tenant_migration_path: Path.join(tmp_dir, "full_tenant"),
        quiet: true,
        format: false,
        auto_name: true,
        snapshot_format: :full
      )

      MigrationGenerator.generate(Domain,
        snapshot_path: delta_sp,
        migration_path: delta_mp,
        tenant_migration_path: Path.join(tmp_dir, "delta_tenant"),
        quiet: true,
        format: false,
        auto_name: true,
        snapshot_format: :delta
      )

      assert resource_migration_content(full_mp) == resource_migration_content(delta_mp),
             "Migration content diverged between full and delta modes"
    end

    test "evolving a resource (add + alter + index) produces identical migrations", %{
      full_sp: full_sp,
      full_mp: full_mp,
      delta_sp: delta_sp,
      delta_mp: delta_mp,
      tmp_dir: tmp_dir
    } do
      initial = fn mod ->
        Code.compiler_options(ignore_module_conflict: true)

        Module.create(
          mod,
          quote do
            use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

            postgres do
              table("delta_parity_2")
              repo(AshPostgres.TestRepo)
            end

            actions do
              defaults([:create, :read, :update, :destroy])
            end

            attributes do
              uuid_primary_key(:id)
              attribute(:title, :string, public?: true)
            end
          end,
          __ENV__
        )

        Code.compiler_options(ignore_module_conflict: false)
      end

      evolved = fn mod ->
        Code.compiler_options(ignore_module_conflict: true)

        Module.create(
          mod,
          quote do
            use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

            postgres do
              table("delta_parity_2")
              repo(AshPostgres.TestRepo)
            end

            actions do
              defaults([:create, :read, :update, :destroy])
            end

            attributes do
              uuid_primary_key(:id)
              attribute(:title, :string, public?: true, allow_nil?: false)
              attribute(:body, :string, public?: true)
            end

            identities do
              identity(:unique_title, [:title])
            end
          end,
          __ENV__
        )

        Code.compiler_options(ignore_module_conflict: false)
      end

      run = fn sp, mp, tenant, format ->
        defdomain([DeltaParity2])

        MigrationGenerator.generate(Domain,
          snapshot_path: sp,
          migration_path: mp,
          tenant_migration_path: tenant,
          quiet: true,
          format: false,
          auto_name: true,
          snapshot_format: format
        )
      end

      full_tenant = Path.join(tmp_dir, "full_tenant")
      delta_tenant = Path.join(tmp_dir, "delta_tenant")

      initial.(DeltaParity2)
      run.(full_sp, full_mp, full_tenant, :full)
      run.(delta_sp, delta_mp, delta_tenant, :delta)

      evolved.(DeltaParity2)
      run.(full_sp, full_mp, full_tenant, :full)
      run.(delta_sp, delta_mp, delta_tenant, :delta)

      assert resource_migration_content(full_mp) == resource_migration_content(delta_mp),
             "Migration content diverged between full and delta modes after resource evolution"
    end
  end

  # ===================================================================
  # Schema-prefixed tables
  # ===================================================================

  describe "schema-prefixed tables" do
    test "delta files for a schema-prefixed resource land under {schema}.{table}/", %{
      snapshot_path: sp,
      migration_path: mp
    } do
      defresource DeltaSchemaThing do
        postgres do
          table("delta_schema_thing")
          schema("example")
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:name, :string, public?: true)
        end
      end

      defdomain([DeltaSchemaThing])
      run_codegen(Domain, sp, mp)

      # File should be at {sp}/test_repo/example.delta_schema_thing/*.json
      delta_path_glob = "#{sp}/**/example.delta_schema_thing/*.json"
      files = Path.wildcard(delta_path_glob)

      assert length(files) == 1

      delta = List.first(files) |> read_delta()

      create_table = Enum.find(delta.operations, &match?(%Operation.CreateTable{}, &1))
      assert create_table.schema == "example"
      assert create_table.table == "delta_schema_thing"

      # Reducer reads the schema-prefixed directory
      snapshot = %{
        table: "delta_schema_thing",
        schema: "example",
        repo: AshPostgres.TestRepo,
        multitenancy: @mt
      }

      opts = %MigrationGenerator{snapshot_path: sp, dev: false, quiet: true}
      state = Reducer.load_reduced_state(snapshot, opts)
      assert state.schema == "example"
      assert Enum.any?(state.attributes, &(&1.source == :id))
      assert Enum.any?(state.attributes, &(&1.source == :name))
    end
  end

  # ===================================================================
  # `--dev` flag
  # ===================================================================

  describe "--dev flag" do
    test "delta codegen with dev: true writes _dev.json files", %{
      snapshot_path: sp,
      migration_path: mp
    } do
      defresource DeltaDevThing do
        postgres do
          table("delta_dev_thing")
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:name, :string, public?: true)
        end
      end

      defdomain([DeltaDevThing])
      run_codegen(Domain, sp, mp, dev: true)

      files = Path.wildcard("#{sp}/**/delta_dev_thing/*.json")
      assert length(files) == 1

      [file] = files
      assert String.ends_with?(file, "_dev.json")

      # The _dev delta is still a valid v2 delta.
      assert Codec.delta?(File.read!(file))

      # Reducer in dev mode loads it.
      snapshot = %{
        table: "delta_dev_thing",
        schema: nil,
        repo: AshPostgres.TestRepo,
        multitenancy: @mt
      }

      opts = %MigrationGenerator{snapshot_path: sp, dev: true, quiet: true}
      state = Reducer.load_reduced_state(snapshot, opts)

      assert Enum.any?(state.attributes, &(&1.source == :name))

      # Reducer in non-dev mode ignores the _dev file.
      opts_non_dev = %{opts | dev: false}
      assert Reducer.load_reduced_state(snapshot, opts_non_dev) == nil
    end
  end
end
