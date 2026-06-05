# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Collation do
  @moduledoc "Represents the collation applied to an attribute's column in generated migrations."
  @fields [
    :attribute,
    :collation
  ]

  defstruct @fields ++ [:__spark_metadata__]

  def fields, do: @fields

  @schema [
    attribute: [
      type: :atom,
      required: true,
      doc: "The attribute to apply the collation to."
    ],
    collation: [
      type: :string,
      required: true,
      doc:
        "The name of the collation to use for the column. Can be a built-in collation (e.g `\"de_AT\"`, `\"und-x-icu\"`) or one created via the repo's `installed_collations/0` callback."
    ]
  ]

  def schema, do: @schema
end
