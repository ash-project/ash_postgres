defmodule AshPostgres.BulkCreateTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Post, Record}

  describe "bulk creates" do
    test "bulk creates insert each input" do
      Ash.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create)

      assert [%{title: "fred"}, %{title: "george"}] =
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
  end

  describe "validation errors" do
    test "skips invalid by default" do
      assert %{records: [_], errors: [_]} =
               Ash.bulk_create!([%{title: "fred"}, %{title: "not allowed"}], Post, :create,
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
end
