# SPDX-FileCopyrightText: 2020 Zach Daniel
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

  use AshPostgres.CustomExtension, name: "immutable_raise_error", latest_version: 1

  require Ecto.Query

  @impl true
  def install(0) do
    ash_raise_error_immutable()
  end

  @impl true
  def uninstall(_version) do
    "execute(\"DROP FUNCTION IF EXISTS ash_raise_error_immutable(jsonb, ANYCOMPATIBLE), ash_raise_error_immutable(jsonb, ANYELEMENT, ANYCOMPATIBLE)\")"
  end

  defp ash_raise_error_immutable do
    """
    execute(\"\"\"
    CREATE OR REPLACE FUNCTION ash_raise_error_immutable(json_data jsonb, token ANYCOMPATIBLE)
    RETURNS BOOLEAN AS $$
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
    CREATE OR REPLACE FUNCTION ash_raise_error_immutable(json_data jsonb, type_signal ANYELEMENT, token ANYCOMPATIBLE)
    RETURNS ANYELEMENT AS $$
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

  @doc false
  def immutable_error_expr(
        query,
        %Ash.Query.Function.Error{arguments: [exception, input]} = value,
        bindings,
        embedded?,
        acc,
        type
      ) do
    acc = %{acc | has_error?: true}

    {encoded, acc} =
      if Ash.Expr.expr?(input) do
        frag_parts =
          Enum.flat_map(input, fn {key, value} ->
            if Ash.Expr.expr?(value) do
              [
                expr: to_string(key),
                raw: "::text, ",
                expr: value,
                raw: ", "
              ]
            else
              [
                expr: to_string(key),
                raw: "::text, ",
                expr: value,
                raw: "::jsonb, "
              ]
            end
          end)

        frag_parts =
          List.update_at(frag_parts, -1, fn {:raw, text} ->
            {:raw, String.trim_trailing(text, ", ") <> "))"}
          end)

        AshSql.Expr.dynamic_expr(
          query,
          %Ash.Query.Function.Fragment{
            embedded?: false,
            arguments:
              [
                raw: "jsonb_build_object('exception', ",
                expr: inspect(exception),
                raw: "::text, 'input', jsonb_build_object("
              ] ++
                frag_parts
          },
          bindings,
          embedded?,
          nil,
          acc
        )
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
           fragment("ash_raise_error_immutable(?::jsonb, ?)", ^encoded, ^row_token)
         ), acc}

      {dynamic_type, row_token} ->
        {:ok,
         Ecto.Query.dynamic(
           fragment(
             "ash_raise_error_immutable(?::jsonb, ?, ?)",
             ^encoded,
             ^dynamic_type,
             ^row_token
           )
         ), acc}
    end
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
