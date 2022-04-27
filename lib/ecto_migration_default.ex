defprotocol EctoMigrationDefault do
  def to_default(value)
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
