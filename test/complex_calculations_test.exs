defmodule AshPostgres.Test.ComplexCalculationsTest do
  use AshPostgres.RepoCase, async: false

  require Ash.Query

  test "complex calculation" do
    certification =
      AshPostgres.Test.ComplexCalculations.Certification
      |> Ash.Changeset.new()
      |> AshPostgres.Test.ComplexCalculations.Api.create!()

    skill =
      AshPostgres.Test.ComplexCalculations.Skill
      |> Ash.Changeset.new()
      |> Ash.Changeset.manage_relationship(:certification, certification, type: :append)
      |> AshPostgres.Test.ComplexCalculations.Api.create!()

    _documentation =
      AshPostgres.Test.ComplexCalculations.Documentation
      |> Ash.Changeset.new(%{status: :demonstrated})
      |> Ash.Changeset.manage_relationship(:skill, skill, type: :append)
      |> AshPostgres.Test.ComplexCalculations.Api.create!()

    skill =
      skill
      |> AshPostgres.Test.ComplexCalculations.Api.load!([:latest_documentation_status])

    assert skill.latest_documentation_status == :demonstrated

    certification =
      certification
      |> AshPostgres.Test.ComplexCalculations.Api.load!([
        :count_of_skills
      ])

    assert certification.count_of_skills == 1

    certification =
      certification
      |> AshPostgres.Test.ComplexCalculations.Api.load!([
        :count_of_approved_skills
      ])

    assert certification.count_of_approved_skills == 0

    certification =
      certification
      |> AshPostgres.Test.ComplexCalculations.Api.load!([
        :count_of_documented_skills
      ])

    assert certification.count_of_documented_skills == 1

    certification =
      certification
      |> AshPostgres.Test.ComplexCalculations.Api.load!([
        :count_of_documented_skills,
        :all_documentation_approved,
        :some_documentation_created
      ])

    assert certification.some_documentation_created
  end

  test "channel: first_member and second member" do
    channel =
      AshPostgres.Test.ComplexCalculations.Channel
      |> Ash.Changeset.new()
      |> AshPostgres.Test.ComplexCalculations.Api.create!()

    user_1 =
      AshPostgres.Test.User
      |> Ash.Changeset.for_create(:create, %{name: "User 1"})
      |> AshPostgres.Test.Api.create!()

    user_2 =
      AshPostgres.Test.User
      |> Ash.Changeset.for_create(:create, %{name: "User 2"})
      |> AshPostgres.Test.Api.create!()

    channel_member_1 =
      AshPostgres.Test.ComplexCalculations.ChannelMember
      |> Ash.Changeset.new()
      |> Ash.Changeset.manage_relationship(:channel, channel, type: :append)
      |> Ash.Changeset.manage_relationship(:user, user_1, type: :append)
      |> AshPostgres.Test.ComplexCalculations.Api.create!()

    channel_member_2 =
      AshPostgres.Test.ComplexCalculations.ChannelMember
      |> Ash.Changeset.new()
      |> Ash.Changeset.manage_relationship(:channel, channel, type: :append)
      |> Ash.Changeset.manage_relationship(:user, user_2, type: :append)
      |> AshPostgres.Test.ComplexCalculations.Api.create!()

    channel =
      channel
      |> AshPostgres.Test.ComplexCalculations.Api.load!([
        :first_member,
        :second_member
      ])

    assert channel.first_member.id == channel_member_1.id
    assert channel.second_member.id == channel_member_2.id

    channel =
      channel
      |> AshPostgres.Test.ComplexCalculations.Api.load!(:name, actor: user_1)

    assert channel.name == user_1.name

    channel =
      channel
      |> AshPostgres.Test.ComplexCalculations.Api.load!(:name, actor: user_2)

    assert channel.name == user_2.name
  end

  test "complex calculation while using actor on related resource passes reference" do
    dm_channel =
      AshPostgres.Test.ComplexCalculations.DMChannel
      |> Ash.Changeset.new()
      |> AshPostgres.Test.ComplexCalculations.Api.create!()

    user_1 =
      AshPostgres.Test.User
      |> Ash.Changeset.for_create(:create, %{name: "User 1"})
      |> AshPostgres.Test.Api.create!()

    user_2 =
      AshPostgres.Test.User
      |> Ash.Changeset.for_create(:create, %{name: "User 2"})
      |> AshPostgres.Test.Api.create!()

    channel_member_1 =
      AshPostgres.Test.ComplexCalculations.ChannelMember
      |> Ash.Changeset.for_create(:create, %{channel_id: dm_channel.id, user_id: user_1.id})
      |> AshPostgres.Test.ComplexCalculations.Api.create!()

    channel_member_2 =
      AshPostgres.Test.ComplexCalculations.ChannelMember
      |> Ash.Changeset.for_create(:create, %{channel_id: dm_channel.id, user_id: user_2.id})
      |> AshPostgres.Test.ComplexCalculations.Api.create!()

    dm_channel =
      dm_channel
      |> AshPostgres.Test.ComplexCalculations.Api.load!([
        :first_member,
        :second_member
      ])

    assert dm_channel.first_member.id == channel_member_1.id
    assert dm_channel.second_member.id == channel_member_2.id

    dm_channel =
      dm_channel
      |> AshPostgres.Test.ComplexCalculations.Api.load!(:name, actor: user_1)

    assert dm_channel.name == user_1.name

    dm_channel =
      dm_channel
      |> AshPostgres.Test.ComplexCalculations.Api.load!(:name, actor: user_2)

    assert dm_channel.name == user_2.name

    channels =
      AshPostgres.Test.ComplexCalculations.Channel
      |> Ash.Query.for_read(:read)
      |> AshPostgres.Test.ComplexCalculations.Api.read!()

    channels =
      channels
      |> AshPostgres.Test.ComplexCalculations.Api.load!([dm_channel: :name],
        actor: user_1
      )

    [channel | _] = channels

    assert channel.dm_channel.name == user_1.name

    channel =
      channel
      |> AshPostgres.Test.ComplexCalculations.Api.load!([:dm_name, :foo], actor: user_2)

    assert channel.dm_name == user_2.name
  end

  test "calculations with parent filters can be filtered on themselves" do
    AshPostgres.Test.ComplexCalculations.DMChannel
    |> Ash.Changeset.new()
    |> AshPostgres.Test.ComplexCalculations.Api.create!()

    assert [%{foo: "foobar"}] =
             AshPostgres.Test.ComplexCalculations.Channel
             |> Ash.Query.filter(foo == "foobar")
             |> AshPostgres.Test.ComplexCalculations.Api.read!(load: :foo)
  end

  test "calculations with aggregates can be referenced from aggregates" do
    author =
      AshPostgres.Test.Author
      |> Ash.Changeset.new(%{first_name: "is", last_name: "match"})
      |> AshPostgres.Test.Api.create!()

    AshPostgres.Test.Post
    |> Ash.Changeset.new(%{title: "match"})
    |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
    |> AshPostgres.Test.Api.create!()

    assert [%{author_count_of_posts: 1}] =
             AshPostgres.Test.Post
             |> Ash.Query.load(:author_count_of_posts)
             |> AshPostgres.Test.Api.read!()

    assert [%{author_count_of_posts: 1}] =
             AshPostgres.Test.Post
             |> AshPostgres.Test.Api.read!()
             |> AshPostgres.Test.Api.load!(:author_count_of_posts)

    assert [_] =
             AshPostgres.Test.Post
             |> Ash.Query.filter(author_count_of_posts == 1)
             |> AshPostgres.Test.Api.read!()
  end
end
