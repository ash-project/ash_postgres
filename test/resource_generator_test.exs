# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.ResourceGeenratorTests do
  use AshPostgres.RepoCase, async: false

  import Igniter.Test

  defp assert_creates_normalized(igniter, path, expected) do
    assert_creates(igniter, path, fn actual ->
      actual = String.replace(actual, "\r\n", "\n")
      expected = String.replace(expected, "\r\n", "\n")

      assert actual == expected
    end)
  end

  setup do
    AshPostgres.TestRepo.query!("DROP TABLE IF EXISTS example_table")

    AshPostgres.TestRepo.query!("CREATE TABLE example_table (
      id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
      name VARCHAR(255),
      age INTEGER,
      email VARCHAR(255)
    )")

    :ok
  end

  test "a resource is generated from a table" do
    test_project()
    |> Igniter.compose_task("ash_postgres.gen.resources", [
      "MyApp.Accounts",
      "--tables",
      "example_table",
      "--yes",
      "--repo",
      "AshPostgres.TestRepo"
    ])
    |> assert_creates_normalized("lib/my_app/accounts/example_table.ex", """
    defmodule MyApp.Accounts.ExampleTable do
      use Ash.Resource,
        domain: MyApp.Accounts,
        data_layer: AshPostgres.DataLayer

      actions do
        defaults([:read, :destroy, create: :*, update: :*])
      end

      postgres do
        table("example_table")
        repo(AshPostgres.TestRepo)
      end

      attributes do
        uuid_primary_key :id do
          public?(true)
        end

        attribute :name, :string do
          public?(true)
        end

        attribute :age, :integer do
          public?(true)
        end

        attribute :email, :string do
          sensitive?(true)
          public?(true)
        end
      end
    end
    """)
  end

  test "a resource is generated from a table without a primary key" do
    AshPostgres.TestRepo.query!("DROP TABLE IF EXISTS pk_less_table")

    AshPostgres.TestRepo.query!("CREATE TABLE pk_less_table (
      name VARCHAR(255),
      value INTEGER
    )")

    test_project()
    |> Igniter.compose_task("ash_postgres.gen.resources", [
      "MyApp.Accounts",
      "--tables",
      "pk_less_table",
      "--yes",
      "--repo",
      "AshPostgres.TestRepo"
    ])
    |> assert_creates_normalized("lib/my_app/accounts/pk_less_table.ex", """
    defmodule MyApp.Accounts.PkLessTable do
      use Ash.Resource,
        domain: MyApp.Accounts,
        data_layer: AshPostgres.DataLayer

      resource do
        # WARNING: Configured to bypass missing primary key.
        # Add primary_key?: true to your attributes/relationships and remove this block.
        require_primary_key?(false)
      end

      actions do
        # WARNING: No primary key detected.
        # :update and :destroy actions require a primary key to safely identify records.
        defaults([:read, create: :*])
      end

      postgres do
        table("pk_less_table")
        repo(AshPostgres.TestRepo)
      end

      attributes do
        attribute :name, :string do
          public?(true)
        end

        attribute :value, :integer do
          public?(true)
        end
      end
    end
    """)
  end

  test "a resource is generated from a VIEW when --include-views is set" do
    AshPostgres.TestRepo.query!("DROP VIEW IF EXISTS example_view")
    AshPostgres.TestRepo.query!("DROP TABLE IF EXISTS example_view_source")

    AshPostgres.TestRepo.query!("CREATE TABLE example_view_source (
      id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
      amount INTEGER NOT NULL
    )")

    AshPostgres.TestRepo.query!(
      "CREATE VIEW example_view AS SELECT id, amount * 2 AS doubled FROM example_view_source"
    )

    test_project()
    |> Igniter.compose_task("ash_postgres.gen.resources", [
      "MyApp.Accounts",
      "--tables",
      "example_view",
      "--yes",
      "--repo",
      "AshPostgres.TestRepo",
      "--include-views"
    ])
    |> assert_creates_normalized("lib/my_app/accounts/example_view.ex", """
    defmodule MyApp.Accounts.ExampleView do
      use Ash.Resource,
        domain: MyApp.Accounts,
        data_layer: AshPostgres.DataLayer

      resource do
        # WARNING: Configured to bypass missing primary key.
        # Add primary_key?: true to your attributes/relationships and remove this block.
        require_primary_key?(false)
      end

      actions do
        # WARNING: Generated from a PostgreSQL VIEW.
        # Views are read-only; only the :read default action is safe.
        defaults([:read])
      end

      postgres do
        table("example_view")
        repo(AshPostgres.TestRepo)

        # NOTE: Source is a PostgreSQL VIEW, not a base table.
        # migrate? false prevents Ash from trying to manage its schema.
        # TODO: Migrations need to be handled manually for views.
        migrate?(false)
      end

      attributes do
        attribute :id, :uuid do
          public?(true)
        end

        attribute :doubled, :integer do
          public?(true)
        end
      end
    end
    """)
  end

  test "a resource is generated from a MATERIALIZED VIEW when --include-views is set" do
    AshPostgres.TestRepo.query!("DROP MATERIALIZED VIEW IF EXISTS example_mv")
    AshPostgres.TestRepo.query!("DROP TABLE IF EXISTS example_mv_source")

    AshPostgres.TestRepo.query!("CREATE TABLE example_mv_source (
      id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
      category VARCHAR(64) NOT NULL,
      amount INTEGER NOT NULL
    )")

    AshPostgres.TestRepo.query!("""
    CREATE MATERIALIZED VIEW example_mv AS
    SELECT id, category, amount * 2 AS doubled FROM example_mv_source
    """)

    AshPostgres.TestRepo.query!("CREATE UNIQUE INDEX example_mv_id_unique ON example_mv(id)")

    test_project()
    |> Igniter.compose_task("ash_postgres.gen.resources", [
      "MyApp.Accounts",
      "--tables",
      "example_mv",
      "--yes",
      "--repo",
      "AshPostgres.TestRepo",
      "--include-views"
    ])
    |> assert_creates_normalized("lib/my_app/accounts/example_mv.ex", """
    defmodule MyApp.Accounts.ExampleMv do
      use Ash.Resource,
        domain: MyApp.Accounts,
        data_layer: AshPostgres.DataLayer

      resource do
        # WARNING: Configured to bypass missing primary key.
        # Add primary_key?: true to your attributes/relationships and remove this block.
        require_primary_key?(false)
      end

      actions do
        # WARNING: Generated from a PostgreSQL MATERIALIZED VIEW.
        # Views are read-only; only the :read default action is safe.
        defaults([:read])
      end

      postgres do
        table("example_mv")
        repo(AshPostgres.TestRepo)

        # NOTE: Source is a PostgreSQL MATERIALIZED VIEW, not a base table.
        # migrate? false prevents Ash from trying to manage its schema.
        # TODO: Migrations need to be handled manually for views.
        migrate?(false)

        identity_index_names(id_unique: "example_mv_id_unique")
      end

      attributes do
        attribute :id, :uuid do
          public?(true)
        end

        attribute :category, :string do
          public?(true)
        end

        attribute :doubled, :integer do
          public?(true)
        end
      end

      identities do
        identity(:id_unique, [:id])
      end
    end
    """)
  end

  test "a MATERIALIZED VIEW is NOT generated without --include-views" do
    AshPostgres.TestRepo.query!("DROP MATERIALIZED VIEW IF EXISTS skip_mv")
    AshPostgres.TestRepo.query!("DROP TABLE IF EXISTS skip_mv_source")

    AshPostgres.TestRepo.query!("CREATE TABLE skip_mv_source (
      id UUID DEFAULT uuid_generate_v4() PRIMARY KEY
    )")

    AshPostgres.TestRepo.query!(
      "CREATE MATERIALIZED VIEW skip_mv AS SELECT id FROM skip_mv_source"
    )

    igniter =
      test_project()
      |> Igniter.compose_task("ash_postgres.gen.resources", [
        "MyApp.Accounts",
        "--tables",
        "skip_mv",
        "--yes",
        "--repo",
        "AshPostgres.TestRepo"
      ])

    refute Rewrite.has_source?(igniter.rewrite, "lib/my_app/accounts/skip_mv.ex")
  end

  test "a VIEW is NOT generated without --include-views" do
    AshPostgres.TestRepo.query!("DROP VIEW IF EXISTS skip_view")
    AshPostgres.TestRepo.query!("DROP TABLE IF EXISTS skip_view_source")

    AshPostgres.TestRepo.query!("CREATE TABLE skip_view_source (
      id UUID DEFAULT uuid_generate_v4() PRIMARY KEY
    )")

    AshPostgres.TestRepo.query!("CREATE VIEW skip_view AS SELECT id FROM skip_view_source")

    igniter =
      test_project()
      |> Igniter.compose_task("ash_postgres.gen.resources", [
        "MyApp.Accounts",
        "--tables",
        "skip_view",
        "--yes",
        "--repo",
        "AshPostgres.TestRepo"
      ])

    refute Rewrite.has_source?(igniter.rewrite, "lib/my_app/accounts/skip_view.ex")
  end

  test "a resource is generated from a table in a non-public schema with foreign keys and indexes" do
    AshPostgres.TestRepo.query!("CREATE SCHEMA IF NOT EXISTS inventory")

    AshPostgres.TestRepo.query!("DROP TABLE IF EXISTS inventory.products CASCADE")
    AshPostgres.TestRepo.query!("DROP TABLE IF EXISTS inventory.warehouses CASCADE")

    AshPostgres.TestRepo.query!("""
    CREATE TABLE inventory.warehouses (
      id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
      name VARCHAR(255) NOT NULL,
      location VARCHAR(255)
    )
    """)

    AshPostgres.TestRepo.query!("CREATE INDEX warehouses_name_idx ON inventory.warehouses(name)")

    AshPostgres.TestRepo.query!("""
    CREATE TABLE inventory.products (
      id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
      name VARCHAR(255) NOT NULL,
      warehouse_id UUID REFERENCES inventory.warehouses(id) ON DELETE CASCADE,
      quantity INTEGER
    )
    """)

    AshPostgres.TestRepo.query!(
      "CREATE INDEX products_warehouse_id_idx ON inventory.products(warehouse_id)"
    )

    test_project()
    |> Igniter.compose_task("ash_postgres.gen.resources", [
      "MyApp.Inventory",
      "--tables",
      "inventory.warehouses,inventory.products",
      "--yes",
      "--repo",
      "AshPostgres.TestRepo"
    ])
    |> assert_creates_normalized("lib/my_app/inventory/warehouse.ex", """
    defmodule MyApp.Inventory.Warehouse do
      use Ash.Resource,
        domain: MyApp.Inventory,
        data_layer: AshPostgres.DataLayer

      actions do
        defaults([:read, :destroy, create: :*, update: :*])
      end

      postgres do
        table("warehouses")
        repo(AshPostgres.TestRepo)
        schema("inventory")
      end

      attributes do
        uuid_primary_key :id do
          public?(true)
        end

        attribute :name, :string do
          allow_nil?(false)
          public?(true)
        end

        attribute :location, :string do
          public?(true)
        end
      end

      relationships do
        has_many :products, MyApp.Inventory.Product do
          public?(true)
        end
      end
    end
    """)
    |> assert_creates_normalized("lib/my_app/inventory/product.ex", """
    defmodule MyApp.Inventory.Product do
      use Ash.Resource,
        domain: MyApp.Inventory,
        data_layer: AshPostgres.DataLayer

      actions do
        defaults([:read, :destroy, create: :*, update: :*])
      end

      postgres do
        table("products")
        repo(AshPostgres.TestRepo)
        schema("inventory")

        references do
          reference :warehouse do
            on_delete(:delete)
          end
        end
      end

      attributes do
        uuid_primary_key :id do
          public?(true)
        end

        attribute :name, :string do
          allow_nil?(false)
          public?(true)
        end

        attribute :quantity, :integer do
          public?(true)
        end
      end

      relationships do
        belongs_to :warehouse, MyApp.Inventory.Warehouse do
          public?(true)
        end
      end
    end
    """)
  end

  test "resolves has_many name conflicts using suggested names when --yes is set" do
    AshPostgres.TestRepo.query!("DROP TABLE IF EXISTS conflict_posts CASCADE")
    AshPostgres.TestRepo.query!("DROP TABLE IF EXISTS conflict_authors CASCADE")

    AshPostgres.TestRepo.query!("""
    CREATE TABLE conflict_authors (
      id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
      name VARCHAR(255)
    )
    """)

    AshPostgres.TestRepo.query!("""
    CREATE TABLE conflict_posts (
      id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
      title VARCHAR(255),
      created_by_id UUID REFERENCES conflict_authors(id),
      updated_by_id UUID REFERENCES conflict_authors(id)
    )
    """)

    igniter =
      test_project()
      |> Igniter.compose_task("ash_postgres.gen.resources", [
        "MyApp.Accounts",
        "--tables",
        "conflict_authors,conflict_posts",
        "--yes",
        "--repo",
        "AshPostgres.TestRepo"
      ])

    author_source =
      Rewrite.source!(igniter.rewrite, "lib/my_app/accounts/conflict_author.ex")

    author_content = Rewrite.Source.get(author_source, :content)

    assert author_content =~ ":created_by_conflict_posts"
    assert author_content =~ ":updated_by_conflict_posts"
    refute author_content =~ "has_many :conflict_posts,"
  end

  describe "--fragments option" do
    @describetag :fragments

    test "generates resource and fragment files when resource does not exist" do
      test_project()
      |> Igniter.compose_task("ash_postgres.gen.resources", [
        "MyApp.Accounts",
        "--tables",
        "example_table",
        "--yes",
        "--repo",
        "AshPostgres.TestRepo",
        "--fragments"
      ])
      |> assert_creates_normalized("lib/my_app/accounts/example_table.ex", """
      defmodule MyApp.Accounts.ExampleTable do
        use Ash.Resource,
          domain: MyApp.Accounts,
          data_layer: AshPostgres.DataLayer,
          fragments: [MyApp.Accounts.ExampleTable.Model]

        actions do
          defaults([:read, :destroy, create: :*, update: :*])
        end

        postgres do
          table("example_table")
          repo(AshPostgres.TestRepo)
        end
      end
      """)
      |> assert_creates_normalized("lib/my_app/accounts/example_table/model.ex", """
      defmodule MyApp.Accounts.ExampleTable.Model do
        use Spark.Dsl.Fragment,
          of: Ash.Resource

        attributes do
          uuid_primary_key :id do
            public?(true)
          end

          attribute :name, :string do
            public?(true)
          end

          attribute :age, :integer do
            public?(true)
          end

          attribute :email, :string do
            sensitive?(true)
            public?(true)
          end
        end
      end
      """)
    end

    @tag :fragments
    test "generates fragment with relationships" do
      AshPostgres.TestRepo.query!("CREATE SCHEMA IF NOT EXISTS fragtest")

      AshPostgres.TestRepo.query!("DROP TABLE IF EXISTS fragtest.orders CASCADE")
      AshPostgres.TestRepo.query!("DROP TABLE IF EXISTS fragtest.customers CASCADE")

      AshPostgres.TestRepo.query!("""
      CREATE TABLE fragtest.customers (
        id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
        name VARCHAR(255) NOT NULL
      )
      """)

      AshPostgres.TestRepo.query!("""
      CREATE TABLE fragtest.orders (
        id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
        customer_id UUID REFERENCES fragtest.customers(id),
        total INTEGER
      )
      """)

      test_project()
      |> Igniter.compose_task("ash_postgres.gen.resources", [
        "MyApp.Sales",
        "--tables",
        "fragtest.customers,fragtest.orders",
        "--yes",
        "--repo",
        "AshPostgres.TestRepo",
        "--fragments"
      ])
      |> assert_creates_normalized("lib/my_app/sales/customer.ex", """
      defmodule MyApp.Sales.Customer do
        use Ash.Resource,
          domain: MyApp.Sales,
          data_layer: AshPostgres.DataLayer,
          fragments: [MyApp.Sales.Customer.Model]

        actions do
          defaults([:read, :destroy, create: :*, update: :*])
        end

        postgres do
          table("customers")
          repo(AshPostgres.TestRepo)
          schema("fragtest")
        end
      end
      """)
      |> assert_creates_normalized("lib/my_app/sales/customer/model.ex", """
      defmodule MyApp.Sales.Customer.Model do
        use Spark.Dsl.Fragment,
          of: Ash.Resource

        attributes do
          uuid_primary_key :id do
            public?(true)
          end

          attribute :name, :string do
            allow_nil?(false)
            public?(true)
          end
        end

        relationships do
          has_many :orders, MyApp.Sales.Order do
            public?(true)
          end
        end
      end
      """)
      |> assert_creates_normalized("lib/my_app/sales/order/model.ex", """
      defmodule MyApp.Sales.Order.Model do
        use Spark.Dsl.Fragment,
          of: Ash.Resource

        attributes do
          uuid_primary_key :id do
            public?(true)
          end

          attribute :total, :integer do
            public?(true)
          end
        end

        relationships do
          belongs_to :customer, MyApp.Sales.Customer do
            public?(true)
          end
        end
      end
      """)
    end

    @tag :fragments
    test "only regenerates fragment when resource already exists" do
      # Create a pre-existing resource file with user customization
      existing_resource = """
      defmodule MyApp.Accounts.ExampleTable do
        use Ash.Resource,
          domain: MyApp.Accounts,
          data_layer: AshPostgres.DataLayer,
          fragments: [MyApp.Accounts.ExampleTable.Model]

        # User customization that should be preserved
        actions do
          defaults([:read, :destroy, create: :*, update: :*])

          create :custom_create do
            accept [:name]
          end
        end

        postgres do
          table("example_table")
          repo(AshPostgres.TestRepo)
        end
      end
      """

      test_project(
        files: %{
          "lib/my_app/accounts/example_table.ex" => existing_resource
        }
      )
      |> Igniter.compose_task("ash_postgres.gen.resources", [
        "MyApp.Accounts",
        "--tables",
        "example_table",
        "--yes",
        "--repo",
        "AshPostgres.TestRepo",
        "--fragments"
      ])
      # Resource should NOT be modified (it already exists)
      |> assert_unchanged("lib/my_app/accounts/example_table.ex")
      # Fragment should still be created
      |> assert_creates_normalized("lib/my_app/accounts/example_table/model.ex", """
      defmodule MyApp.Accounts.ExampleTable.Model do
        use Spark.Dsl.Fragment,
          of: Ash.Resource

        attributes do
          uuid_primary_key :id do
            public?(true)
          end

          attribute :name, :string do
            public?(true)
          end

          attribute :age, :integer do
            public?(true)
          end

          attribute :email, :string do
            sensitive?(true)
            public?(true)
          end
        end
      end
      """)
    end
  end

  defp file_content(igniter, path) do
    source = igniter.rewrite.sources[path]
    assert source, "Expected #{inspect(path)} to be created"
    Rewrite.Source.get(source, :content)
  end

  describe "many_to_many relationship generation" do
    setup do
      AshPostgres.TestRepo.query!("DROP TABLE IF EXISTS article_tags CASCADE")
      AshPostgres.TestRepo.query!("DROP TABLE IF EXISTS articles CASCADE")
      AshPostgres.TestRepo.query!("DROP TABLE IF EXISTS topics CASCADE")

      AshPostgres.TestRepo.query!("""
      CREATE TABLE articles (
        id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
        title VARCHAR(255)
      )
      """)

      AshPostgres.TestRepo.query!("""
      CREATE TABLE topics (
        id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
        name VARCHAR(255)
      )
      """)

      AshPostgres.TestRepo.query!("""
      CREATE TABLE article_tags (
        article_id UUID NOT NULL REFERENCES articles(id),
        topic_id UUID NOT NULL REFERENCES topics(id),
        PRIMARY KEY (article_id, topic_id)
      )
      """)

      :ok
    end

    test "generates has_many to the join table alongside many_to_many to the destination" do
      test_project()
      |> Igniter.compose_task("ash_postgres.gen.resources", [
        "MyApp.Blog",
        "--tables",
        "articles,topics,article_tags",
        "--yes",
        "--repo",
        "AshPostgres.TestRepo"
      ])
      |> assert_creates_normalized("lib/my_app/blog/article.ex", """
      defmodule MyApp.Blog.Article do
        use Ash.Resource,
          domain: MyApp.Blog,
          data_layer: AshPostgres.DataLayer

        actions do
          defaults([:read, :destroy, create: :*, update: :*])
        end

        postgres do
          table("articles")
          repo(AshPostgres.TestRepo)
        end

        attributes do
          uuid_primary_key :id do
            public?(true)
          end

          attribute :title, :string do
            public?(true)
          end
        end

        relationships do
          has_many :article_tags, MyApp.Blog.ArticleTag do
            public?(true)
          end

          many_to_many :topics, MyApp.Blog.Topic do
            through(MyApp.Blog.ArticleTag)
            join_relationship(:article_tags)
            public?(true)
          end
        end
      end
      """)
      |> assert_creates_normalized("lib/my_app/blog/topic.ex", """
      defmodule MyApp.Blog.Topic do
        use Ash.Resource,
          domain: MyApp.Blog,
          data_layer: AshPostgres.DataLayer

        actions do
          defaults([:read, :destroy, create: :*, update: :*])
        end

        postgres do
          table("topics")
          repo(AshPostgres.TestRepo)
        end

        attributes do
          uuid_primary_key :id do
            public?(true)
          end

          attribute :name, :string do
            public?(true)
          end
        end

        relationships do
          has_many :article_tags, MyApp.Blog.ArticleTag do
            public?(true)
          end

          many_to_many :articles, MyApp.Blog.Article do
            through(MyApp.Blog.ArticleTag)
            join_relationship(:article_tags)
            public?(true)
          end
        end
      end
      """)
    end

    test "join table resource itself gets only belongs_to relationships" do
      igniter =
        test_project()
        |> Igniter.compose_task("ash_postgres.gen.resources", [
          "MyApp.Blog",
          "--tables",
          "articles,topics,article_tags",
          "--yes",
          "--repo",
          "AshPostgres.TestRepo"
        ])

      content = file_content(igniter, "lib/my_app/blog/article_tag.ex")
      assert content =~ "belongs_to :article, MyApp.Blog.Article"
      assert content =~ "belongs_to :topic, MyApp.Blog.Topic"
      # Composite PK lives on the FK columns; each belongs_to must declare primary_key? true
      # so Ash recognizes the composite PK and does not raise VerifyPrimaryKeyPresent.
      assert content =~ "primary_key?(true)"
      refute content =~ "many_to_many"
      refute content =~ "has_many"
    end

    test "omits source/dest join attributes when they match the module-name defaults" do
      igniter =
        test_project()
        |> Igniter.compose_task("ash_postgres.gen.resources", [
          "MyApp.Blog",
          "--tables",
          "articles,topics,article_tags",
          "--yes",
          "--repo",
          "AshPostgres.TestRepo"
        ])

      content = file_content(igniter, "lib/my_app/blog/article.ex")
      # article_id and topic_id match defaults → options omitted
      refute content =~ "source_attribute_on_join_resource"
      refute content =~ "destination_attribute_on_join_resource"
    end

    test "emits source/dest join attributes when FK column names differ from module-name defaults" do
      AshPostgres.TestRepo.query!("DROP TABLE IF EXISTS article_mappings CASCADE")

      AshPostgres.TestRepo.query!("""
      CREATE TABLE article_mappings (
        the_article UUID NOT NULL REFERENCES articles(id),
        the_topic   UUID NOT NULL REFERENCES topics(id),
        PRIMARY KEY (the_article, the_topic)
      )
      """)

      igniter =
        test_project()
        |> Igniter.compose_task("ash_postgres.gen.resources", [
          "MyApp.Blog",
          "--tables",
          "articles,topics,article_mappings",
          "--yes",
          "--repo",
          "AshPostgres.TestRepo"
        ])

      content = file_content(igniter, "lib/my_app/blog/article.ex")
      assert content =~ "source_attribute_on_join_resource(:the_article)"
      assert content =~ "destination_attribute_on_join_resource(:the_topic)"
    end

    test "detects many_to_many when the join table has a unique index over the FK columns instead of a composite primary key" do
      # Hibernate / legacy schemas often use UNIQUE(a, b) instead of PRIMARY KEY (a, b).
      AshPostgres.TestRepo.query!("DROP TABLE IF EXISTS article_uq_tags CASCADE")

      AshPostgres.TestRepo.query!("""
      CREATE TABLE article_uq_tags (
        article_id UUID NOT NULL REFERENCES articles(id),
        topic_id   UUID NOT NULL REFERENCES topics(id)
      )
      """)

      AshPostgres.TestRepo.query!(
        "CREATE UNIQUE INDEX article_uq_tags_uniq ON article_uq_tags (article_id, topic_id)"
      )

      igniter =
        test_project()
        |> Igniter.compose_task("ash_postgres.gen.resources", [
          "MyApp.Blog",
          "--tables",
          "articles,topics,article_uq_tags",
          "--yes",
          "--repo",
          "AshPostgres.TestRepo"
        ])

      article_content = file_content(igniter, "lib/my_app/blog/article.ex")
      assert article_content =~ "many_to_many :topics, MyApp.Blog.Topic"
      assert article_content =~ "has_many :article_uq_tags"

      topic_content = file_content(igniter, "lib/my_app/blog/topic.ex")
      assert topic_content =~ "many_to_many :articles, MyApp.Blog.Article"
      assert topic_content =~ "has_many :article_uq_tags"
    end

    test "does not generate many_to_many when the join table has its own surrogate primary key" do
      AshPostgres.TestRepo.query!("DROP TABLE IF EXISTS article_labels CASCADE")

      AshPostgres.TestRepo.query!("""
      CREATE TABLE article_labels (
        id         UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
        article_id UUID NOT NULL REFERENCES articles(id),
        topic_id   UUID NOT NULL REFERENCES topics(id)
      )
      """)

      igniter =
        test_project()
        |> Igniter.compose_task("ash_postgres.gen.resources", [
          "MyApp.Blog",
          "--tables",
          "articles,topics,article_labels",
          "--yes",
          "--repo",
          "AshPostgres.TestRepo"
        ])

      article_content = file_content(igniter, "lib/my_app/blog/article.ex")
      assert article_content =~ "has_many :article_labels"
      refute article_content =~ "many_to_many"

      topic_content = file_content(igniter, "lib/my_app/blog/topic.ex")
      assert topic_content =~ "has_many :article_labels"
      refute topic_content =~ "many_to_many"
    end

    test "does not generate many_to_many for self-referential join tables" do
      # Both FKs point to the same table → join_table? returns false because
      # fk_tables has length 1, not 2
      AshPostgres.TestRepo.query!("DROP TABLE IF EXISTS article_links CASCADE")

      AshPostgres.TestRepo.query!("""
      CREATE TABLE article_links (
        source_id UUID NOT NULL REFERENCES articles(id),
        target_id UUID NOT NULL REFERENCES articles(id),
        PRIMARY KEY (source_id, target_id)
      )
      """)

      igniter =
        test_project()
        |> Igniter.compose_task("ash_postgres.gen.resources", [
          "MyApp.Blog",
          "--tables",
          "articles,article_links",
          "--yes",
          "--repo",
          "AshPostgres.TestRepo"
        ])

      content = file_content(igniter, "lib/my_app/blog/article.ex")
      refute content =~ "many_to_many"
    end

    test "--skip-many-to-many generates only has_many for detected join tables" do
      igniter =
        test_project()
        |> Igniter.compose_task("ash_postgres.gen.resources", [
          "MyApp.Blog",
          "--tables",
          "articles,topics,article_tags",
          "--yes",
          "--repo",
          "AshPostgres.TestRepo",
          "--skip-many-to-many"
        ])

      article_content = file_content(igniter, "lib/my_app/blog/article.ex")
      assert article_content =~ "has_many :article_tags"
      refute article_content =~ "many_to_many"

      topic_content = file_content(igniter, "lib/my_app/blog/topic.ex")
      assert topic_content =~ "has_many :article_tags"
      refute topic_content =~ "many_to_many"
    end

    test "falls back to has_many when the destination table is excluded from generation" do
      # topics excluded → build_many_to_many can't find dest_spec → returns nil
      igniter =
        test_project()
        |> Igniter.compose_task("ash_postgres.gen.resources", [
          "MyApp.Blog",
          "--tables",
          "articles,article_tags",
          "--yes",
          "--repo",
          "AshPostgres.TestRepo"
        ])

      content = file_content(igniter, "lib/my_app/blog/article.ex")
      assert content =~ "has_many :article_tags"
      refute content =~ "many_to_many"
    end

    test "generates many_to_many correctly in fragment mode" do
      igniter =
        test_project()
        |> Igniter.compose_task("ash_postgres.gen.resources", [
          "MyApp.Blog",
          "--tables",
          "articles,topics,article_tags",
          "--yes",
          "--repo",
          "AshPostgres.TestRepo",
          "--fragments"
        ])

      content = file_content(igniter, "lib/my_app/blog/article/model.ex")
      assert content =~ "has_many :article_tags, MyApp.Blog.ArticleTag"
      assert content =~ "many_to_many :topics, MyApp.Blog.Topic"
      assert content =~ "through"
      assert content =~ "join_relationship"
    end
  end

  describe "inferring relationship names from foreign keys with _id suffix" do
    setup do
      AshPostgres.TestRepo.query!("DROP TABLE IF EXISTS people CASCADE")
      AshPostgres.TestRepo.query!("DROP TABLE IF EXISTS articles CASCADE")

      AshPostgres.TestRepo.query!("""
      CREATE TABLE people (
        id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
        name VARCHAR(255)
      )
      """)

      AshPostgres.TestRepo.query!("""
      CREATE TABLE articles (
        id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
        title VARCHAR(255),
        author_id UUID NOT NULL REFERENCES people(id),
        reviewer_id UUID NOT NULL REFERENCES people(id)
      )
      """)

      :ok
    end

    test "avoids naming collisions by appending table name for has_many relationships when multiple references exist" do
      test_project()
      |> Igniter.compose_task("ash_postgres.gen.resources", [
        "MyApp.Blog",
        "--tables",
        "articles,people",
        "--yes",
        "--repo",
        "AshPostgres.TestRepo"
      ])
      |> assert_creates_normalized("lib/my_app/blog/article.ex", """
      defmodule MyApp.Blog.Article do
        use Ash.Resource,
          domain: MyApp.Blog,
          data_layer: AshPostgres.DataLayer

        actions do
          defaults([:read, :destroy, create: :*, update: :*])
        end

        postgres do
          table("articles")
          repo(AshPostgres.TestRepo)
        end

        attributes do
          uuid_primary_key :id do
            public?(true)
          end

          attribute :title, :string do
            public?(true)
          end
        end

        relationships do
          belongs_to :author, MyApp.Blog.Person do
            allow_nil?(false)
            public?(true)
          end

          belongs_to :reviewer, MyApp.Blog.Person do
            allow_nil?(false)
            public?(true)
          end
        end
      end
      """)
      |> assert_creates_normalized("lib/my_app/blog/person.ex", """
      defmodule MyApp.Blog.Person do
        use Ash.Resource,
          domain: MyApp.Blog,
          data_layer: AshPostgres.DataLayer

        actions do
          defaults([:read, :destroy, create: :*, update: :*])
        end

        postgres do
          table("people")
          repo(AshPostgres.TestRepo)
        end

        attributes do
          uuid_primary_key :id do
            public?(true)
          end

          attribute :name, :string do
            public?(true)
          end
        end

        relationships do
          has_many :author_articles, MyApp.Blog.Article do
            destination_attribute(:author_id)
            public?(true)
          end

          has_many :reviewer_articles, MyApp.Blog.Article do
            destination_attribute(:reviewer_id)
            public?(true)
          end
        end
      end
      """)
    end
  end
end
