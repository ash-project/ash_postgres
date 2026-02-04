# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.ImmutableErrorTester do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  require Ash.Expr
  import Ash.Expr

  postgres do
    table "immutable_error_testers"
    repo(AshPostgres.TestRepo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:atom_value, :atom, allow_nil?: false, public?: true)
    attribute(:string_value, :string, allow_nil?: false, public?: true)
    attribute(:integer_value, :integer, allow_nil?: false, public?: true)
    attribute(:float_value, :float, allow_nil?: false, public?: true)
    attribute(:boolean_value, :boolean, allow_nil?: false, public?: true)

    attribute(:struct_value, AshPostgres.Test.ImmutableErrorTester.Struct,
      allow_nil?: false,
      public?: true
    )

    attribute(:uuid_value, Ash.Type.UUID, allow_nil?: false, public?: true)
    attribute(:date_value, :date, allow_nil?: false, public?: true)
    attribute(:time_value, :time, allow_nil?: false, public?: true)
    attribute(:ci_string_value, :ci_string, allow_nil?: false, public?: true)
    attribute(:naive_datetime_value, :naive_datetime, allow_nil?: false, public?: true)
    attribute(:utc_datetime_value, :utc_datetime, allow_nil?: false, public?: true)
    attribute(:timestamptz_value, AshPostgres.Timestamptz, allow_nil?: false, public?: true)
    attribute(:string_array_value, {:array, :string}, allow_nil?: false, public?: true)
    attribute(:response_value, AshPostgres.Test.Types.Response, allow_nil?: false, public?: true)
    attribute(:nullable_string_value, :string, public?: true)
  end

  actions do
    defaults([:read])

    create :create do
      accept(:*)
    end

    update :update_one do
      argument(:integer_value, :integer, allow_nil?: false)
      change(atomic_update(:integer_value, expr(^arg(:integer_value))))
      validate(AshPostgres.Test.ImmutableErrorTester.Validations.UpdateOne)
    end

    update :update_many do
      accept(:*)
      validate(AshPostgres.Test.ImmutableErrorTester.Validations.UpdateMany)
    end

    update :update_literal do
      validate(AshPostgres.Test.ImmutableErrorTester.Validations.UpdateLiteral)
    end
  end
end
