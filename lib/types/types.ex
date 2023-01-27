defmodule AshPostgres.Types do
  @moduledoc false

  alias Ash.Query.Ref

  def parameterized_type({:parameterized, _, _} = type, _) do
    type
  end

  def parameterized_type({:in, type}, constraints) do
    parameterized_type({:array, type}, constraints)
  end

  def parameterized_type({:array, type}, constraints) do
    case parameterized_type(type, constraints[:items] || []) do
      nil ->
        nil

      type ->
        {:array, type}
    end
  end

  def parameterized_type(Ash.Type.CiString, constraints) do
    parameterized_type(Ash.Type.CiStringWrapper, constraints)
  end

  def parameterized_type(Ash.Type.String.EctoType, constraints) do
    parameterized_type(Ash.Type.StringWrapper, constraints)
  end

  def parameterized_type(type, constraints) do
    if Ash.Type.ash_type?(type) do
      cast_in_query? =
        if function_exported?(Ash.Type, :cast_in_query?, 2) do
          Ash.Type.cast_in_query?(type, constraints)
        else
          Ash.Type.cast_in_query?(type)
        end

      if cast_in_query? do
        parameterized_type(Ash.Type.ecto_type(type), constraints)
      else
        nil
      end
    else
      if is_atom(type) && :erlang.function_exported(type, :type, 1) do
        {:parameterized, type, constraints || []}
      else
        type
      end
    end
  end

  def determine_types(mod, values) do
    Code.ensure_compiled(mod)

    cond do
      :erlang.function_exported(mod, :types, 0) ->
        mod.types()

      :erlang.function_exported(mod, :args, 0) ->
        mod.args()

      true ->
        [:any]
    end
    |> Enum.map(fn types ->
      case types do
        :same ->
          types =
            for _ <- values do
              :same
            end

          closest_fitting_type(types, values)

        :any ->
          for _ <- values do
            :any
          end

        types ->
          closest_fitting_type(types, values)
      end
    end)
    |> Enum.filter(fn types ->
      Enum.all?(types, &(vagueness(&1) == 0))
    end)
    |> case do
      [type] ->
        if type == :any || type == {:in, :any} do
          nil
        else
          type
        end

      # There are things we could likely do here
      # We only say "we know what types these are" when we explicitly know
      _ ->
        Enum.map(values, fn _ -> nil end)
    end
  end

  defp closest_fitting_type(types, values) do
    types_with_values = Enum.zip(types, values)

    types_with_values
    |> fill_in_known_types()
    |> clarify_types()
  end

  defp clarify_types(types) do
    basis =
      types
      |> Enum.map(&elem(&1, 0))
      |> Enum.min_by(&vagueness(&1))

    Enum.map(types, fn {type, _value} ->
      replace_same(type, basis)
    end)
  end

  defp replace_same({:in, type}, basis) do
    {:in, replace_same(type, basis)}
  end

  defp replace_same(:same, :same) do
    :any
  end

  defp replace_same(:same, {:in, :same}) do
    {:in, :any}
  end

  defp replace_same(:same, basis) do
    basis
  end

  defp replace_same(other, _basis) do
    other
  end

  defp fill_in_known_types(types) do
    Enum.map(types, &fill_in_known_type/1)
  end

  defp fill_in_known_type(
         {vague_type, %Ref{attribute: %{type: type, constraints: constraints}}} = ref
       )
       when vague_type in [:any, :same] do
    if Ash.Type.ash_type?(type) do
      type = type |> parameterized_type(constraints) |> array_to_in()

      {type || :any, ref}
    else
      type =
        if is_atom(type) && :erlang.function_exported(type, :type, 1) do
          {:parameterized, type, []} |> array_to_in()
        else
          type |> array_to_in()
        end

      {type, ref}
    end
  end

  defp fill_in_known_type(
         {{:array, type}, %Ref{attribute: %{type: {:array, type}} = attribute} = ref}
       ) do
    {:in, fill_in_known_type({type, %{ref | attribute: %{attribute | type: type}}})}
  end

  defp fill_in_known_type({type, value}), do: {array_to_in(type), value}

  defp array_to_in({:array, v}), do: {:in, array_to_in(v)}

  defp array_to_in({:parameterized, type, constraints}),
    do: {:parameterized, array_to_in(type), constraints}

  defp array_to_in(v), do: v

  defp vagueness({:in, type}), do: vagueness(type)
  defp vagueness(:same), do: 2
  defp vagueness(:any), do: 1
  defp vagueness(_), do: 0
end
