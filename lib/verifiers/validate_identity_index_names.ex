defmodule AshPostgres.Verifiers.ValidateIdentityIndexNames do
  @moduledoc false
  use Spark.Dsl.Verifier
  alias Spark.Dsl.Verifier

  def verify(dsl) do
    identity_index_names =
      AshPostgres.DataLayer.Info.identity_index_names(dsl)

    Enum.each(identity_index_names, fn {identity, name} ->
      if String.length(name) > 63 do
        raise Spark.Error.DslError,
          path: [:postgres, :identity_index_names, identity],
          module: Verifier.get_persisted(dsl, :module),
          message: """
          Identity #{identity} has a name that is too long. Names must be 63 characters or less.
          """
      end
    end)

    table = AshPostgres.DataLayer.Info.table(dsl)

    if table do
      dsl
      |> Ash.Resource.Info.identities()
      |> Enum.map(fn identity ->
        {identity, identity_index_names[identity.name] || "#{table}_#{identity.name}_index"}
      end)
      |> Enum.group_by(&elem(&1, 1))
      |> Enum.each(fn
        {name, [_, _ | _] = identities} ->
          raise Spark.Error.DslError,
            path: [:postgres, :identity_index_names, name],
            module: Verifier.get_persisted(dsl, :module),
            message: """
            Multiple identities would result in the same index name: #{name}

            Identities: #{inspect(Enum.map(identities, & &1.name))}
            """

        {name, [identity]} ->
          if String.length(name) > 63 do
            raise Spark.Error.DslError,
              path: [:postgres, :identity_index_names, name],
              module: Verifier.get_persisted(dsl, :module),
              message: """
              Identity #{identity.name} has a name that is too long. Names must be 63 characters or less.

              Please configure an index name for this identity in the `identity_index_names` configuration. For example:application

              postgres do
                identity_index_names #{inspect(identity.name)}: "a_shorter_name"
              end
              """
          end
      end)
    end

    :ok
  end
end
