# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.CommentLike do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [
      Ash.Policy.Authorizer
    ]

  policies do
    bypass action_type(:read) do
      # Check that the comment is in the same org (via post) as actor
      authorize_if(relates_to_actor_via([:post, :organization, :users]))
    end
  end

  postgres do
    table "comment_likes"
    repo(AshPostgres.TestRepo)

    references do
      reference(:author,
        on_delete: :delete,
        on_update: :update,
        name: "comment_like_author_fkey"
      )

      reference(:comment,
        on_delete: :delete,
        on_update: :update,
        name: "comment_like_comment_fkey"
      )
    end
  end

  actions do
    default_accept(:*)
    defaults([:create, :read, :update, :destroy])
  end

  relationships do
    belongs_to(:author, AshPostgres.Test.Author) do
      allow_nil?(false)
      public?(true)
      primary_key?(true)
    end

    belongs_to(:comment, AshPostgres.Test.Comment) do
      allow_nil?(false)
      public?(true)
      primary_key?(true)
    end
  end
end
