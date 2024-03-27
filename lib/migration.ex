defmodule AshPostgres.Migration do
  @moduledoc "Utilities for use in migrations"

  @doc """
  A utility for creating postgres enums for an Ash enum type.

  In your migration, you can say:

  ```elixir
  def up() do
    AshPostgres.Migration.create_enum(MyEnumType)
  end
  ```

  Attribution:

  This code and example was copied from ecto_enum. I didn't use the library itself
  because it has a lot that would not currently be relevant for Ash.
  https://github.com/gjaldon/ecto_enum

  Must be done manually, as the migration generator will not do it.
  Additionally, altering the type must be done in its own, separate migration, which
  must have `@disable_ddl_transaction true`, as you cannot do this operation
  in a transaction.

  For example:

  ```elixir
  defmodule MyApp.Repo.Migrations.AddToGenderEnum do
    use Ecto.Migration
    @disable_ddl_transaction true

    def up do
      Ecto.Migration.execute "ALTER TYPE gender ADD VALUE IF NOT EXISTS 'other'"
    end

    def down do
      ...
    end
  end
  ```

  Keep in mind, that if you want to create a custom enum type, you will want to add
  ```elixir
  def storage_type(_), do: :my_type_name
  ```
  """
  def create_enum(type, constraints \\ []) do
    if type.storage_type(constraints) == :string do
      raise "Must customize the storage_type for #{type} in order to create an enum"
    end

    types = Enum.map_join(type.values(), ", ", &"'#{&1}'")

    Ecto.Migration.execute(
      "CREATE TYPE #{type.storage_type()} AS ENUM (#{types})",
      "DROP TYPE #{type.storage_type()}"
    )
  end

  def drop_enum(type) do
    if type.storage_type() == :string do
      raise "Must customize the storage_type for #{type} in order to create an enum"
    end

    types = Enum.map_join(type.values(), ", ", &"'#{&1}'")

    Ecto.Migration.execute(
      "DROP TYPE #{type.storage_type()}",
      "CREATE TYPE #{type.storage_type()} AS ENUM (#{types})"
    )
  end
end
