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
end
