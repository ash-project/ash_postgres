# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.SqlImplementation do
  @moduledoc false
  use AshSql.Implementation

  require Ecto.Query

  @impl true
  def manual_relationship_function, do: :ash_postgres_join

  @impl true
  def manual_relationship_subquery_function, do: :ash_postgres_subquery

  @impl true
  def require_ash_functions_for_or_and_and?, do: true

  @impl true
  def require_extension_for_citext, do: {true, "citext"}

  # Migrations create second-precision columns for these types (e.g.
  # `timestamp(0)`, see `Ecto.Adapters.Postgres.Connection.column_type_name/2`),
  # but expression casts render without the typmod. Casting a column reference
  # to `::timestamp` when the column is `timestamp(0)` is a typmod change, so
  # postgres keeps a coercion node and can no longer match the bare column
  # against partial-index predicates or expression indexes. Casting to the
  # typmod-accurate type makes it an identity cast that the parser deletes.
  @impl true
  def ref_cast_type(type) do
    case ref_storage_type(type) do
      :utc_datetime -> AshPostgres.Type.Timestamp0
      :naive_datetime -> AshPostgres.Type.NaiveTimestamp0
      :time -> AshPostgres.Type.Time0
      _ -> type
    end
  end

  defp ref_storage_type({:parameterized, _} = type), do: Ecto.Type.type(type)
  defp ref_storage_type({:parameterized, mod, params}), do: mod.type(params)
  defp ref_storage_type(type) when is_atom(type), do: type
  defp ref_storage_type(_), do: nil

  @impl true
  def storage_type(resource, field) do
    case AshPostgres.DataLayer.Info.storage_types(resource)[field] do
      nil ->
        nil

      {:array, type} ->
        parameterized_type({:array, Ash.Type.get_type(type)}, [])

      {:array, type, constraints} ->
        parameterized_type({:array, Ash.Type.get_type(type)}, constraints)

      {type, constraints} ->
        parameterized_type(type, constraints)

      type ->
        parameterized_type(type, [])
    end
  end

  @impl true
  def expr(_query, [], _bindings, _embedded?, acc, type) when type in [:map, :jsonb] do
    {:ok, Ecto.Query.dynamic(fragment("'[]'::jsonb")), acc}
  end

  def expr(
        query,
        %Ash.Query.UpsertConflict{attribute: attribute},
        _bindings,
        _embedded?,
        acc,
        _type
      ) do
    # The incoming row is referenced as `EXCLUDED` for both `INSERT ... ON CONFLICT` and
    # `MERGE` (where `AshPostgres.Merge` aliases the USING source `AS EXCLUDED`).
    {:ok,
     Ecto.Query.dynamic(
       [],
       fragment(
         "EXCLUDED.?",
         identifier(
           ^to_string(
             AshPostgres.DataLayer.get_source_for_upsert_field(
               attribute,
               query.__ash_bindings__.resource
             )
           )
         )
       )
     ), acc}
  end

  def expr(query, %AshPostgres.Functions.Binding{}, _bindings, _embedded?, acc, _type) do
    binding =
      AshSql.Bindings.get_binding(
        query.__ash_bindings__.resource,
        [],
        query,
        [:left, :inner, :root]
      )

    if is_nil(binding) do
      raise "Error while constructing explicit `binding()` reference."
    end

    {:ok, Ecto.Query.dynamic([{^binding, row}], row), acc}
  end

  def expr(
        query,
        %like{arguments: [arg1, arg2], embedded?: pred_embedded?},
        bindings,
        embedded?,
        acc,
        type
      )
      when like in [AshPostgres.Functions.Like, AshPostgres.Functions.ILike] do
    {arg1, acc} =
      AshSql.Expr.dynamic_expr(query, arg1, bindings, pred_embedded? || embedded?, :string, acc)

    {arg2, acc} =
      AshSql.Expr.dynamic_expr(query, arg2, bindings, pred_embedded? || embedded?, :string, acc)

    inner_dyn =
      if like == AshPostgres.Functions.Like do
        Ecto.Query.dynamic(like(^arg1, ^arg2))
      else
        Ecto.Query.dynamic(ilike(^arg1, ^arg2))
      end

    # Cast the result to a proper boolean when that's the expected output type.
    # `type` typically arrives as a `{Ash.Type.Boolean, constraints}` tuple, so
    # match both forms.
    if boolean_type?(type) do
      {:ok, Ecto.Query.dynamic(type(^inner_dyn, :boolean)), acc}
    else
      {:ok, inner_dyn, acc}
    end
  end

  def expr(
        query,
        %AshPostgres.Functions.TrigramSimilarity{
          arguments: [arg1, arg2],
          embedded?: pred_embedded?
        },
        bindings,
        embedded?,
        acc,
        _type
      ) do
    {arg1, acc} =
      AshSql.Expr.dynamic_expr(query, arg1, bindings, pred_embedded? || embedded?, :string, acc)

    {arg2, acc} =
      AshSql.Expr.dynamic_expr(query, arg2, bindings, pred_embedded? || embedded?, :string, acc)

    {:ok, Ecto.Query.dynamic(fragment("similarity(?, ?)", ^arg1, ^arg2)), acc}
  end

  def expr(
        query,
        %AshPostgres.Functions.VectorCosineDistance{
          arguments: [arg1, arg2],
          embedded?: pred_embedded?
        },
        bindings,
        embedded?,
        acc,
        _type
      ) do
    {arg1, acc} =
      AshSql.Expr.dynamic_expr(query, arg1, bindings, pred_embedded? || embedded?, :string, acc)

    {arg2, acc} =
      AshSql.Expr.dynamic_expr(query, arg2, bindings, pred_embedded? || embedded?, :string, acc)

    {:ok, Ecto.Query.dynamic(fragment("(? <=> ?)", ^arg1, ^arg2)), acc}
  end

  def expr(
        query,
        %AshPostgres.Functions.VectorL2Distance{
          arguments: [arg1, arg2],
          embedded?: pred_embedded?
        },
        bindings,
        embedded?,
        acc,
        _type
      ) do
    {arg1, acc} =
      AshSql.Expr.dynamic_expr(query, arg1, bindings, pred_embedded? || embedded?, :string, acc)

    {arg2, acc} =
      AshSql.Expr.dynamic_expr(query, arg2, bindings, pred_embedded? || embedded?, :string, acc)

    {:ok, Ecto.Query.dynamic(fragment("(? <-> ?)", ^arg1, ^arg2)), acc}
  end

  def expr(
        query,
        %AshPostgres.Functions.PostgresIn{
          arguments: [left, right],
          embedded?: pred_embedded?
        },
        bindings,
        embedded?,
        acc,
        _type
      ) do
    context_embedded? = pred_embedded? || embedded?

    # Determine the Ecto type from the left-hand side for proper value encoding
    left_type =
      case left do
        %Ash.Query.Ref{attribute: %{type: type, constraints: constraints}} ->
          AshPostgres.SqlImplementation.parameterized_type(type, constraints)

        _ ->
          :any
      end

    {left_expr, acc} =
      AshSql.Expr.dynamic_expr(query, left, bindings, context_embedded?, :any, acc)

    case right do
      %Ash.Query.Ref{} ->
        # If right side is a reference (i.e. an array column), fall back to = ANY(...)
        {right_expr, acc} =
          AshSql.Expr.dynamic_expr(query, right, bindings, context_embedded?, :any, acc)

        {:ok, Ecto.Query.dynamic(^left_expr in ^right_expr), acc}

      _ ->
        values =
          case right do
            %Ash.Query.Function.Type{arguments: [value | _]} -> value
            value -> value
          end

        values = if is_list(values), do: values, else: [values]

        # Build params and fragment_data in forward order (not reversed)
        # Param index 0 = left_expr, indices 1..N = values
        params = [{left_expr, :any}]

        {params, value_fragment_parts, _count, acc} =
          Enum.reduce(values, {params, [], 1, acc}, fn value, {params, parts, count, acc} ->
            {value_expr, acc} =
              AshSql.Expr.dynamic_expr(query, value, bindings, context_embedded?, :any, acc)

            separator =
              if count == 1, do: "", else: ", "

            typed_value =
              if left_type != :any do
                Ecto.Query.dynamic(type(^value_expr, ^left_type))
              else
                value_expr
              end

            new_parts = [{:raw, separator}, {:expr, {:^, [], [count]}}]
            {params ++ [{typed_value, :any}], parts ++ new_parts, count + 1, acc}
          end)

        # Build complete fragment: "" left_expr " IN (" v1 ", " v2 ... ")"
        fragment_data =
          [{:raw, ""}, {:expr, {:^, [], [0]}}, {:raw, " IN ("}] ++
            value_fragment_parts ++
            [{:raw, ")"}]

        dynamic = %Ecto.Query.DynamicExpr{
          fun: fn _query ->
            {{:fragment, [], fragment_data}, params, [], %{}}
          end,
          binding: [],
          file: __ENV__.file,
          line: __ENV__.line
        }

        {:ok, dynamic, acc}
    end
  end

  def expr(
        query,
        %Ash.Query.Ref{
          attribute: %Ash.Resource.Attribute{
            type: attr_type,
            constraints: constraints
          },
          bare?: true
        } = ref,
        bindings,
        embedded?,
        acc,
        type
      ) do
    if function_exported?(attr_type, :postgres_reference_expr, 3) do
      non_bare_ref = %{ref | bare?: nil}
      {expr, acc} = AshSql.Expr.dynamic_expr(query, non_bare_ref, bindings, embedded?, type, acc)

      case attr_type.postgres_reference_expr(attr_type, constraints, expr) do
        {:ok, bare_expr} -> {:ok, bare_expr, acc}
        :error -> :error
      end
    else
      :error
    end
  end

  def expr(
        query,
        %Ash.Query.Function.Error{} = value,
        bindings,
        embedded?,
        acc,
        type
      ) do
    resource = query.__ash_bindings__.resource
    repo = AshSql.dynamic_repo(resource, AshPostgres.SqlImplementation, query)

    if repo.immutable_expr_error?() do
      AshPostgres.Extensions.ImmutableRaiseError.immutable_error_expr(
        query,
        value,
        bindings,
        embedded?,
        acc,
        type
      )
    else
      :error
    end
  end

  def expr(
        query,
        %{name: :required!, arguments: [value_expr, attribute]} = required,
        bindings,
        embedded?,
        acc,
        type
      ) do
    pred_embedded? = Map.get(required, :embedded?, false)

    {value_dyn, acc} =
      AshSql.Expr.dynamic_expr(
        query,
        value_expr,
        bindings,
        pred_embedded? || embedded?,
        type,
        acc
      )

    resource =
      Map.get(attribute, :resource) ||
        raise("attribute must have :resource for ash_required!")

    field =
      Map.get(attribute, :name) ||
        Map.get(attribute, "name") ||
        raise("attribute must have :name for ash_required!")

    payload =
      %{
        exception: inspect(Ash.Error.Changes.Required),
        input: %{field: field, type: :attribute, resource: resource}
      }
      |> Jason.encode!()

    repo = AshSql.dynamic_repo(resource, AshPostgres.SqlImplementation, query)

    if repo.immutable_expr_error?() do
      AshPostgres.Extensions.ImmutableRaiseError.immutable_required_expr(
        query,
        required,
        bindings,
        embedded?,
        acc,
        type
      )
    else
      {:ok, Ecto.Query.dynamic(fragment("ash_required(?, ?::jsonb)", ^value_dyn, ^payload)), acc}
    end
  end

  # Date arithmetic on timestamptz values. Ecto's `datetime_add/3` (which `AshSql` uses,
  # so that every adapter gets its own dialect) casts to `timestamp`, which on postgres
  # depends on the session's `TimeZone`: on a session that isn't UTC, adding a day
  # across a DST change adds 23 or 25 hours, and the expression is only stable, not
  # immutable, so a bound parameter can't be folded to a constant while planning
  # (partitioned tables and TimescaleDB hypertables then plan every partition).
  #
  # For timestamptz values, the arithmetic is done on the UTC wall clock instead:
  # `timezone('UTC', x)` is the UTC wall-clock time, plus the interval, and
  # `timezone('UTC', ...)` back to an instant. Every step is immutable, and the result
  # is the UTC arithmetic Ash's own evaluation does. Naive timestamps are left to
  # `AshSql`, where they were already computed this way.
  def expr(
        query,
        %Ash.Query.Function.DateTimeAdd{
          arguments: [datetime, amount, interval],
          embedded?: pred_embedded?
        },
        bindings,
        embedded?,
        acc,
        type
      )
      when is_binary(interval) or is_atom(interval) do
    case timestamptz_type(type) || timestamptz_type(datetime) do
      nil ->
        :error

      tz_type ->
        embedded? = pred_embedded? || embedded?

        # The datetime is computed as timestamptz too, so a nested `datetime_add` (or
        # anything else typed by context) takes this path rather than producing a naive
        # timestamp that would then need a session-dependent cast.
        {datetime, acc} =
          AshSql.Expr.dynamic_expr(query, datetime, bindings, embedded?, tz_type, acc)

        {amount, acc} =
          AshSql.Expr.dynamic_expr(query, amount, bindings, embedded?, :integer, acc)

        {:ok, utc_add(datetime, amount, interval), acc}
    end
  end

  def expr(
        query,
        %Ash.Query.Function.DateTimeAdd{
          arguments: [datetime, duration],
          embedded?: pred_embedded?
        },
        bindings,
        embedded?,
        acc,
        type
      ) do
    case timestamptz_type(type) || timestamptz_type(datetime) do
      nil ->
        :error

      tz_type ->
        embedded? = pred_embedded? || embedded?

        {datetime, acc} =
          AshSql.Expr.dynamic_expr(query, datetime, bindings, embedded?, tz_type, acc)

        {duration, acc} =
          AshSql.Expr.dynamic_expr(query, duration, bindings, embedded?, :duration, acc)

        {:ok, utc_add_interval(datetime, duration), acc}
    end
  end

  def expr(
        query,
        %fun{arguments: [amount, interval], embedded?: pred_embedded?},
        bindings,
        embedded?,
        acc,
        type
      )
      when fun in [Ash.Query.Function.Ago, Ash.Query.Function.FromNow] and
             (is_binary(interval) or is_atom(interval)) do
    if timestamptz_type(type) do
      {amount, acc} =
        AshSql.Expr.dynamic_expr(
          query,
          amount,
          bindings,
          pred_embedded? || embedded?,
          :integer,
          acc
        )

      amount =
        if fun == Ash.Query.Function.Ago,
          do: Ecto.Query.dynamic(-1 * ^amount),
          else: amount

      {:ok, utc_add(as_of_or_now(query), amount, interval), acc}
    else
      :error
    end
  end

  def expr(
        query,
        %fun{arguments: [duration], embedded?: pred_embedded?},
        bindings,
        embedded?,
        acc,
        type
      )
      when fun in [Ash.Query.Function.Ago, Ash.Query.Function.FromNow] do
    if timestamptz_type(type) do
      {duration, acc} =
        AshSql.Expr.dynamic_expr(
          query,
          duration,
          bindings,
          pred_embedded? || embedded?,
          :duration,
          acc
        )

      now = as_of_or_now(query)

      dynamic =
        if fun == Ash.Query.Function.Ago do
          Ecto.Query.dynamic(
            fragment("timezone('UTC', timezone('UTC', ?::timestamptz) - ?)", ^now, ^duration)
          )
        else
          utc_add_interval(now, duration)
        end

      {:ok, dynamic, acc}
    else
      :error
    end
  end

  def expr(
        query,
        %fun{arguments: [time_zone], embedded?: pred_embedded?, extra: extra},
        bindings,
        embedded?,
        acc,
        _type
      )
      when fun in [Ash.Query.Function.LocalNow, Ash.Query.Function.LocalToday] do
    instant = local_time_anchor(query, extra)

    {local, acc} =
      local_time(query, instant, time_zone, bindings, pred_embedded? || embedded?, acc)

    local =
      if fun == Ash.Query.Function.LocalToday do
        Ecto.Query.dynamic(fragment("?::date", ^local))
      else
        local
      end

    {:ok, local, acc}
  end

  def expr(
        query,
        %fun{arguments: [amount, interval, time_zone], embedded?: pred_embedded?, extra: extra},
        bindings,
        embedded?,
        acc,
        _type
      )
      when fun in [Ash.Query.Function.LocalAgo, Ash.Query.Function.LocalFromNow] and
             (is_binary(interval) or is_atom(interval)) do
    embedded? = pred_embedded? || embedded?
    {amount, acc} = AshSql.Expr.dynamic_expr(query, amount, bindings, embedded?, :integer, acc)

    amount =
      if fun == Ash.Query.Function.LocalAgo,
        do: Ecto.Query.dynamic(-1 * ^amount),
        else: amount

    instant = utc_add(local_time_anchor(query, extra), amount, interval)
    {local, acc} = local_time(query, instant, time_zone, bindings, embedded?, acc)
    {:ok, local, acc}
  end

  def expr(
        query,
        %fun{arguments: [duration, time_zone], embedded?: pred_embedded?, extra: extra},
        bindings,
        embedded?,
        acc,
        _type
      )
      when fun in [Ash.Query.Function.LocalAgo, Ash.Query.Function.LocalFromNow] do
    embedded? = pred_embedded? || embedded?

    {duration, acc} =
      AshSql.Expr.dynamic_expr(query, duration, bindings, embedded?, :duration, acc)

    duration =
      if fun == Ash.Query.Function.LocalAgo,
        do: Ecto.Query.dynamic(fragment("-(?::interval)", ^duration)),
        else: duration

    instant = utc_add_interval(local_time_anchor(query, extra), duration)
    {local, acc} = local_time(query, instant, time_zone, bindings, embedded?, acc)
    {:ok, local, acc}
  end

  def expr(
        _query,
        _expr,
        _bindings,
        _embedded?,
        _acc,
        _type
      ) do
    :error
  end

  defp local_time_anchor(query, extra) do
    (extra[:as_of] || as_of_or_now(query))
    |> DateTime.shift_zone!("Etc/UTC")
  end

  defp local_time(query, instant, time_zone, bindings, embedded?, acc) do
    {time_zone, acc} =
      AshSql.Expr.dynamic_expr(query, time_zone, bindings, embedded?, :string, acc)

    {Ecto.Query.dynamic(fragment("timezone(?::text, ?::timestamptz)", ^time_zone, ^instant)), acc}
  end

  # `amount` whole `interval`s (`:day`, `:month`, ...) after `datetime`, in UTC. The unit
  # goes as an interval parameter (Postgrex sends a `Duration` as one), so one fragment
  # covers every unit and nothing is parsed from text.
  defp utc_add(datetime, amount, interval) do
    unit = one(interval)

    Ecto.Query.dynamic(
      fragment(
        "timezone('UTC', timezone('UTC', ?::timestamptz) + (?::numeric * ?::interval))",
        ^datetime,
        ^amount,
        ^unit
      )
    )
  end

  defp utc_add_interval(datetime, duration) do
    Ecto.Query.dynamic(
      fragment("timezone('UTC', timezone('UTC', ?::timestamptz) + ?)", ^datetime, ^duration)
    )
  end

  defp one(interval) when is_binary(interval), do: one(String.to_existing_atom(interval))
  defp one(:year), do: Duration.new!(year: 1)
  defp one(:month), do: Duration.new!(month: 1)
  defp one(:week), do: Duration.new!(week: 1)
  defp one(:day), do: Duration.new!(day: 1)
  defp one(:hour), do: Duration.new!(hour: 1)
  defp one(:minute), do: Duration.new!(minute: 1)
  defp one(:second), do: Duration.new!(second: 1)
  defp one(:millisecond), do: Duration.new!(microsecond: {1000, 6})
  defp one(:microsecond), do: Duration.new!(microsecond: {1, 6})

  defp as_of_or_now(query) do
    get_in(query.__ash_bindings__, [:context, :private, :as_of]) || DateTime.utc_now()
  end

  # The type (as `{type, constraints}`), or the type of an expression, if it is stored as
  # timestamptz; otherwise nil.
  defp timestamptz_type(nil), do: nil
  defp timestamptz_type({:array, _}), do: nil

  defp timestamptz_type({type, constraints}) when is_atom(type) and is_list(constraints) do
    case Ash.Type.get_type(type) do
      type when is_atom(type) and not is_nil(type) ->
        if Code.ensure_loaded?(type) and function_exported?(type, :storage_type, 1) and
             type.storage_type(constraints) in [:timestamptz, :"timestamptz(6)"] do
          {type, constraints}
        end

      _ ->
        nil
    end
  end

  defp timestamptz_type(type) when is_atom(type), do: timestamptz_type({type, []})

  defp timestamptz_type(expr) do
    case Ash.Expr.determine_type(expr) do
      {:ok, type} -> timestamptz_type(type)
      _ -> nil
    end
  end

  defp boolean_type?(Ash.Type.Boolean), do: true
  defp boolean_type?({Ash.Type.Boolean, _}), do: true
  defp boolean_type?(:boolean), do: true
  defp boolean_type?({:boolean, _}), do: true
  defp boolean_type?(_), do: false

  @impl true
  def table(resource) do
    AshPostgres.DataLayer.Info.table(resource)
  end

  @impl true
  def schema(resource) do
    AshPostgres.DataLayer.Info.schema(resource)
  end

  @impl true
  def repo(resource, kind) do
    AshPostgres.DataLayer.Info.repo(resource, kind)
  end

  @impl true
  def simple_join_first_aggregates(resource) do
    AshPostgres.DataLayer.Info.simple_join_first_aggregates(resource)
  end

  @impl true
  def list_aggregate(resource) do
    if AshPostgres.DataLayer.Info.pg_version_matches?(resource, ">= 16.0.0") do
      "any_value"
    else
      "array_agg"
    end
  end

  @impl true
  def parameterized_type({:parameterized, _} = type, _) do
    type
  end

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

  def parameterized_type({type, constraints}, []) do
    parameterized_type(type, constraints)
  end

  def parameterized_type(Ash.Type.CiString, constraints) do
    parameterized_type(AshPostgres.Type.CiStringWrapper, constraints)
  end

  def parameterized_type(Ash.Type.Range, constraints) do
    parameterized_type(AshPostgres.Type.Range, constraints)
  end

  def parameterized_type({Ash.Type.Range, constraints}, _) do
    parameterized_type(AshPostgres.Type.Range, constraints)
  end

  def parameterized_type(Ash.Type.String, constraints) do
    parameterized_type(AshPostgres.Type.StringWrapper, constraints)
  end

  def parameterized_type(:tsquery, constraints) do
    parameterized_type(AshPostgres.Tsquery, constraints)
  end

  def parameterized_type(type, constraints) do
    if Ash.Type.ash_type?(type) do
      cast_in_query? =
        Ash.Type.cast_in_query?(type, constraints)

      if cast_in_query? do
        type = Ash.Type.ecto_type(type)

        parameterized_type(type, constraints)
      else
        nil
      end
    else
      if is_atom(type) && :erlang.function_exported(type, :type, 1) do
        if type == :ci_string do
          :citext
        else
          case type.type(constraints || []) do
            :ci_string ->
              parameterized_type(AshPostgres.Type.CiStringWrapper, constraints)

            _ ->
              Ecto.ParameterizedType.init(type, constraints || [])
          end
        end
      else
        if type == :ci_string do
          :citext
        else
          type
        end
      end
    end
  end

  @impl true
  def determine_types(mod, args, returns \\ nil) do
    returns = normalize_returns(returns)

    {types, new_returns} = Ash.Expr.determine_types(mod, args, returns)

    {types, new_returns || returns}
  end

  @impl true
  def determine_types(mod, args, returns, operand_types) do
    returns = normalize_returns(returns)

    {types, new_returns} =
      Ash.Expr.determine_types_with_operand_types(mod, args, operand_types, returns)

    {types, new_returns || returns}
  end

  defp normalize_returns(returns) do
    case returns do
      {:parameterized, _} -> nil
      {:array, {:parameterized, _}} -> nil
      {:array, {type, constraints}} when type != :array -> {type, [items: constraints]}
      {:array, _} -> nil
      {type, constraints} -> {type, constraints}
      other -> other
    end
  end
end
