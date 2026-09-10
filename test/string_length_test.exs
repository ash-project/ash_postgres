defmodule AshPostgres.StringLengthTest do
  use AshPostgres.RepoCase, async: false

  alias Ash.Query.Function.StringLength
  alias AshPostgres.Test.Post

  require Ash.Query
  import Ash.Expr

  # Decomposed, so the stored value is 11 codepoints and its NFC form is 7.
  @decomposed :unicode.characters_to_nfd_binary("ünïcödé")

  test "string_length counts codepoints on the stored value" do
    Post |> Ash.Changeset.for_create(:create, %{title: @decomposed}) |> Ash.create!()

    expected = StringLength.string_length(@decomposed, :codepoints)

    assert %{length: ^expected} =
             Post
             |> Ash.Query.calculate(:length, :integer, expr(string_length(title, :codepoints)))
             |> Ash.read_one!()
             |> Map.get(:calculations)
  end
end
