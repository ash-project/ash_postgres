# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.ActorAggregateInCalculationTest do
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.{Comment, Post}

  test "an aggregate filtered by the actor gives the same count inside a calculation" do
    post = Ash.Seed.seed!(Post, %{title: "post"})

    for title <- ["mine", "mine", "theirs"] do
      Ash.Seed.seed!(Comment, %{title: title, post_id: post.id})
    end

    actor = %{title: "mine"}

    assert Ash.load!(post, :count_of_comments_titled_by_actor, actor: actor, authorize?: false).count_of_comments_titled_by_actor ==
             2

    assert Ash.load!(post, :count_of_comments_titled_by_actor_plus_one,
             actor: actor,
             authorize?: false
           ).count_of_comments_titled_by_actor_plus_one ==
             3
  end
end
