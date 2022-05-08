require Logger

defprotocol EctoMigrationDefault do
  @fallback_to_any true
  def to_default(value)
end

defimpl EctoMigrationDefault, for: Any do
  def to_default(value) do
    Logger.warn("""
    You have specified a default value for a type that cannot be explicitly
    converted to an Ecto default:

      `#{inspect(value)}`

    The default value in the migration will be set to `nil` and you can edit
    your migration accordingly.

    To prevent this warning, implement the `EctoMigrationDefault` protocol
    for the appropriate Elixir type in your Ash project.
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
