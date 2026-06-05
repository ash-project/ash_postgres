# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.CustomCollation do
  @moduledoc """
  Represents a custom PostgreSQL collation object created via a repo's
  `c:AshPostgres.Repo.installed_collations/0` callback.

  `ash_postgres` assembles the `CREATE COLLATION` statement from its fields:

      %AshPostgres.CustomCollation{
        name: "natural_sort",
        provider: :icu,
        locale: "en-u-kn-true",
        deterministic: true
      }

  Because `installed_collations/0` is an ordinary function, structs can be built
  dynamically there (e.g. branching on `min_pg_version/0`) without any extra wrapper.
  """

  @fields [
    :name,
    :provider,
    :locale,
    :lc_collate,
    :lc_ctype,
    :from,
    :rules,
    :version
  ]

  defstruct @fields ++ [deterministic: true]

  @type t :: %__MODULE__{
          name: String.t(),
          provider: :icu | :libc | :builtin | nil,
          locale: String.t() | nil,
          lc_collate: String.t() | nil,
          lc_ctype: String.t() | nil,
          from: String.t() | nil,
          rules: String.t() | nil,
          version: String.t() | nil,
          deterministic: boolean()
        }

  @doc false
  @spec create_sql(t()) :: String.t()
  def create_sql(%__MODULE__{name: name, from: from}) when not is_nil(from) do
    "CREATE COLLATION IF NOT EXISTS #{quote_ident(name)} FROM #{quote_ident(from)}"
  end

  def create_sql(%__MODULE__{name: name} = collation) do
    options =
      [
        option("provider", collation.provider),
        option("locale", collation.locale),
        option("lc_collate", collation.lc_collate),
        option("lc_ctype", collation.lc_ctype),
        option("deterministic", collation.deterministic),
        option("rules", collation.rules),
        option("version", collation.version)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(", ")

    "CREATE COLLATION IF NOT EXISTS #{quote_ident(name)} (#{options})"
  end

  @doc false
  @spec drop_sql(t()) :: String.t()
  def drop_sql(%__MODULE__{name: name}) do
    "DROP COLLATION IF EXISTS #{quote_ident(name)}"
  end

  # `provider` and `deterministic` are bare keywords/booleans; everything else is a quoted literal.
  defp option(_key, nil), do: nil
  defp option("provider", provider), do: "provider = #{provider}"
  defp option("deterministic", value) when is_boolean(value), do: "deterministic = #{value}"
  defp option(key, value), do: "#{key} = #{quote_literal(value)}"

  defp quote_ident(name), do: ~s|"#{String.replace(to_string(name), "\"", "\"\"")}"|
  defp quote_literal(value), do: "'#{String.replace(to_string(value), "'", "''")}'"
end
