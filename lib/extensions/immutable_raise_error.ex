# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Extensions.ImmutableRaiseError do
  @moduledoc """
  An extension that installs an immutable version of ash_raise_error.

  This can be used to improve compatibility with Postgres sharding extensions like Citus,
  which requires functions used in CASE or COALESCE expressions to be immutable.

  The new `ash_raise_error_immutable` functions add an additional row-dependent argument to ensure
  the planner doesn't constant-fold error expressions.

  To install, add this module to your repo's `installed_extensions` list:

  ```elixir
  def installed_extensions do
    ["ash-functions", AshPostgres.Extensions.ImmutableRaiseError]
  end
  ```

  And run `mix ash_postgres.generate_migrations` to generate the migrations.

  Once installed, you can control whether the immutable function is used by adding this to your
  repo:

  ```elixir
  def immutable_expr_error?, do: true
  ```
  """

  use AshPostgres.CustomExtension, name: "immutable_raise_error", latest_version: 2

  require Ecto.Query

  @impl true
  def install(0) do
    """
    #{ash_raise_error_immutable()}

    #{ash_to_jsonb_immutable()}
    """
  end

  def install(1) do
    ash_to_jsonb_immutable()
  end

  @impl true
  def uninstall(2) do
    "execute(\"DROP FUNCTION IF EXISTS ash_to_jsonb_immutable(anyelement)\")"
  end

  def uninstall(_version) do
    "execute(\"DROP FUNCTION IF EXISTS ash_to_jsonb_immutable(anyelement), ash_raise_error_immutable(jsonb, anycompatible), ash_raise_error_immutable(jsonb, anyelement, anycompatible)\")"
  end

  defp ash_raise_error_immutable do
    """
    execute(\"\"\"
    CREATE OR REPLACE FUNCTION ash_raise_error_immutable(json_data jsonb, token anycompatible)
    RETURNS boolean AS $$
    BEGIN
        -- Raise an error with the provided JSON data.
        -- The JSON object is converted to text for inclusion in the error message.
        -- 'token' is intentionally ignored; its presence makes the call non-constant at the call site.
        RAISE EXCEPTION 'ash_error: %', json_data::text;
        RETURN NULL;
    END;
    $$ LANGUAGE plpgsql
    IMMUTABLE
    SET search_path = '';
    \"\"\")

    execute(\"\"\"
    CREATE OR REPLACE FUNCTION ash_raise_error_immutable(json_data jsonb, type_signal anyelement, token anycompatible)
    RETURNS anyelement AS $$
    BEGIN
        -- Raise an error with the provided JSON data.
        -- The JSON object is converted to text for inclusion in the error message.
        -- 'token' is intentionally ignored; its presence makes the call non-constant at the call site.
        RAISE EXCEPTION 'ash_error: %', json_data::text;
        RETURN NULL;
    END;
    $$ LANGUAGE plpgsql
    IMMUTABLE
    SET search_path = '';
    \"\"\")
    """
  end

  # Wraps to_jsonb and pins session GUCs that affect JSON. This makes the function’s result
  # deterministic, so it is safe to mark IMMUTABLE.
  defp ash_to_jsonb_immutable do
    """
    execute(\"\"\"
    CREATE OR REPLACE FUNCTION ash_to_jsonb_immutable(value anyelement)
     RETURNS jsonb
     LANGUAGE plpgsql
     IMMUTABLE
     SET search_path TO 'pg_catalog'
     SET \"TimeZone\" TO 'UTC'
     SET \"DateStyle\" TO 'ISO, YMD'
     SET \"IntervalStyle\" TO 'iso_8601'
     SET extra_float_digits TO '0'
     SET bytea_output TO 'hex'
    AS $function$
    BEGIN
      RETURN COALESCE(to_jsonb(value), 'null'::jsonb);
    END;
    $function$
    \"\"\")
    """
  end

  @doc false
  def immutable_error_expr(
        query,
        %Ash.Query.Function.Error{arguments: [exception, input]} = value,
        bindings,
        _embedded?,
        acc,
        type
      ) do
    if !(Keyword.keyword?(input) or is_map(input)) do
      raise "Input expression to `error` must be a map or keyword list"
    end

    acc = %{acc | has_error?: true}

    {error_payload, acc} =
      if Ash.Expr.expr?(input) do
        expression_error_payload(exception, input, query, bindings, acc)
      else
        {Jason.encode!(%{exception: inspect(exception), input: Map.new(input)}), acc}
      end

    dynamic_type =
      if type do
        # This is a type hint, if we're raising an error, we tell it what the value
        # type *would* be in this expression so that we can return a "NULL" of that type
        # its weird, but there isn't any other way that I can tell :)
        AshSql.Expr.validate_type!(query, type, value)

        type =
          AshSql.Expr.parameterized_type(
            bindings.sql_behaviour,
            type,
            [],
            :expr
          )

        Ecto.Query.dynamic(type(fragment("NULL"), ^type))
      else
        nil
      end

    case {dynamic_type, immutable_error_expr_token(query, bindings)} do
      {_, nil} ->
        :error

      {nil, row_token} ->
        {:ok,
         Ecto.Query.dynamic(
           fragment("ash_raise_error_immutable(?::jsonb, ?)", ^error_payload, ^row_token)
         ), acc}

      {dynamic_type, row_token} ->
        {:ok,
         Ecto.Query.dynamic(
           fragment(
             "ash_raise_error_immutable(?::jsonb, ?, ?)",
             ^error_payload,
             ^dynamic_type,
             ^row_token
           )
         ), acc}
    end
  end

  # Encodes an error payload as jsonb using only IMMUTABLE SQL functions.
  #
  # Strategy:
  # * Split the 'input' into Ash expressions and literal values
  # * Build the base json map with the exception name and literal input values
  # * For each expression value, use nested calls to `jsonb_set` (IMMUTABLE) to add the value to
  #   'input', converting each expression to jsonb using `ash_to_jsonb_immutable` (which pins
  #   session GUCs for deterministic encoding)
  defp expression_error_payload(exception, input, query, bindings, acc) do
    {expr_inputs, literal_inputs} =
      Enum.split_with(input, fn {_key, value} -> Ash.Expr.expr?(value) end)

    base_json = %{exception: inspect(exception), input: Map.new(literal_inputs)}

    Enum.reduce(expr_inputs, {base_json, acc}, fn
      {key, expr_value}, {current_payload, acc} ->
        path_expr = %Ash.Query.Function.Type{
          arguments: [["input", to_string(key)], {:array, :string}, []]
        }

        new_value_jsonb =
          %Ash.Query.Function.Fragment{
            arguments: [raw: "ash_to_jsonb_immutable(", expr: expr_value, raw: ")"]
          }

        {%Ecto.Query.DynamicExpr{} = new_payload, acc} =
          AshSql.Expr.dynamic_expr(
            query,
            %Ash.Query.Function.Fragment{
              arguments: [
                raw: "jsonb_set(",
                expr: current_payload,
                raw: "::jsonb, ",
                expr: path_expr,
                raw: ", ",
                expr: new_value_jsonb,
                raw: "::jsonb, true)"
              ]
            },
            bindings,
            false,
            nil,
            acc
          )

        {new_payload, acc}
    end)
  end

  # Returns a row-dependent token to prevent constant-folding for immutable functions.
  defp immutable_error_expr_token(query, bindings) do
    resource = query.__ash_bindings__.resource
    ref_binding = bindings.root_binding

    pk_attr_names = Ash.Resource.Info.primary_key(resource)

    attr_names =
      case pk_attr_names do
        [] ->
          case Ash.Resource.Info.attributes(resource) do
            [%{name: name} | _] -> [name]
            _ -> []
          end

        pk ->
          pk
      end

    if ref_binding && attr_names != [] do
      value_exprs =
        Enum.map(attr_names, fn attr_name ->
          if bindings[:parent?] &&
               ref_binding not in List.wrap(bindings[:lateral_join_bindings]) do
            Ecto.Query.dynamic(field(parent_as(^ref_binding), ^attr_name))
          else
            Ecto.Query.dynamic(field(as(^ref_binding), ^attr_name))
          end
        end)

      row_parts =
        value_exprs
        |> Enum.map(&{:casted_expr, &1})
        |> Enum.intersperse({:raw, ", "})

      {%Ecto.Query.DynamicExpr{} = token, _acc} =
        AshSql.Expr.dynamic_expr(
          query,
          %Ash.Query.Function.Fragment{
            embedded?: false,
            arguments: [raw: "ROW("] ++ row_parts ++ [raw: ")"]
          },
          AshSql.Expr.set_location(bindings, :sub_expr),
          false
        )

      token
    else
      nil
    end
  end
end
