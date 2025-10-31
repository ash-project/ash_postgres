# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.DataLayerMetadataTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Post

  require Ash.Query

  test "update_query sets bulk metadata on returned records" do
    _post1 = Ash.create!(Post, %{title: "title1"})
    _post2 = Ash.create!(Post, %{title: "title2"})
    _post3 = Ash.create!(Post, %{title: "title3"})

    ash_query = Ash.Query.new(Post)
    {:ok, query} = Ash.Query.data_layer_query(ash_query)

    ref = make_ref()

    changeset = %Ash.Changeset{
      resource: Post,
      action_type: :update,
      data: %Post{},
      attributes: %{title: "updated"},
      atomics: [],
      filter: nil,
      context: %{bulk_update: %{index: 0, ref: ref}},
      domain: AshPostgres.Test.Domain,
      tenant: nil,
      timeout: :infinity
    }

    {:ok, results} =
      AshPostgres.DataLayer.update_query(query, changeset, Post, return_records?: true)

    assert is_list(results)
    assert length(results) > 0

    Enum.each(results, fn result ->
      assert is_integer(result.__metadata__.bulk_update_index)
      assert result.__metadata__.bulk_action_ref == ref
    end)
  end

  test "destroy_query sets bulk metadata on returned records" do
    _post1 = Ash.create!(Post, %{title: "title1"})
    _post2 = Ash.create!(Post, %{title: "title2"})
    _post3 = Ash.create!(Post, %{title: "title3"})

    ash_query = Ash.Query.new(Post)
    {:ok, query} = Ash.Query.data_layer_query(ash_query)

    ref = make_ref()

    changeset = %Ash.Changeset{
      resource: Post,
      action_type: :destroy,
      data: %Post{},
      attributes: %{},
      atomics: [],
      filter: nil,
      context: %{bulk_destroy: %{index: 0, ref: ref}},
      domain: AshPostgres.Test.Domain,
      tenant: nil,
      timeout: :infinity
    }

    {:ok, results} =
      AshPostgres.DataLayer.destroy_query(query, changeset, Post, return_records?: true)

    assert is_list(results)
    assert length(results) > 0

    Enum.each(results, fn result ->
      assert is_integer(result.__metadata__.bulk_destroy_index)
      assert result.__metadata__.bulk_action_ref == ref
    end)
  end
end
