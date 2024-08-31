defmodule AshPostgres.UpdateTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Post
  require Ash.Query

  test "can update with nested maps" do
    Post
    |> Ash.Changeset.for_create(:create, %{stuff: %{foo: %{bar: :baz}}})
    |> Ash.create!()
    |> then(fn record ->
      Ash.Query.filter(Post, id == ^record.id)
    end)
    |> Ash.bulk_update(
      :update,
      %{
        stuff: %{
          summary: %{
            chat_history: [
              %{"content" => "Default system prompt", "role" => "system"},
              %{
                "content" =>
                  "Here's a collection of tweets from the Twitter list 'Web 3 Mid':\nTweet by KhanAbbas201 (2024-08-26 19:40:13.000000Z):\n@Rahatcodes told me I look good wearing the Eth shirt. https://t.co/xBugAt2tDi\nTweet by Rahatcodes (2024-08-26 19:42:55.000000Z):\n@KhanAbbas201 I dont recall saying this\nTweet by KhanAbbas201 (2024-08-26 19:44:08.000000Z):\n@Rahatcodes Damn what happened to your memory bruv?\nTweet by angelinarusse (2024-08-26 19:56:05.000000Z):\n@dabit3 Real degens call it Twitter\nTweet by angelinarusse (2024-08-26 20:13:58.000000Z):\n@hamseth They tried the same in Afghanistan and it didn’t go well for them.\nTweet by KhanAbbas201 (2024-08-26 20:39:53.000000Z):\nTweet by Osh_mahajan (2024-08-26 21:34:08.000000Z):\n@FedericoNoemie 🐾🐾🦘\nTweet by developer_dao (2024-08-26 21:39:59.000000Z):\n@ZwigoZwitscher @ArweaveEco @k4yls Wildly high praise, ty ty. @k4yls is 🔥 with a 🐶\nTweet by developer_dao (2024-08-26 21:41:17.000000Z):\nRT @ZwigoZwitscher : I've been into @ArweaveEco for years – as an interested outsider – and still learned new things in that course 👇. Thanks…\nTweet by angelin...eet by developer_dao (2024-08-26 22:18:09.000000Z):\nRT @jeremykauffman: BREAKING: France has arrested Gonzalve Bich, the CEO of Bic\nTweet by PatrickAlphaC (2024-08-26 22:26:16.000000Z):\n@oxfav @ar_io_network\n",
                "role" => "user"
              },
              %{"content" => "test", "role" => "user"},
              %{
                "content" =>
                  "It looks like you're testing the feature. How can I assist you further?",
                "role" => "assistant"
              }
            ]
          }
        }
      }
    )
  end
end
