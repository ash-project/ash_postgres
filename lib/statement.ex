defmodule AshPostgres.Statement do
  @moduledoc false
  defstruct [
    :name,
    :up,
    :down,
    :code?
  ]

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
      Whether the provided up/down should be treated as code or sql strings.

      By default, we place the strings inside of ecto migration's `execute/1`
      function and assume they are sql. Use this option if you want to provide custom
      elixir code to be placed directly in the migrations
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
