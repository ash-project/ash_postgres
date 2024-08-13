defmodule AshPostgres.Repo.BeforeCompile do
  @moduledoc false

  defmacro __before_compile__(_env) do
    quote do
      unless Module.defines?(__MODULE__, {:min_pg_version, 0}, :def) do
        IO.warn("""
        Please define `min_pg_version/0` in repo module: #{inspect(__MODULE__)}

        For example:

            def min_pg_version do
              %Version{major: 16, minor: 0, patch: 0}
            end

        The lowest compatible version is being assumed.
        """)

        def min_pg_version do
          %Version{major: 13, minor: 0, patch: 0}
        end
      end
    end
  end
end
