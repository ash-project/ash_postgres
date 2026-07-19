# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Statement do
  @moduledoc "Represents a custom statement to be run in generated migrations"

  @fields [
    :name,
    :up,
    :down,
    :code?,
    :global?,
    :after_tables
  ]

  defstruct @fields ++ [:__spark_metadata__]

  def fields, do: @fields

  @schema [
    name: [
      type: :atom,
      required: true,
      doc: """
      The name of the statement, must be unique within the resource
      """
    ],
    code?: [
      type: :boolean,
      default: false,
      doc: """
      By default, we place the strings inside of ecto migration's `execute/1` function and assume they are sql. Use this option if you want to provide custom elixir code to be placed directly in the migrations
      """
    ],
    global?: [
      type: :boolean,
      default: false,
      doc: """
      By default, a multi-tenant resource's custom statements will be written into the tenant migration folder. Set this to true for statements that create global, shared structures so they are written into the public migration folder even when defined on a tenant resource.
      """
    ],
    up: [
      type: :string,
      doc: """
      How to create the structure of the statement
      """,
      required: true
    ],
    down: [
      type: :string,
      doc: "How to tear down the structure of the statement",
      required: true
    ],
    after_tables: [
      type: {:list, :string},
      default: [],
      doc: """
      Table names that this statement's `up` depends on being fully finalized (including their columns and indexes) before it runs. Use this when a raw SQL statement references structure (e.g. a foreign key referencing a unique index) on another table so the migration generator can order it correctly.
      """
    ]
  ]

  def schema, do: @schema
end
