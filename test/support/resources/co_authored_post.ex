# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.CoAuthorPost do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "co_authored_posts"
    repo AshPostgres.TestRepo
  end

  attributes do
    attribute :role, :atom do
      allow_nil?(false)
      public?(true)

      constraints(one_of: [:editor, :writer, :proof_reader])
    end

    attribute :was_cancelled_at, :datetime do
      allow_nil?(true)
      public?(true)
    end
  end

  actions do
    default_accept(:*)

    defaults([:read, :update, :destroy])

    create :create do
    end

    update :cancel_author do
      change(set_attribute(:was_cancelled_at, DateTime.utc_now()))
    end

    update :uncancel_author do
      change(set_attribute(:was_cancelled_at, nil))
    end
  end

  code_interface do
    define(:cancel, action: :cancel_author)
    define(:uncancel, action: :uncancel_author)
  end

  relationships do
    belongs_to :author, AshPostgres.Test.Author do
      primary_key?(true)
      public?(true)
      allow_nil?(false)
    end

    belongs_to :post, AshPostgres.Test.Post do
      primary_key?(true)
      public?(true)
      allow_nil?(false)
    end
  end
end
