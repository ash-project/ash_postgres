defmodule AshPostgres.Statement do
  @moduledoc "Represents a custom statement to be run in generated migrations"

  @fields [
    :name,
    :up,
    :down,
    :code?
  ]

  defstruct @fields

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
    ]
  ]

  def schema, do: @schema
end
