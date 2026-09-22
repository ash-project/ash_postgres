# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.RepertoireErrorTest do
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.Post

  require Ash.Query

  # PostgreSQL rejects both with `22021 character_not_in_repertoire`
  @nul "a" <> <<0>> <> "b"
  @invalid_utf8 "a" <> <<255>> <> "b"

  test "a filter with a NUL byte is an invalid filter value" do
    assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.InvalidFilterValue{} = error]}} =
             Post |> Ash.Query.filter(title == ^@nul) |> Ash.read()

    assert error.message =~ "invalid byte sequence"
  end

  test "an update with a NUL byte names the attribute" do
    post = Post |> Ash.Changeset.for_create(:create, %{title: "title"}) |> Ash.create!()

    assert {:error, %Ash.Error.Invalid{errors: [error]}} =
             post |> Ash.Changeset.for_update(:update, %{title: @nul}) |> Ash.update()

    assert %Ash.Error.Changes.InvalidAttribute{field: :title, value: @nul} = error
  end

  test "an update with invalid UTF-8 names the attribute" do
    post = Post |> Ash.Changeset.for_create(:create, %{title: "title"}) |> Ash.create!()

    assert {:error,
            %Ash.Error.Invalid{errors: [%Ash.Error.Changes.InvalidAttribute{field: :title}]}} =
             post |> Ash.Changeset.for_update(:update, %{title: @invalid_utf8}) |> Ash.update()
  end

  test "a create with a NUL byte is an invalid change" do
    assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Changes.InvalidChanges{} = error]}} =
             Post |> Ash.Changeset.for_create(:create, %{title: @nul}) |> Ash.create()

    assert error.message =~ "invalid byte sequence"
  end

  test "ordinary text still stores and filters" do
    Post |> Ash.Changeset.for_create(:create, %{title: "plain"}) |> Ash.create!()
    assert [%Post{}] = Post |> Ash.Query.filter(title == "plain") |> Ash.read!()
  end
end
