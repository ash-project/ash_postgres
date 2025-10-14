# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Expressions.TrigramWordSimilarity do
  @moduledoc false
  use Ash.CustomExpression,
    name: :trigram_word_similarity,
    arguments: [[:string, :string]],
    # setting to true does not seem to change the behaviour observed in this ticket
    predicate?: false

  def expression(data_layer, [left, right]) when data_layer in [AshPostgres.DataLayer] do
    {:ok, expr(fragment("word_similarity(?, ?)", ^left, ^right))}
  end

  def expression(_data_layer, _args), do: :unknown
end
