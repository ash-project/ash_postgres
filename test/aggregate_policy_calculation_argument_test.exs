# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.AggregatePolicyCalculationArgumentTest do
  @moduledoc false
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.{Comment, Post}

  test "an authorized aggregate whose destination policy calls a calculation module with arguments" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "post"})
      |> Ash.create!(authorize?: false)

    for title <- ["yes", "no"] do
      Comment
      |> Ash.Changeset.for_create(:create, %{title: title})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!(authorize?: false)
    end

    # The actor deliberately does not relate to the post's organization, so the
    # `bypass` on `Comment` does not apply and the `:read_in_titles` policy runs.
    actor = %{titles: ["yes"]}

    assert %{count_of_comments_in_titles: 1} =
             Ash.load!(post, :count_of_comments_in_titles, actor: actor, authorize?: true)
  end
end
