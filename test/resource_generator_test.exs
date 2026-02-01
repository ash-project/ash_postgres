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
end
