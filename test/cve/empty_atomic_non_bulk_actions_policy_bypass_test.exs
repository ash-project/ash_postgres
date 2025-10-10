# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.EmptyAtomicNonBulkActionsPolicyBypassTest do
  @moduledoc """
  This is test verifies the fix for the following CVE:

  https://github.com/ash-project/ash_postgres/security/advisories/GHSA-hf59-7rwq-785m
  """
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.PostWithEmptyUpdate

  require Ash.Query

  test "a forbidden error is appropriately raised on atomic upgraded, empty, non-bulk actions" do
    post =
      PostWithEmptyUpdate
      |> Ash.Changeset.for_create(:create, %{})
      |> Ash.create!()

    assert_raise Ash.Error.Forbidden, fn ->
      post
      |> Ash.Changeset.for_update(:empty_update, %{}, authorize?: true)
      |> Ash.update!()
    end
  end
end
