# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.UpdateAllTest do
  @moduledoc """
  Verifies `Ash.update_all/3` (record-by-record bulk update) against a real transactional data
  layer, focusing on what ETS cannot show: with `transaction: :per_record` a single record failing
  *at write time* (a check-constraint violation) rolls back only that record while its siblings
  commit, whereas the default `transaction: :batch` rolls the whole batch back.

  `AshPostgres.Test.Post` has `check_constraint(:price, "price_must_be_positive", check: "price > 0")`,
  so a negative `price` produces a genuine Postgres write-time error mid-batch.
  """
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.Post

  require Ash.Query

  defp create_post(title, price) do
    Post
    |> Ash.Changeset.for_create(:create, %{title: title, price: price})
    |> Ash.create!()
  end

  defp reload(post), do: Ash.get!(Post, post.id)

  # Error classes wrap the concrete error; dig out the first one of the given type.
  defp find_error(%struct{} = error, struct), do: error

  defp find_error(%{errors: errors}, struct) when is_list(errors) do
    Enum.find_value(errors, &find_error(&1, struct))
  end

  defp find_error(_error, _struct), do: nil

  describe "transaction: :per_record" do
    test "a write-time failure rolls back only the failing record; siblings commit (contrast: :batch rolls back everything)" do
      # Same mid-batch failure (the second record violates check_constraint price > 0)
      # run two ways: once per-record, once as a single batch. Each gets its own posts
      # so the two runs can't interfere; the contrast is asserted at the end.
      pr1 = create_post("one", 10)
      pr2 = create_post("two", 10)
      pr3 = create_post("three", 10)

      b1 = create_post("one", 10)
      b2 = create_post("two", 10)
      b3 = create_post("three", 10)

      per_record_result =
        Ash.update_all(
          [
            {pr1, %{price: 1}},
            {pr2, %{price: -5}},
            {pr3, %{price: 3}}
          ],
          :update,
          resource: Post,
          transaction: :per_record,
          stop_on_error?: false,
          return_records?: true,
          return_errors?: true,
          sorted?: true
        )

      batch_result =
        Ash.update_all(
          [
            {b1, %{price: 1}},
            {b2, %{price: -5}},
            {b3, %{price: 3}}
          ],
          :update,
          resource: Post,
          transaction: :batch,
          stop_on_error?: false,
          return_records?: true,
          return_errors?: true
        )

      assert %Ash.BulkResult{
               status: :partial_success,
               error_count: 1,
               records: records,
               errors: [error]
             } = per_record_result

      assert Enum.map(records, & &1.price) == [1, 3]
      assert Enum.map(records, & &1.__metadata__.bulk_update_index) == [0, 2]

      invalid = find_error(error, Ash.Error.Changes.InvalidAttribute)
      assert invalid.field == :price
      assert invalid.message =~ "bad price"
      assert [1 | _] = error.path

      assert %Ash.BulkResult{status: batch_status} = batch_result
      assert batch_status in [:error, :partial_success]

      # The crucial contrast ETS could not make. With :per_record the failing record is
      # rolled back to its own savepoint while its siblings commit; with :batch every
      # record shares one transaction, so the good writes roll back along with the bad.
      assert reload(pr1).price == 1
      assert reload(pr3).price == 3
      assert reload(pr2).price == 10

      assert reload(b1).price == 10
      assert reload(b2).price == 10
      assert reload(b3).price == 10
    end

    test "every record commits when none fail" do
      p1 = create_post("a", 10)
      p2 = create_post("b", 10)

      result =
        Ash.update_all(
          [{p1, %{price: 4}}, {p2, %{price: 7}}],
          :update,
          resource: Post,
          transaction: :per_record,
          return_records?: true,
          sorted?: true
        )

      assert %Ash.BulkResult{status: :success, records: [r1, r2]} = result
      assert r1.price == 4
      assert r2.price == 7
      assert reload(p1).price == 4
      assert reload(p2).price == 7
    end
  end
end
