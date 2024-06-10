defmodule AshPostgres.Reference do
  @moduledoc "Represents the configuration of a reference (i.e foreign key)."
  defstruct [
    :relationship,
    :on_delete,
    :on_update,
    :name,
    :match_with,
    :match_type,
    :deferrable,
    :index?,
    ignore?: false
  ]

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
        type:
          {:or,
           [
             {:one_of, [:delete, :nilify, :nothing, :restrict]},
             {:tagged_tuple, :nilify, {:wrap_list, :atom}}
           ]},
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
        Whether or not the constraint is deferrable. This only affects the migration generator.
        """
      ],
      name: [
        type: :string,
        doc:
          "The name of the foreign key to generate in the database. Defaults to <table>_<source_attribute>_fkey"
      ],
      match_with: [
        type: :non_empty_keyword_list,
        doc:
          "Defines additional keys to the foreign key in order to build a composite foreign key. The key should be the name of the source attribute (in the current resource), the value the name of the destination attribute."
      ],
      match_type: [
        type: {:one_of, [:simple, :partial, :full]},
        doc: "select if the match is `:simple`, `:partial`, or `:full`"
      ],
      index?: [
        type: :boolean,
        default: false,
        doc: "Whether to create or not a corresponding index"
      ]
    ]
  end
end
