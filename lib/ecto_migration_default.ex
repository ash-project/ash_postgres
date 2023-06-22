defprotocol EctoMigrationDefault do
  @moduledoc """
  Allows configuring how values are translated to default values in migrations.

  Still a work in progress, but covers most standard values aside from maps.
  """
  @fallback_to_any true
  @doc "Returns the text (elixir code) that will be placed into a migration as the default value"
  def to_default(value)
end

defimpl EctoMigrationDefault, for: Any do
  require Logger

  def to_default(value) do
    Logger.warning("""
    You have specified a default value for a type that cannot be explicitly
    converted to an Ecto default:

      `#{inspect(value)}`

    The default value in the migration will be set to `nil` and you can edit
    your migration accordingly.

    To prevent this warning, implement the `EctoMigrationDefault` protocol
    for the appropriate Elixir type in your Ash project, or configure its
    default value in `migration_defaults` in the postgres section. Use `\\\"nil\\\"`
    for no default.
    """)

    "nil"
  end
end

defimpl EctoMigrationDefault, for: Integer do
  def to_default(value) do
    to_string(value)
  end
end

defimpl EctoMigrationDefault, for: Float do
  def to_default(value) do
    to_string(value)
  end
end

defimpl EctoMigrationDefault, for: Decimal do
  def to_default(value) do
    ~s["#{value}"]
  end
end

defimpl EctoMigrationDefault, for: BitString do
  def to_default(value) do
    inspect(value)
  end
end

defimpl EctoMigrationDefault, for: DateTime do
  def to_default(value) do
    ~s[fragment("'#{to_string(value)}'")]
  end
end

defimpl EctoMigrationDefault, for: NaiveDateTime do
  def to_default(value) do
    ~s[fragment("'#{to_string(value)}'")]
  end
end

defimpl EctoMigrationDefault, for: Date do
  def to_default(value) do
    ~s[fragment("'#{to_string(value)}'")]
  end
end

defimpl EctoMigrationDefault, for: Time do
  def to_default(value) do
    ~s[fragment("'#{to_string(value)}'")]
  end
end

defimpl EctoMigrationDefault, for: Atom do
  def to_default(value) when value in [nil, true, false], do: inspect(value)

  def to_default(value) do
    inspect(to_string(value))
  end
end
