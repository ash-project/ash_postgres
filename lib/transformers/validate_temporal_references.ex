# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Transformers.ValidateTemporalReferences do
  @moduledoc false
  # A temporal relationship (`temporal_keys` with both a source and destination period
  # attribute) is backed by a Postgres `PERIOD` foreign key. PostgreSQL only supports
  # `NO ACTION` for those — "PostgreSQL supports temporal foreign keys with action
  # NO ACTION, but not RESTRICT, CASCADE, SET NULL, or SET DEFAULT" (PG19 docs, 5.7
  # Temporal Tables). So reject an `on_delete`/`on_update` referential action on such a
  # relationship's `references` — it can't be expressed at the database level and must be
  # handled in the application (e.g. an `Ash.Resource.Change.CascadeDestroy`).
  #
  # This is a transformer (not a verifier) so it raises and fails compilation — Spark
  # verifiers only emit a warning here.
  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer
  alias Spark.Error.DslError

  def transform(dsl) do
    references =
      dsl
      |> AshPostgres.DataLayer.Info.references()
      |> Map.new(&{&1.relationship, &1})

    dsl
    |> Ash.Resource.Info.relationships()
    |> Enum.find_value(fn relationship ->
      reference = references[relationship.name]

      cond do
        not period_foreign_key?(relationship) -> nil
        action?(reference && reference.on_delete) -> {relationship.name, :on_delete}
        action?(reference && reference.on_update) -> {relationship.name, :on_update}
        true -> nil
      end
    end)
    |> case do
      nil ->
        {:ok, dsl}

      {relationship, option} ->
        raise DslError,
          module: Transformer.get_persisted(dsl, :module),
          path: [:postgres, :references, relationship, option],
          message: """
          `#{option}` is not supported on the temporal relationship #{inspect(relationship)}.

          It is backed by a Postgres `PERIOD` foreign key, and PostgreSQL only supports
          `NO ACTION` for those (not CASCADE/SET NULL/SET DEFAULT/RESTRICT) — see the
          PostgreSQL docs, "5.7 Temporal Tables".

          Remove `#{option}` from its `references` and handle the cascade in the
          application instead (e.g. `change cascade_destroy(#{inspect(relationship)})`).
          """
    end
  end

  # A `belongs_to` whose `temporal_keys` name both a source and destination period
  # attribute gets a `PERIOD` foreign key from the migration generator.
  defp period_foreign_key?(%{type: :belongs_to} = relationship) do
    case Map.get(relationship, :temporal_keys) do
      {source, destination} -> not is_nil(source) and not is_nil(destination)
      _ -> false
    end
  end

  defp period_foreign_key?(_), do: false

  # `nil`/`:nothing` mean NO ACTION; anything else is an unsupported referential action.
  defp action?(nil), do: false
  defp action?(:nothing), do: false
  defp action?(_), do: true
end
