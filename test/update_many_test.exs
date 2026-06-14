# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.UpdateManyTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Post

  require Ash.Query

  # `update_many` is implemented as a single SQL MERGE, which requires PostgreSQL 17.
  @moduletag :postgres_17

  defp create_post(attrs) do
    Post
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create!()
  end

  test "applies a distinct input to each record in one operation" do
    a = create_post(%{title: "a", score: 1})
    b = create_post(%{title: "b", score: 2})

    %Ash.BulkResult{status: :success, records: records} =
      Ash.update_many(
        [{a, %{title: "a!"}}, {b, %{score: 99}}],
        Post,
        :update,
        return_records?: true
      )

    by_id = Map.new(records, &{&1.id, &1})

    # heterogeneous inputs in a single MERGE: each record only changed what it was given
    assert by_id[a.id].title == "a!"
    assert by_id[a.id].score == 1
    assert by_id[b.id].title == "b"
    assert by_id[b.id].score == 99
  end

  test "every returned record is tagged with :upsert_action :update" do
    a = create_post(%{title: "a"})

    %Ash.BulkResult{records: [record]} =
      Ash.update_many([{a, %{title: "b"}}], Post, :update, return_records?: true)

    assert Ash.Resource.get_metadata(record, :upsert_action) == :update
  end

  test "preserves the only-if-changed behavior of update timestamps" do
    post = create_post(%{title: "a"})
    original = Ash.get!(Post, post.id)

    # no-op: setting the same value must not bump updated_at
    %Ash.BulkResult{records: [unchanged]} =
      Ash.update_many([{original, %{title: original.title}}], Post, :update,
        return_records?: true
      )

    assert DateTime.compare(unchanged.updated_at, original.updated_at) == :eq

    # a real change does bump it
    %Ash.BulkResult{records: [changed]} =
      Ash.update_many([{original, %{title: "different"}}], Post, :update, return_records?: true)

    assert DateTime.compare(changed.updated_at, original.updated_at) == :gt
  end

  test "a missing record yields a StaleRecord error, a missing identifier a NotFound error" do
    real = create_post(%{title: "real"})
    ghost_record = %{real | id: Ash.UUID.generate()}

    %Ash.BulkResult{status: :partial_success, records: records, errors: errors} =
      Ash.update_many(
        [
          {real, %{title: "updated"}},
          {ghost_record, %{title: "no"}},
          {Ash.UUID.generate(), %{title: "no"}}
        ],
        Post,
        :update,
        return_records?: true,
        return_errors?: true
      )

    assert [%{title: "updated"}] = records
    error_types = Enum.map(errors, & &1.__struct__) |> Enum.sort()
    assert error_types == Enum.sort([Ash.Error.Changes.StaleRecord, Ash.Error.Query.NotFound])
  end

  test "a shared atomic change is applied across the batch" do
    a = create_post(%{title: "a", limited_score: 1})
    b = create_post(%{title: "b", limited_score: 10})

    %Ash.BulkResult{status: :success, records: records} =
      Ash.update_many(
        [{a, %{amount: 5}}, {b, %{amount: 5}}],
        Post,
        :add_to_limited_score,
        return_records?: true
      )

    by_id = Map.new(records, &{&1.id, &1.limited_score})
    assert by_id[a.id] == 6
    assert by_id[b.id] == 15
  end

  test "the :stream strategy applies distinct inputs via per-record updates" do
    a = create_post(%{title: "a"})
    b = create_post(%{title: "b"})

    # `:change_title` has a non-atomic change, so this exercises the streaming fallback path.
    %Ash.BulkResult{status: :success, records: records} =
      Ash.update_many(
        [{a, %{title: "a!"}}, {b, %{title: "b!"}}],
        Post,
        :change_title,
        strategy: [:stream],
        return_records?: true
      )

    by_id = Map.new(records, &{&1.id, &1.title})
    assert by_id[a.id] == "a!"
    assert by_id[b.id] == "b!"
  end

  test "the default :atomic strategy fails with a single error when a change cannot be made atomic" do
    posts = for i <- 1..5, do: create_post(%{title: "t#{i}"})
    inputs = Enum.map(posts, fn p -> {p, %{title: "#{p.title}!"}} end)

    %Ash.BulkResult{status: :error, errors: errors, error_count: error_count} =
      Ash.update_many(inputs, Post, :change_title,
        return_records?: true,
        return_errors?: true
      )

    # not one error per row — a single operation-level error
    assert error_count == 1
    assert [%Ash.Error.Invalid.NoMatchingBulkStrategy{}] = errors
  end

  test "the :atomic strategy is enforced for identifier inputs too (not silently streamed)" do
    a = create_post(%{title: "a"})

    %Ash.BulkResult{status: :error, records: records} =
      Ash.update_many([{%{id: a.id}, %{title: "a!"}}], Post, :change_title,
        return_records?: true,
        return_errors?: true
      )

    # the non-atomic change was not applied
    assert records in [nil, []]
    assert Ash.get!(Post, a.id).title == "a"
  end

  test "updates more records than fit in a single batch under the :atomic_batches strategy" do
    posts = for i <- 1..10, do: create_post(%{title: "t#{i}", score: i})
    inputs = Enum.map(posts, fn p -> {p, %{score: p.score + 100}} end)

    %Ash.BulkResult{status: :success} =
      result =
      Ash.update_many(inputs, Post, :update,
        strategy: [:atomic_batches],
        batch_size: 3,
        return_records?: true
      )

    assert length(result.records) == 10
    assert Enum.all?(result.records, &(&1.score >= 101))
  end
end
