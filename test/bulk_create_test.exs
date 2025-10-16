# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.BulkCreateTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{IntegerPost, Post, Record}

  require Ash.Query
  import Ash.Expr

  describe "bulk creates" do
    test "bulk creates insert each input" do
      Ash.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create)

      assert [%{title: "fred"}, %{title: "george"}] =
               Post
               |> Ash.Query.sort(:title)
               |> Ash.read!()
    end

    test "bulk creates perform before action hooks" do
      Ash.bulk_create!(
        [%{title: "before_action"}, %{title: "before_action"}],
        Post,
        :create_with_before_action,
        return_errors?: true,
        return_records?: true
      )

      assert [%{title: "before_action"}, %{title: "before_action"}] =
               Post
               |> Ash.Query.sort(:title)
               |> Ash.read!()
    end

    test "bulk creates can be streamed" do
      assert [{:ok, %{title: "fred"}}, {:ok, %{title: "george"}}] =
               Ash.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create,
                 return_stream?: true,
                 return_records?: true
               )
               |> Enum.sort_by(fn {:ok, result} -> result.title end)
    end

    test "bulk creates can upsert" do
      assert [
               {:ok, %{title: "fred", uniq_one: "one", uniq_two: "two", price: 10}},
               {:ok, %{title: "george", uniq_one: "three", uniq_two: "four", price: 20}}
             ] =
               Ash.bulk_create!(
                 [
                   %{title: "fred", uniq_one: "one", uniq_two: "two", price: 10},
                   %{title: "george", uniq_one: "three", uniq_two: "four", price: 20}
                 ],
                 Post,
                 :create,
                 return_stream?: true,
                 return_records?: true
               )
               |> Enum.sort_by(fn {:ok, result} -> result.title end)

      assert [
               {:ok, %{title: "fred", uniq_one: "one", uniq_two: "two", price: 1000}},
               {:ok, %{title: "george", uniq_one: "three", uniq_two: "four", price: 20_000}}
             ] =
               Ash.bulk_create!(
                 [
                   %{title: "something", uniq_one: "one", uniq_two: "two", price: 1000},
                   %{title: "else", uniq_one: "three", uniq_two: "four", price: 20_000}
                 ],
                 Post,
                 :create,
                 upsert?: true,
                 upsert_identity: :uniq_one_and_two,
                 upsert_fields: [:price],
                 return_stream?: true,
                 return_errors?: true,
                 return_records?: true
               )
               |> Enum.sort_by(fn
                 {:ok, result} ->
                   result.title

                 _ ->
                   nil
               end)
    end

    test "bulk upsert skips with filter" do
      assert [
               {:ok, %{title: "fredfoo", uniq_if_contains_foo: "1foo", price: 10}},
               {:ok, %{title: "georgefoo", uniq_if_contains_foo: "2foo", price: 20}},
               {:ok, %{title: "herbert", uniq_if_contains_foo: "3", price: 30}}
             ] =
               Ash.bulk_create!(
                 [
                   %{title: "fredfoo", uniq_if_contains_foo: "1foo", price: 10},
                   %{title: "georgefoo", uniq_if_contains_foo: "2foo", price: 20},
                   %{title: "herbert", uniq_if_contains_foo: "3", price: 30}
                 ],
                 Post,
                 :create,
                 return_stream?: true,
                 return_records?: true
               )
               |> Enum.sort_by(fn {:ok, result} -> result.title end)

      assert [
               {:ok, %{title: "georgefoo", uniq_if_contains_foo: "2foo", price: 20_000}},
               {:ok, %{title: "herbert", uniq_if_contains_foo: "3", price: 30}}
             ] =
               Ash.bulk_create!(
                 [
                   %{title: "fredfoo", uniq_if_contains_foo: "1foo", price: 10},
                   %{title: "georgefoo", uniq_if_contains_foo: "2foo", price: 20_000},
                   %{title: "herbert", uniq_if_contains_foo: "3", price: 30}
                 ],
                 Post,
                 :upsert_with_filter,
                 return_stream?: true,
                 return_errors?: true,
                 return_records?: true
               )
               |> Enum.sort_by(fn
                 {:ok, result} ->
                   result.title

                 _ ->
                   nil
               end)
    end

    test "bulk upsert skips with upsert_condition" do
      assert [
               {:ok, %{title: "fredfoo", uniq_if_contains_foo: "1foo", price: 10}},
               {:ok, %{title: "georgefoo", uniq_if_contains_foo: "2foo", price: 20}},
               {:ok, %{title: "herbert", uniq_if_contains_foo: "3", price: 30}}
             ] =
               Ash.bulk_create!(
                 [
                   %{title: "fredfoo", uniq_if_contains_foo: "1foo", price: 10},
                   %{title: "georgefoo", uniq_if_contains_foo: "2foo", price: 20},
                   %{title: "herbert", uniq_if_contains_foo: "3", price: 30}
                 ],
                 Post,
                 :create,
                 return_stream?: true,
                 return_records?: true
               )
               |> Enum.sort_by(fn {:ok, result} -> result.title end)

      assert [
               {:ok, %{title: "georgefoo", uniq_if_contains_foo: "2foo", price: 20_000}},
               {:ok, %{title: "herbert", uniq_if_contains_foo: "3", price: 30}}
             ] =
               Ash.bulk_create!(
                 [
                   %{title: "fredfoo", uniq_if_contains_foo: "1foo", price: 10},
                   %{title: "georgefoo", uniq_if_contains_foo: "2foo", price: 20_000},
                   %{title: "herbert", uniq_if_contains_foo: "3", price: 30}
                 ],
                 Post,
                 :upsert_with_no_filter,
                 return_stream?: true,
                 upsert_condition: expr(price != upsert_conflict(:price)),
                 return_errors?: true,
                 return_records?: true
               )
               |> Enum.sort_by(fn
                 {:ok, result} ->
                   result.title

                 _ ->
                   nil
               end)
    end

    test "bulk upsert returns skipped records with return_skipped_upsert?" do
      assert [
               {:ok, %{title: "fredfoo", uniq_if_contains_foo: "1foo", price: 10}},
               {:ok, %{title: "georgefoo", uniq_if_contains_foo: "2foo", price: 20}},
               {:ok, %{title: "herbert", uniq_if_contains_foo: "3", price: 30}}
             ] =
               Ash.bulk_create!(
                 [
                   %{title: "fredfoo", uniq_if_contains_foo: "1foo", price: 10},
                   %{title: "georgefoo", uniq_if_contains_foo: "2foo", price: 20},
                   %{title: "herbert", uniq_if_contains_foo: "3", price: 30}
                 ],
                 Post,
                 :create,
                 return_stream?: true,
                 return_records?: true
               )
               |> Enum.sort_by(fn {:ok, result} -> result.title end)

      results =
        Ash.bulk_create!(
          [
            %{title: "fredfoo", uniq_if_contains_foo: "1foo", price: 10},
            %{title: "georgefoo", uniq_if_contains_foo: "2foo", price: 20_000},
            %{title: "herbert", uniq_if_contains_foo: "3", price: 30}
          ],
          Post,
          :upsert_with_no_filter,
          return_stream?: true,
          upsert_condition: expr(price != upsert_conflict(:price)),
          return_errors?: true,
          return_records?: true,
          return_skipped_upsert?: true
        )
        |> Enum.sort_by(fn
          {:ok, result} ->
            result.title

          _ ->
            nil
        end)

      assert [
               {:ok, skipped},
               {:ok, updated},
               {:ok, no_conflict}
             ] = results

      assert skipped.title == "fredfoo"
      assert skipped.price == 10
      assert Ash.Resource.get_metadata(skipped, :upsert_skipped) == true

      assert updated.title == "georgefoo"
      assert updated.price == 20_000
      refute Ash.Resource.get_metadata(updated, :upsert_skipped)

      assert no_conflict.title == "herbert"
      assert no_conflict.price == 30
      refute Ash.Resource.get_metadata(no_conflict, :upsert_skipped)
    end

    # confirmed that this doesn't work because it can't. An upsert must map to a potentially successful insert.
    # leaving this test here for posterity
    # test "bulk creates can upsert with id" do
    #   org_id = Ash.UUID.generate()

    #   _new_org =
    #     Organization
    #     |> Ash.Changeset.for_create(:create, %{
    #       id: org_id,
    #       title: "Avengers"
    #     })
    #     |> Ash.create!()

    #   assert [
    #            {:ok,
    #             %{
    #               name: "Bruce Banner",
    #               code: "BB01",
    #               must_be_present: "I am Hulk",
    #               organization_id: org_id
    #             }},
    #            {:ok,
    #             %{
    #               name: "Tony Stark",
    #               code: "TS01",
    #               must_be_present: "I am Iron Man",
    #               organization_id: org_id
    #             }}
    #          ] =
    #            Ash.bulk_create!(
    #              [
    #                %{
    #                  name: "Tony Stark",
    #                  code: "TS01",
    #                  must_be_present: "I am Iron Man",
    #                  organization_id: org_id
    #                },
    #                %{
    #                  name: "Bruce Banner",
    #                  code: "BB01",
    #                  must_be_present: "I am Hulk",
    #                  organization_id: org_id
    #                }
    #              ],
    #              Manager,
    #              :create,
    #              return_stream?: true,
    #              return_records?: true,
    #              return_errors?: true
    #            )
    #            |> Enum.sort_by(fn {:ok, result} -> result.name end)

    #   assert [
    #            {:ok,
    #             %{
    #               name: "Bruce Banner",
    #               code: "BB01",
    #               must_be_present: "I am Hulk",
    #               organization_id: org_id,
    #               role: "bone breaker"
    #             }},
    #            {:ok,
    #             %{
    #               name: "Tony Stark",
    #               code: "TS01",
    #               must_be_present: "I am Iron Man",
    #               organization_id: org_id,
    #               role: "master in chief"
    #             }}
    #          ] =
    #            Ash.bulk_create!(
    #              [
    #                %{
    #                  name: "Tony Stark",
    #                  code: "TS01",
    #                  organization_id: org_id,
    #                  role: "master in chief"
    #                },
    #                %{
    #                  name: "Brice Brenner",
    #                  code: "BB01",
    #                  organization_id: org_id,
    #                  role: "bone breaker"
    #                }
    #              ],
    #              Manager,
    #              :create,
    #              upsert?: true,
    #              upsert_identity: :uniq_code,
    #              upsert_fields: [:role],
    #              return_stream?: true,
    #              return_records?: true,
    #              return_errors?: true
    #            )
    #            |> Enum.sort_by(fn
    #              {:ok, result} ->
    #                result.name

    #              _ ->
    #                nil
    #            end)
    # end

    test "bulk creates can create relationships" do
      Ash.bulk_create!(
        [%{title: "fred", rating: %{score: 5}}, %{title: "george", rating: %{score: 0}}],
        Post,
        :create
      )

      assert [
               %{title: "fred", ratings: [%{score: 5}]},
               %{title: "george", ratings: [%{score: 0}]}
             ] =
               Post
               |> Ash.Query.sort(:title)
               |> Ash.Query.load(:ratings)
               |> Ash.read!()
    end

    test "bulk creates with integer primary key return records" do
      %Ash.BulkResult{records: records} =
        Ash.bulk_create!(
          [%{title: "first"}, %{title: "second"}, %{title: "third"}],
          IntegerPost,
          :create,
          return_records?: true
        )

      assert length(records) == 3
    end
  end

  describe "validation errors" do
    test "skips invalid by default" do
      assert %{records: [_], errors: [_]} =
               Ash.bulk_create([%{title: "fred"}, %{title: "not allowed"}], Post, :create,
                 return_records?: true,
                 return_errors?: true
               )
    end

    test "returns errors in the stream" do
      assert [{:ok, _}, {:error, _}] =
               Ash.bulk_create!([%{title: "fred"}, %{title: "not allowed"}], Post, :create,
                 return_records?: true,
                 return_stream?: true,
                 return_errors?: true
               )
               |> Enum.to_list()
    end

    test "handle allow_nil? false correctly" do
      assert %{
               errors: [
                 %Ash.Error.Invalid{errors: [%Ash.Error.Changes.Required{field: :full_name}]}
               ]
             } =
               Ash.bulk_create([%{full_name: ""}], Record, :create,
                 return_records?: true,
                 return_errors?: true
               )
    end
  end

  describe "database errors" do
    test "database errors affect the entire batch" do
      # assert %{records: [_], errors: [_]} =
      Ash.bulk_create(
        [%{title: "fred"}, %{title: "george", organization_id: Ash.UUID.generate()}],
        Post,
        :create,
        return_records?: true
      )

      assert [] =
               Post
               |> Ash.Query.sort(:title)
               |> Ash.read!()
    end

    test "database errors don't affect other batches" do
      Ash.bulk_create(
        [%{title: "george", organization_id: Ash.UUID.generate()}, %{title: "fred"}],
        Post,
        :create,
        return_records?: true,
        batch_size: 1
      )

      assert [%{title: "fred"}] =
               Post
               |> Ash.Query.sort(:title)
               |> Ash.read!()
    end
  end

  describe "nested bulk operations" do
    test "supports bulk_create in after_action callbacks" do
      result =
        Ash.bulk_create!(
          [%{title: "trigger_nested"}],
          Post,
          :create_with_nested_bulk_create,
          return_records?: true,
          authorize?: false
        )

      # Assert the bulk result contains the expected data
      assert %Ash.BulkResult{records: [original_post]} = result
      assert original_post.title == "trigger_nested"

      # Verify all posts that should exist after the nested operation
      all_posts =
        Post
        |> Ash.Query.sort(:title)
        |> Ash.read!()

      # Should have: 1 original + 2 nested = 3 total posts
      assert length(all_posts) == 3

      # Verify we have the expected posts with correct titles
      post_titles = Enum.map(all_posts, & &1.title) |> Enum.sort()
      assert post_titles == ["nested_post_1", "nested_post_2", "trigger_nested"]

      # Verify the specific nested posts were created by the after_action callback
      nested_posts =
        Post
        |> Ash.Query.filter(expr(title in ["nested_post_1", "nested_post_2"]))
        |> Ash.Query.sort(:title)
        |> Ash.read!()

      assert length(nested_posts) == 2
      assert [%{title: "nested_post_1"}, %{title: "nested_post_2"}] = nested_posts

      # Verify that each nested post has proper metadata
      Enum.each(nested_posts, fn post ->
        assert is_binary(post.id)
        assert post.title in ["nested_post_1", "nested_post_2"]
      end)
    end

    test "supports bulk_update in after_action callbacks" do
      # Create the original post - the after_action callback will create and update additional posts
      result =
        Ash.bulk_create!(
          [%{title: "trigger_nested_update"}],
          Post,
          :create_with_nested_bulk_update,
          return_records?: true,
          authorize?: false
        )

      # Assert the bulk result contains the expected data
      assert %Ash.BulkResult{records: [original_post]} = result
      assert original_post.title == "trigger_nested_update"

      # Verify all posts that should exist after the nested operations
      # The after_action callback should have created 2 posts and updated them
      all_posts =
        Post
        |> Ash.Query.sort(:title)
        |> Ash.read!()

      # Should have: 1 original + 2 created and updated = 3 total posts
      assert length(all_posts) == 3

      # Verify the original post still exists
      original_posts =
        Post
        |> Ash.Query.filter(expr(title == "trigger_nested_update"))
        |> Ash.read!()

      assert length(original_posts) == 1
      assert hd(original_posts).title == "trigger_nested_update"

      # Verify the nested posts were created and then updated by the after_action callback
      updated_posts =
        Post
        |> Ash.Query.filter(expr(title == "updated_via_nested_bulk"))
        |> Ash.read!()

      assert length(updated_posts) == 2

      # Verify that the updated posts have proper metadata and were actually updated
      Enum.each(updated_posts, fn post ->
        assert is_binary(post.id)
        assert post.title == "updated_via_nested_bulk"
      end)

      # Verify no posts remain with the intermediate titles (they should have been updated)
      intermediate_posts =
        Post
        |> Ash.Query.filter(expr(title in ["post_to_update_1", "post_to_update_2"]))
        |> Ash.read!()

      assert intermediate_posts == [],
             "Posts should have been updated, not left with intermediate titles"
    end

    test "nested bulk operations handle metadata indexing correctly" do
      # Create multiple posts in the parent bulk operation to test indexing
      # Each parent post's after_action callback will create nested posts
      result =
        Ash.bulk_create!(
          [
            %{title: "trigger_nested"},
            %{title: "trigger_nested_2"}
          ],
          Post,
          :create_with_nested_bulk_create,
          return_records?: true,
          authorize?: false
        )

      # Assert both parent posts were created
      assert %Ash.BulkResult{records: parent_posts} = result
      assert length(parent_posts) == 2

      parent_titles = Enum.map(parent_posts, & &1.title) |> Enum.sort()
      assert parent_titles == ["trigger_nested", "trigger_nested_2"]

      # Verify total posts: 2 parent + (2 nested per parent from after_action) = 6 total
      all_posts = Post |> Ash.Query.sort(:title) |> Ash.read!()
      assert length(all_posts) == 6

      # Count posts by type
      nested_posts =
        Post
        |> Ash.Query.filter(expr(title in ["nested_post_1", "nested_post_2"]))
        |> Ash.read!()

      # Should have 4 nested posts (2 for each parent operation via after_action callbacks)
      assert length(nested_posts) == 4

      # Verify each nested post has proper structure
      Enum.each(nested_posts, fn post ->
        assert is_binary(post.id)
        assert post.title in ["nested_post_1", "nested_post_2"]
      end)
    end
  end
end
