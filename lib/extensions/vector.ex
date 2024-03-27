defmodule AshPostgres.Extensions.Vector do
  @moduledoc """
  An extension that adds support for the `vector` type.

  Create a file with these contents, not inside of a module:

  ```elixir
  Postgrex.Types.define(<YourApp>.PostgrexTypes, [AshPostgres.Extensions.Vector] ++ Ecto.Adapters.Postgres.extensions(), [])
  ```

  And then ensure that you refer to these types in your repo configuration, i.e

  ```elixir
  config :my_app, YourApp.Repo,
    types: <YourApp>.PostgrexTypes
  ```
  """
  import Postgrex.BinaryUtils, warn: false

  def init(opts), do: Keyword.get(opts, :decode_binary, :copy)

  def matching(_), do: [type: "vector"]

  def format(_), do: :binary

  def encode(_) do
    quote do
      vec when is_struct(vec, Ash.Vector) ->
        data = vec |> Ash.Vector.to_binary()
        [<<IO.iodata_length(data)::int32()>> | data]

      vec ->
        case Ash.Vector.new(vec) do
          {:ok, vector} ->
            data = Ash.Vector.to_binary(vector)
            [<<IO.iodata_length(data)::int32()>> | data]

          {:error, error} ->
            raise """
            Attempting to encode invalid vector, error: #{inspect(error)}

            Vector:

            #{inspect(vec)}
            """
        end
    end
  end

  def decode(:copy) do
    quote do
      <<len::int32(), bin::binary-size(len)>> ->
        bin |> :binary.copy() |> Ash.Vector.from_binary()
    end
  end

  def decode(_) do
    quote do
      <<len::int32(), bin::binary-size(len)>> ->
        bin |> Ash.Vector.from_binary()
    end
  end
end
