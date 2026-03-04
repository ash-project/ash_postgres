# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Functions.RequiredErrorTest do
  use ExUnit.Case, async: true

  alias AshPostgres.Functions.RequiredError

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
end
