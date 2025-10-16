# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.ImmutableRaiseErrorTest do
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.ImmutableErrorTester

  require Ash.Query

  setup do
    original = Application.get_env(:ash_postgres, :test_repo_use_immutable_errors?)
    Application.put_env(:ash_postgres, :test_repo_use_immutable_errors?, true)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:ash_postgres, :test_repo_use_immutable_errors?)
      else
        Application.put_env(:ash_postgres, :test_repo_use_immutable_errors?, original)
      end
    end)

    :ok
  end

  describe "atomic error payloads" do
    test "update_one returns InvalidAttribute error with expression value" do
      tester = create_tester()

      # The :update_one validation builds an error with a single expression value and literal
      # values (non-empty base input).
      assert {:error, %Ash.Error.Invalid{errors: [error]}} =
               tester
               |> Ash.Changeset.for_update(:update_one, %{integer_value: 99})
               |> Ash.update()

      assert %Ash.Error.Changes.InvalidAttribute{} = error
      assert error.field == :integer_value
      assert error.value == 99
    end

    test "update_many returns custom error containing all expression values" do
      tester = create_tester()

      # The :update_many validation builds an error that include many (all attributes) value
      # expressions, and zero literal values (empty base input).
      assert {:error, %Ash.Error.Invalid{errors: [error]}} =
               tester
               |> Ash.Changeset.for_update(:update_many, %{})
               |> Ash.update()

      assert %ImmutableErrorTester.Error{} = error

      assert error.atom_value == "initial_atom"
      assert error.string_value == "initial string"
      assert error.integer_value == 10
      assert error.float_value == 1.5
      assert error.boolean_value == true

      assert error.struct_value == %{
               "active?" => true,
               "count" => 1,
               "name" => "initial"
             }

      assert error.uuid_value == "00000000-0000-0000-0000-000000000000"
      assert error.date_value == "2024-01-01"
      assert error.time_value == "12:00:00"
      assert error.ci_string_value == "Initial String"
      assert error.naive_datetime_value == "2024-01-01T12:00:00"
      assert error.utc_datetime_value == "2024-01-01T00:01:00"
      assert error.timestamptz_value == "2024-01-01T00:02:00+00:00"
      assert error.string_array_value == ["one", "two"]

      # Native value for :awaiting is 0
      assert error.response_value == 0
      assert error.nullable_string_value == nil
    end

    test "update_literal returns literal payload" do
      tester = create_tester()

      # The :update_literal validation builds an error with only literal values, zero expression values.
      assert {:error, %Ash.Error.Invalid{errors: [error]}} =
               tester
               |> Ash.Changeset.for_update(:update_literal, %{})
               |> Ash.update()

      assert error.string_value == "literal string"
      assert error.integer_value == 123
      assert error.float_value == 9.99
      assert error.boolean_value == false
      assert error.string_array_value == ["alpha", "beta"]
      assert error.nullable_string_value == nil
    end
  end

  defp create_tester do
    input =
      %{
        atom_value: :initial_atom,
        string_value: "initial string",
        integer_value: 10,
        float_value: 1.5,
        boolean_value: true,
        struct_value: ImmutableErrorTester.Struct.new!(name: "initial", count: 1, active?: true),
        uuid_value: "00000000-0000-0000-0000-000000000000",
        date_value: ~D[2024-01-01],
        time_value: ~T[12:00:00],
        ci_string_value: "Initial String",
        naive_datetime_value: ~N[2024-01-01 12:00:00],
        utc_datetime_value: ~U[2024-01-01 00:01:00.00Z],
        timestamptz_value: ~U[2024-01-01 00:02:00.00Z],
        string_array_value: ["one", "two"],
        response_value: :awaiting,
        nullable_string_value: nil
      }

    ImmutableErrorTester
    |> Ash.Changeset.for_create(:create, input)
    |> Ash.create!()
  end
end
