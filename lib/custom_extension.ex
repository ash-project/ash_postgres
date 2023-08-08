defmodule AshPostgres.CustomExtension do
  @moduledoc """
  A custom extension implementation.
  """

  @callback install(version :: integer) :: String.t()

  @callback uninstall(version :: integer) :: String.t()

  defmacro __using__(name: name, latest_version: latest_version) do
    quote do
      @behaviour AshPostgres.CustomExtension

      @extension_name unquote(name)
      @extension_latest_version unquote(latest_version)

      def extension, do: {@extension_name, @extension_latest_version, &install/1, &uninstall/1}
    end
  end
end
