# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.MigrationCompileCache do
  @moduledoc """
  A cache for the compiled migrations.

  This is used to avoid recompiling the migration files
  every time a migration is run, as well as ensuring that
  migrations are compiled sequentially.

  This is important because otherwise there is a race condition
  where two invocations could be compiling the same migration at
  once, which would error out.
  """

  def start_link(opts \\ %{}) do
    Agent.start_link(fn -> opts end, name: __MODULE__)
  end

  @doc """
  Compile a file, caching the result for future calls.
  """
  def compile_file(file) do
    Agent.get_and_update(__MODULE__, fn state ->
      new_state = ensure_compiled(state, file)
      {Map.get(new_state, file), new_state}
    end)
  end

  defp ensure_compiled(state, file) do
    case Map.get(state, file) do
      nil ->
        Code.put_compiler_option(:ignore_module_conflict, true)
        compiled = Code.compile_file(file)
        Map.put(state, file, compiled)

      _ ->
        state
    end
  after
    Code.put_compiler_option(:ignore_module_conflict, false)
  end
end
