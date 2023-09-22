defmodule AshPostgres.Reference do
  @moduledoc "Represents the configuration of a reference (i.e foreign key)."
  defstruct [:relationship, :on_delete, :on_update, :name, :deferrable, ignore?: false]

  def schema do
    [
      relationship: [
        type: :atom,
        required: true,
        doc: "The relationship to be configured"
      ],
      ignore?: [
        type: :boolean,
        doc:
          "If set to true, no reference is created for the given relationship. This is useful if you need to define it in some custom way"
      ],
      on_delete: [
        type: {:one_of, [:delete, :nilify, :nothing, :restrict]},
        doc: """
        What should happen to records of this resource when the referenced record of the *destination* resource is deleted.
        """
      ],
      on_update: [
        type: {:one_of, [:update, :nilify, :nothing, :restrict]},
        doc: """
        What should happen to records of this resource when the referenced destination_attribute of the *destination* record is update.
        """
      ],
      deferrable: [
        type: {:one_of, [false, true, :initially]},
        default: false,
        doc: """
        Wether or not the constraint is deferrable. This only affects the migration generator.
        """
      ],
      name: [
        type: :string,
        doc:
          "The name of the foreign key to generate in the database. Defaults to <table>_<source_attribute>_fkey"
      ]
    ]
  end
end
