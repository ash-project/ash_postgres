defmodule AshPostgres.Test.ComplexCalculationsTest do
  use AshPostgres.RepoCase, async: false

  require Ash.Query

  test "complex calculation" do
    certification =
      AshPostgres.Test.ComplexCalculations.Certification
      |> Ash.Changeset.new()
      |> Ash.create!()

    skill =
      AshPostgres.Test.ComplexCalculations.Skill
      |> Ash.Changeset.new()
      |> Ash.Changeset.manage_relationship(:certification, certification, type: :append)
      |> Ash.create!()

    _documentation =
      AshPostgres.Test.ComplexCalculations.Documentation
      |> Ash.Changeset.for_create(:create, %{status: :demonstrated})
      |> Ash.Changeset.manage_relationship(:skill, skill, type: :append)
      |> Ash.create!()

    skill =
      skill
      |> Ash.load!([:latest_documentation_status])

    assert skill.latest_documentation_status == :demonstrated

    certification =
      certification
      |> Ash.load!([
        :count_of_skills
      ])

    assert certification.count_of_skills == 1

    certification =
      certification
      |> Ash.load!([
        :count_of_approved_skills
      ])

    assert certification.count_of_approved_skills == 0

    certification =
      certification
      |> Ash.load!([
        :count_of_documented_skills
      ])

    assert certification.count_of_documented_skills == 1

    certification =
      certification
      |> Ash.load!([
        :count_of_documented_skills,
        :all_documentation_approved,
        :some_documentation_created
      ])

    assert certification.some_documentation_created
  end

  test "complex aggregates" do
    certification =
      AshPostgres.Test.ComplexCalculations.Certification
      |> Ash.Changeset.new()
      |> Ash.create!()

    skill =
      AshPostgres.Test.ComplexCalculations.Skill
      |> Ash.Changeset.new()
      |> Ash.Changeset.manage_relationship(:certification, certification, type: :append)
      |> Ash.create!()

    AshPostgres.Test.ComplexCalculations.Documentation
    |> Ash.Changeset.for_create(:create, %{status: :demonstrated})
    |> Ash.Changeset.manage_relationship(:skill, skill, type: :append)
    |> Ash.create!()

    certification =
      certification
      |> Ash.load!([:count_of_skills_ever_demonstrated])

    assert certification.count_of_skills_ever_demonstrated == 1
  end

  test "calculation of inline aggregate" do
    skill =
      AshPostgres.Test.ComplexCalculations.Skill
      |> Ash.Changeset.new()
      |> Ash.create!()

    AshPostgres.Test.ComplexCalculations.Documentation
    |> Ash.Changeset.for_create(:create, %{status: :demonstrated})
    |> Ash.Changeset.manage_relationship(:skill, skill, type: :append)
    |> Ash.create!()

    skill = Ash.load!(skill, [:documentations_custom])

    assert %{one: "One", documentations: [%{"two" => "Two", "status" => "demonstrated"}]} =
             skill.documentations_custom
  end

  test "channel: first_member and second member" do
    channel =
      AshPostgres.Test.ComplexCalculations.Channel
      |> Ash.Changeset.new()
      |> Ash.create!()

    user_1 =
      AshPostgres.Test.User
      |> Ash.Changeset.for_create(:create, %{name: "User 1"})
      |> Ash.create!()

    user_2 =
      AshPostgres.Test.User
      |> Ash.Changeset.for_create(:create, %{name: "User 2"})
      |> Ash.create!()

    channel_member_1 =
      AshPostgres.Test.ComplexCalculations.ChannelMember
      |> Ash.Changeset.new()
      |> Ash.Changeset.manage_relationship(:channel, channel, type: :append)
      |> Ash.Changeset.manage_relationship(:user, user_1, type: :append)
      |> Ash.create!()

    channel_member_2 =
      AshPostgres.Test.ComplexCalculations.ChannelMember
      |> Ash.Changeset.new()
      |> Ash.Changeset.manage_relationship(:channel, channel, type: :append)
      |> Ash.Changeset.manage_relationship(:user, user_2, type: :append)
      |> Ash.create!()

    channel =
      channel
      |> Ash.load!([
        :first_member,
        :second_member
      ])

    assert channel.first_member.id == channel_member_1.id
    assert channel.second_member.id == channel_member_2.id

    channel =
      channel
      |> Ash.load!(:name, actor: user_1)

    assert channel.name == user_1.name

    channel =
      channel
      |> Ash.load!(:name, actor: user_2)

    assert channel.name == user_2.name
  end

  test "complex calculation while using actor on related resource passes reference" do
    dm_channel =
      AshPostgres.Test.ComplexCalculations.DMChannel
      |> Ash.Changeset.new()
      |> Ash.create!()

    user_1 =
      AshPostgres.Test.User
      |> Ash.Changeset.for_create(:create, %{name: "User 1"})
      |> Ash.create!()

    user_2 =
      AshPostgres.Test.User
      |> Ash.Changeset.for_create(:create, %{name: "User 2"})
      |> Ash.create!()

    channel_member_1 =
      AshPostgres.Test.ComplexCalculations.ChannelMember
      |> Ash.Changeset.for_create(:create, %{channel_id: dm_channel.id, user_id: user_1.id})
      |> Ash.create!()

    channel_member_2 =
      AshPostgres.Test.ComplexCalculations.ChannelMember
      |> Ash.Changeset.for_create(:create, %{channel_id: dm_channel.id, user_id: user_2.id})
      |> Ash.create!()

    dm_channel =
      dm_channel
      |> Ash.load!([
        :first_member,
        :second_member
      ])

    assert dm_channel.first_member.id == channel_member_1.id
    assert dm_channel.second_member.id == channel_member_2.id

    dm_channel =
      dm_channel
      |> Ash.load!(:name, actor: user_1)

    assert dm_channel.name == user_1.name

    dm_channel =
      dm_channel
      |> Ash.load!(:name, actor: user_2)

    assert dm_channel.name == user_2.name

    channels =
      AshPostgres.Test.ComplexCalculations.Channel
      |> Ash.Query.for_read(:read)
      |> Ash.read!()

    channels =
      channels
      |> Ash.load!([dm_channel: :name],
        actor: user_1
      )

    [channel | _] = channels

    assert channel.dm_channel.name == user_1.name

    channel =
      channel
      |> Ash.load!([:dm_name, :foo], actor: user_2)

    assert channel.dm_name == user_2.name
  end

  test "calculations through `from_many?` relationships properly join" do
    dm_channel =
      AshPostgres.Test.ComplexCalculations.DMChannel
      |> Ash.Changeset.new()
      |> Ash.create!()

    user_1 =
      AshPostgres.Test.User
      |> Ash.Changeset.for_create(:create, %{name: "User 1"})
      |> Ash.create!()

    AshPostgres.Test.ComplexCalculations.ChannelMember
    |> Ash.Changeset.for_create(:create, %{channel_id: dm_channel.id, user_id: user_1.id})
    |> Ash.create!()

    assert channel_member =
             AshPostgres.Test.ComplexCalculations.ChannelMember
             |> Ash.Query.load(:first_member_recently_created)
             |> Ash.read_one!()

    assert channel_member.first_member_recently_created
  end

  test "calculations with parent filters can be filtered on themselves" do
    AshPostgres.Test.ComplexCalculations.DMChannel
    |> Ash.Changeset.new()
    |> Ash.create!()

    assert [%{foo: "foobar"}] =
             AshPostgres.Test.ComplexCalculations.Channel
             |> Ash.Query.filter(foo == "foobar")
             |> Ash.read!(load: :foo)
  end

  test "calculations with aggregates can be referenced from aggregates" do
    author =
      AshPostgres.Test.Author
      |> Ash.Changeset.for_create(:create, %{first_name: "is", last_name: "match"})
      |> Ash.create!()

    AshPostgres.Test.Post
    |> Ash.Changeset.for_create(:create, %{title: "match"})
    |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
    |> Ash.create!()

    assert [%{author_count_of_posts: 1}] =
             AshPostgres.Test.Post
             |> Ash.Query.load(:author_count_of_posts)
             |> Ash.read!()

    assert [%{author_count_of_posts: 1}] =
             AshPostgres.Test.Post
             |> Ash.read!()
             |> Ash.load!(:author_count_of_posts)

    assert [_] =
             AshPostgres.Test.Post
             |> Ash.Query.filter(author_count_of_posts == 1)
             |> Ash.read!()
  end

  test "calculations can reference aggregates from optimizable first aggregates" do
    author =
      AshPostgres.Test.Author
      |> Ash.Changeset.for_create(:create, %{first_name: "is", last_name: "match"})
      |> Ash.create!()

    AshPostgres.Test.Post
    |> Ash.Changeset.for_create(:create, %{title: "match"})
    |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
    |> Ash.create!()

    assert [%{author_count_of_posts_agg: 1}] =
             AshPostgres.Test.Post
             |> Ash.Query.load(:author_count_of_posts_agg)
             |> Ash.read!()

    assert [%{author_count_of_posts_agg: 1}] =
             AshPostgres.Test.Post
             |> Ash.read!()
             |> Ash.load!(:author_count_of_posts_agg)

    assert [_] =
             AshPostgres.Test.Post
             |> Ash.Query.filter(author_count_of_posts_agg == 1)
             |> Ash.read!()
  end

  test "calculations can reference aggregates from non optimizable aggregates" do
    author =
      AshPostgres.Test.Author
      |> Ash.Changeset.for_create(:create, %{first_name: "is", last_name: "match"})
      |> Ash.create!()

    AshPostgres.Test.Post
    |> Ash.Changeset.for_create(:create, %{title: "match"})
    |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
    |> Ash.create!()

    assert [%{sum_of_author_count_of_posts: 1}] =
             AshPostgres.Test.Post
             |> Ash.Query.load(:sum_of_author_count_of_posts)
             |> Ash.read!()

    assert [%{sum_of_author_count_of_posts: 1}] =
             AshPostgres.Test.Post
             |> Ash.read!()
             |> Ash.load!(:sum_of_author_count_of_posts)

    assert [_] =
             AshPostgres.Test.Post
             |> Ash.Query.filter(sum_of_author_count_of_posts == 1)
             |> Ash.read!()
  end

  test "filters with nested related list aggregate references don't raise errors" do
    AshPostgres.Test.Note
    |> Ash.Query.for_read(:failing_many_reference)
    |> Ash.read!(page: [count: true])
  end

  test "lazy datetime with timezone is respected in calculations" do
    documentation_before =
      AshPostgres.Test.ComplexCalculations.Documentation
      |> Ash.Changeset.for_create(:create, %{
        status: :demonstrated,
        # 2 hours before Seoul time in UTC
        inserted_at: ~U[2024-05-01 10:00:00Z]
      })
      |> Ash.create!()

    documentation_after =
      AshPostgres.Test.ComplexCalculations.Documentation
      |> Ash.Changeset.for_create(:create, %{
        status: :demonstrated,
        # 2 hours after Seoul time in UTC
        inserted_at: ~U[2024-05-01 14:00:00Z]
      })
      |> Ash.create!()

    [doc_before, doc_after] =
      [documentation_before, documentation_after]
      |> Ash.load!([:is_active_with_timezone])

    assert doc_before.is_active_with_timezone == false
    assert doc_after.is_active_with_timezone == true
  end

  test "gnarly parent bug with some weird ltree setup" do
    _folder_a =
      Ash.Seed.seed!(
        AshPostgres.Test.Support.ComplexCalculations.Folder,
        %{some_integer_setting: 1, level: "a"}
      )

    _folder_b =
      Ash.Seed.seed!(
        AshPostgres.Test.Support.ComplexCalculations.Folder,
        %{some_integer_setting: nil, level: "a.b"}
      )

    folder_c =
      Ash.Seed.seed!(
        AshPostgres.Test.Support.ComplexCalculations.Folder,
        %{some_integer_setting: nil, level: "a.b.c"}
      )

    folder_c_item =
      Ash.Seed.seed!(
        AshPostgres.Test.Support.ComplexCalculations.FolderItem,
        %{name: "Item in C", level: 1, folder_id: folder_c.id}
      )

    # reproduction: this raises Unknown Error
    # * ** (Postgrex.Error) ERROR 42846 (cannot_coerce) cannot cast type bigint to ltree
    assert Ash.calculate!(folder_c_item, :folder_setting) == 1
  end
end
