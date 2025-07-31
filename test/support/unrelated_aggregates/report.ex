defmodule AshPostgres.Test.UnrelatedAggregatesTest.Report do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("unrelated_reports")
    repo(AshPostgres.TestRepo)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:title, :string, public?: true)
    attribute(:author_name, :string, public?: true)
    attribute(:score, :integer, public?: true)

    attribute(:inserted_at, :utc_datetime,
      public?: true,
      default: &DateTime.utc_now/0,
      allow_nil?: false
    )
  end

  actions do
    defaults([:read, :destroy, update: :*])

    create :create do
      primary?(true)
      accept([:title, :author_name, :score, :inserted_at])
    end
  end
end
