defmodule AshPostgres.Functions.TrigramSimilarity do
  @moduledoc """
  See the postgres docs on [https://www.postgresql.org/docs/9.6/pgtrgm.html](trigram) for more information.

  Requires the pg_trgm extension. Configure which extensions you have installed in your `AshPostgres.Repo`

      # Example

      filter(query, trigram_similarity(name, "geoff") > 0.4)
  """

  use Ash.Query.Function, name: :trigram_similarity

  def args, do: [[:string, :string]]
end
