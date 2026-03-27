# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.ResourceGeenratorTests do
  use AshPostgres.RepoCase, async: false

  import Igniter.Test

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
    |> assert_creates("lib/my_app/accounts/example_table.ex", """
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
    |> assert_creates("lib/my_app/inventory/warehouse.ex", """
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
    |> assert_creates("lib/my_app/inventory/product.ex", """
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

        uuid_primary_key :id do
          public?(true)
        end

        attribute :name, :string do
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
      |> assert_creates("lib/my_app/accounts/example_table.ex", """
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
      |> assert_creates("lib/my_app/accounts/example_table/model.ex", """
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
      |> assert_creates("lib/my_app/sales/customer.ex", """
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
      |> assert_creates("lib/my_app/sales/customer/model.ex", """
      defmodule MyApp.Sales.Customer.Model do
        use Spark.Dsl.Fragment,
          of: Ash.Resource

        attributes do
          uuid_primary_key :id do
            public?(true)
          end

          uuid_primary_key :id do
            public?(true)
          end

          attribute :name, :string do
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
      |> assert_creates("lib/my_app/sales/order/model.ex", """
      defmodule MyApp.Sales.Order.Model do
        use Spark.Dsl.Fragment,
          of: Ash.Resource

        attributes do
          uuid_primary_key :id do
            public?(true)
          end

          uuid_primary_key :id do
            public?(true)
          end

          attribute :total, :integer do
            public?(true)
          end
        end

        relationships do
          belongs_to :customer, MyApp.Sales.Customer do
            allow_nil?(false)
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
      |> assert_creates("lib/my_app/accounts/example_table/model.ex", """
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
end
