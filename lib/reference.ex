defmodule AshPostgres.Reference do
  @moduledoc """
  Contains configuration for a database reference
  """
  defstruct [:relationship, :on_delete, :on_update, :name, ignore?: false]

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

        The difference between `:nothing` and `:restrict` is subtle and, if you are unsure, choose `:nothing` (the default behavior).
        `:restrict` will prevent the deletion from happening *before* the end of the database transaction, whereas `:nothing` allows the
        transaction to complete before doing so. This allows for things like deleting the destination row and *then* deleting the source
        row.

        ## Important!

          No resource logic is applied with this operation! No authorization rules or validations take place, and no notifications are issued.
          This operation happens *directly* in the database.

          This option is called `on_delete`, instead of `on_destroy`, because it is hooking into the database level deletion, *not*
          a `destroy` action in your resource.
        """
      ],
      on_update: [
        type: {:one_of, [:update, :nilify, :nothing, :restrict]},
        doc: """
        What should happen to records of this resource when the referenced destination_field of the *destination* record is update.

        The difference between `:nothing` and `:restrict` is subtle and, if you are unsure, choose `:nothing` (the default behavior).
        `:restrict` will prevent the deletion from happening *before* the end of the database transaction, whereas `:nothing` allows the
        transaction to complete before doing so. This allows for things like updating the destination row and *then* updating the reference
        as long as you are in a transaction.

        ## Important!

          No resource logic is applied with this operation! No authorization rules or validations take place, and no notifications are issued.
          This operation happens *directly* in the database.
        """
      ],
      name: [
        type: :string,
        doc:
          "The name of the foreign key to generate in the database. Defaults to <table>_<source_field>_fkey"
      ]
    ]
  end
end
