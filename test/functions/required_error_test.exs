# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.RequiredErrorCoreFunctionTest do
  use ExUnit.Case, async: true

  alias AshPostgres.DataLayer
  alias AshPostgres.Test.Post

  alias Ash.Query.Function.RequiredError

  test "ash_required!/2 returns error when value is nil" do
    attribute = %{name: :title, resource: MyApp.Post}

    assert {:error, %Ash.Error.Changes.Required{} = err} =
             RequiredError.evaluate(%{arguments: [nil, attribute]})

    assert err.field == :title
    assert err.resource == MyApp.Post
    assert err.type == :attribute
  end

  test "ash_required!/2 returns value when non-nil" do
    attribute = %{name: :title, resource: MyApp.Post}

    assert {:known, "hello"} =
             RequiredError.evaluate(%{arguments: ["hello", attribute]})
  end

  test "required!/2 contract matches core for false, 0, and empty string" do
    attribute = %{name: :title, resource: MyApp.Post}

    assert {:known, false} = RequiredError.evaluate(%{arguments: [false, attribute]})
    assert {:known, 0} = RequiredError.evaluate(%{arguments: [0, attribute]})
    assert {:known, ""} = RequiredError.evaluate(%{arguments: ["", attribute]})
  end

  test "required!/2 accepts string name key and validates helper metadata" do
    attribute = %{"name" => :title, resource: MyApp.Post}

    assert {:error, %Ash.Error.Changes.Required{} = err} =
             RequiredError.evaluate(%{arguments: [nil, attribute]})

    assert err.field == :title
    assert RequiredError.can_return_nil?(nil) == false
    assert RequiredError.evaluate_nil_inputs?() == true
  end

  test "required!/2 new/1 returns core-aligned argument error" do
    assert {:error, "required! expects (value, attribute)"} = RequiredError.new([])
    assert {:error, "required! expects (value, attribute)"} = RequiredError.new([:only_one])
  end

  test "required!/2 only needs attribute metadata when value is nil" do
    assert {:known, "hello"} =
             RequiredError.evaluate(%{arguments: ["hello", %{resource: MyApp.Post}]})
  end

  test "required!/2 raises with clear errors for missing metadata on nil values" do
    assert_raise RuntimeError, ~r/attribute must have :resource for required!/, fn ->
      RequiredError.evaluate(%{arguments: [nil, %{name: :title}]})
    end

    assert_raise RuntimeError, ~r/attribute must have :name for required!/, fn ->
      RequiredError.evaluate(%{arguments: [nil, %{resource: MyApp.Post}]})
    end
  end

  test "uses required error function from ash core" do
    source =
      RequiredError.module_info(:compile)
      |> Keyword.fetch!(:source)
      |> List.to_string()
      |> String.replace("\\", "/")

    assert String.ends_with?(source, "/ash/lib/ash/query/function/required_error.ex")
  end

  test "can?(:required_error) is disabled when ash-functions is unavailable" do
    on_exit(fn ->
      Application.delete_env(:ash_postgres, :no_extensions)
    end)

    Application.put_env(:ash_postgres, :no_extensions, ["ash-functions"])

    refute DataLayer.can?(Post, :required_error)
  end

  test "can?(:required_error) is enabled when ash-functions is available" do
    Application.delete_env(:ash_postgres, :no_extensions)

    assert DataLayer.can?(Post, :required_error)
  end
end
