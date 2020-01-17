defmodule AshPostgresTest do
  use ExUnit.Case
  doctest AshPostgres

  test "greets the world" do
    assert AshPostgres.hello() == :world
  end
end
