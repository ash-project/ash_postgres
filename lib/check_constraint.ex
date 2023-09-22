defmodule AshPostgres.CheckConstraint do
  @moduledoc "Represents a configured check constraint on the table backing a resource"

  defstruct [:attribute, :name, :message, :check]

  def schema do
    [
      attribute: [
        type: :any,
        doc:
          "The attribute or list of attributes to which an error will be added if the check constraint fails",
        required: true
      ],
      name: [
        type: :string,
        required: true,
        doc: "The name of the constraint"
      ],
      message: [
        type: :string,
        doc: "The message to be added if the check constraint fails"
      ],
      check: [
        type: :string,
        doc:
          "The contents of the check. If this is set, the migration generator will include it when generating migrations"
      ]
    ]
  end
end
