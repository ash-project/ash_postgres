defmodule AshPostgres.Test.ComplexCalculationsTest do
  use AshPostgres.RepoCase, async: false

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
end
