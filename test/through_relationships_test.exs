# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.ThroughRelationshipsTest do
  use AshPostgres.RepoCase, async: false

  require Ash.Query

  setup do
    school_1 = create_school("School One")
    school_2 = create_school("School Two")

    classroom_1 = create_classroom("Math 101", school_1.id)
    classroom_2 = create_classroom("Science 101", school_1.id)
    classroom_3 = create_classroom("History 101", school_2.id)

    teacher_1 = create_teacher("Mr. Smith")
    teacher_2 = create_teacher("Ms. Johnson")
    teacher_3 = create_teacher("Dr. Williams")
    teacher_4 = create_teacher("Prof. Adams")

    student_1 = create_student("Alice", classroom_1.id)
    student_2 = create_student("Bob", classroom_2.id)

    %{
      school_1: school_1,
      school_2: school_2,
      classroom_1: classroom_1,
      classroom_2: classroom_2,
      classroom_3: classroom_3,
      teacher_1: teacher_1,
      teacher_2: teacher_2,
      teacher_3: teacher_3,
      teacher_4: teacher_4,
      student_1: student_1,
      student_2: student_2
    }
  end

  describe "has_many through relationships" do
    test "loads teachers through classrooms -> classroom_teachers -> teacher", setup do
      %{school_1: school_1, classroom_1: classroom_1, classroom_2: classroom_2} = setup
      %{teacher_1: teacher_1, teacher_2: teacher_2, teacher_3: teacher_3} = setup

      assign_teacher(classroom_1.id, teacher_1.id)
      assign_teacher(classroom_1.id, teacher_2.id)
      assign_teacher(classroom_2.id, teacher_2.id)
      assign_teacher(classroom_2.id, teacher_3.id)

      school_with_teachers = Ash.load!(school_1, :teachers)

      teacher_names =
        school_with_teachers.teachers
        |> Enum.map(& &1.name)
        |> Enum.sort()

      assert teacher_names == ["Dr. Williams", "Mr. Smith", "Ms. Johnson"]
    end

    test "has_many through with no results", setup do
      %{school_2: school_2} = setup

      school_with_teachers = Ash.load!(school_2, :teachers)
      assert school_with_teachers.teachers == []
    end

    test "has_many through with empty intermediate results", setup do
      %{school_1: school_1} = setup

      school_with_teachers = Ash.load!(school_1, :teachers)
      assert school_with_teachers.teachers == []
    end

    test "3-hop path: school -> classrooms -> classroom_teachers -> teacher", setup do
      %{school_1: school_1, classroom_1: classroom_1} = setup
      %{teacher_1: teacher_1} = setup

      assign_teacher(classroom_1.id, teacher_1.id)

      school_with_teachers = Ash.load!(school_1, :teachers)

      assert length(school_with_teachers.teachers) == 1
      assert hd(school_with_teachers.teachers).name == "Mr. Smith"
    end
  end

  describe "many_to_many through atom list" do
    test "retired_teachers loads only teachers with retired_at set", setup do
      %{classroom_1: classroom_1} = setup
      %{teacher_1: teacher_1, teacher_2: teacher_2} = setup

      assign_teacher(classroom_1.id, teacher_1.id)
      assign_teacher(classroom_1.id, teacher_2.id)

      classroom_with_retired = Ash.load!(classroom_1, :retired_teachers)

      assert length(classroom_with_retired.retired_teachers) == 1
      assert hd(classroom_with_retired.retired_teachers).name == teacher_1.name
    end

    test "retired_teachers returns empty when no teachers are retired", setup do
      %{classroom_1: classroom_1} = setup
      %{teacher_1: teacher_1} = setup

      assign_teacher(classroom_1.id, teacher_1.id)

      classroom_with_retired = Ash.load!(classroom_1, :retired_teachers)
      assert classroom_with_retired.retired_teachers == []
    end

    test "teacher many_to_many classrooms via atom list through", setup do
      %{classroom_1: classroom_1, classroom_2: classroom_2} = setup
      %{teacher_1: teacher_1} = setup

      assign_teacher(classroom_1.id, teacher_1.id)
      assign_teacher(classroom_2.id, teacher_1.id)

      teacher_with_classrooms = Ash.load!(teacher_1, :classrooms)

      classroom_names =
        teacher_with_classrooms.classrooms
        |> Enum.map(& &1.name)
        |> Enum.sort()

      assert classroom_names == ["Math 101", "Science 101"]
    end
  end

  describe "has_one through relationships" do
    test "active_teacher loads the non-retired teacher", setup do
      %{classroom_1: classroom_1} = setup
      %{teacher_1: teacher_1, teacher_2: teacher_2} = setup

      assign_teacher(classroom_1.id, teacher_1.id)
      assign_teacher(classroom_1.id, teacher_2.id)

      classroom_loaded = Ash.load!(classroom_1, :active_teacher)
      assert classroom_loaded.active_teacher.name == teacher_2.name
    end

    test "student teacher through classroom active_teacher", setup do
      %{classroom_1: classroom_1} = setup
      %{teacher_1: teacher_1, teacher_2: teacher_2} = setup
      %{student_1: student_1} = setup

      assign_teacher(classroom_1.id, teacher_1.id)
      assign_teacher(classroom_1.id, teacher_2.id)

      student_with_teacher = Ash.load!(student_1, :teacher)
      assert student_with_teacher.teacher.name == teacher_2.name
    end
  end

  describe "aggregates on through relationships" do
    test "school teacher_count counts all teachers through path", setup do
      %{school_1: school_1, classroom_1: classroom_1, classroom_2: classroom_2} = setup
      %{teacher_1: teacher_1, teacher_2: teacher_2} = setup

      assign_teacher(classroom_1.id, teacher_1.id)
      assign_teacher(classroom_2.id, teacher_1.id)
      assign_teacher(classroom_2.id, teacher_2.id)

      school_with_agg =
        AshPostgres.Test.Through.School
        |> Ash.Query.filter(id == ^school_1.id)
        |> Ash.Query.load([:classroom_count, :teacher_count, :teacher_count_via_path])
        |> Ash.read_one!()

      assert school_with_agg.classroom_count == 2
      assert school_with_agg.teacher_count == 3
      assert school_with_agg.teacher_count_via_path == 3
    end

    test "school retired_teacher_count counts only retired", setup do
      %{school_1: school_1, classroom_1: classroom_1} = setup
      %{teacher_1: teacher_1, teacher_2: teacher_2, teacher_3: teacher_3} = setup

      assign_teacher(classroom_1.id, teacher_1.id)
      assign_teacher(classroom_1.id, teacher_2.id)

      school_with_agg =
        AshPostgres.Test.Through.School
        |> Ash.Query.filter(id == ^school_1.id)
        |> Ash.Query.load(:retired_teacher_count)
        |> Ash.Query.load(:active_teacher_count)
        |> Ash.read_one!()

      assert school_with_agg.retired_teacher_count == 1
      assert school_with_agg.active_teacher_count == 1

      assign_teacher(classroom_1.id, teacher_3.id)

      school_with_agg =
        AshPostgres.Test.Through.School
        |> Ash.Query.filter(id == ^school_1.id)
        |> Ash.Query.load(:retired_teacher_count)
        |> Ash.Query.load(:active_teacher_count)
        |> Ash.read_one!()

      assert school_with_agg.retired_teacher_count == 2
      assert school_with_agg.active_teacher_count == 1
    end

    test "multiple schools with aggregates", setup do
      %{school_1: school_1, school_2: school_2} = setup
      %{classroom_1: classroom_1, classroom_2: classroom_2, classroom_3: classroom_3} = setup

      %{teacher_1: teacher_1, teacher_2: teacher_2, teacher_3: teacher_3, teacher_4: teacher_4} =
        setup

      assign_teacher(classroom_1.id, teacher_1.id)
      assign_teacher(classroom_1.id, teacher_2.id)
      assign_teacher(classroom_2.id, teacher_3.id)
      assign_teacher(classroom_3.id, teacher_2.id)
      assign_teacher(classroom_3.id, teacher_3.id)
      assign_teacher(classroom_3.id, teacher_4.id)

      [school_one, school_two] =
        AshPostgres.Test.Through.School
        |> Ash.Query.load([:classroom_count, :teacher_count, :teacher_count_via_path])
        |> Ash.Query.filter(id in [^school_1.id, ^school_2.id])
        |> Ash.Query.sort(:name)
        |> Ash.read!()

      assert school_one.name == "School One"
      assert school_one.classroom_count == 2
      assert school_one.teacher_count == 3
      assert school_one.teacher_count_via_path == 3

      assert school_two.name == "School Two"
      assert school_two.classroom_count == 1
      assert school_two.teacher_count == 3
      assert school_two.teacher_count_via_path == 3
    end

    test "students know their active teacher", setup do
      %{school_1: school_1, classroom_1: classroom_1, classroom_2: classroom_2} = setup

      %{teacher_1: teacher_1, teacher_2: teacher_2, teacher_3: teacher_3, teacher_4: teacher_4} =
        setup

      %{student_1: student_1, student_2: student_2} = setup

      assign_teacher(classroom_1.id, teacher_1.id)
      assign_teacher(classroom_2.id, teacher_2.id)

      student_1 = Ash.load!(student_1, [:teacher, :retired_teacher_count])
      student_2 = Ash.load!(student_2, [:teacher, :retired_teacher_count])

      assign_teacher(classroom_1.id, teacher_3.id)
      assign_teacher(classroom_2.id, teacher_4.id)

      student_1 = Ash.load!(student_1, [:teacher, :retired_teacher_count])
      student_2 = Ash.load!(student_2, [:teacher, :retired_teacher_count])

      assert student_1.teacher.name == teacher_3.name
      assert student_1.retired_teacher_count == 1
      assert student_2.teacher.name == teacher_4.name
      assert student_2.retired_teacher_count == 1

      school_1 = Ash.load!(school_1, [:retired_teacher_count, :active_teacher_count])

      assert school_1.retired_teacher_count == 2
      assert school_1.active_teacher_count == 2
    end
  end

  defp create_school(name) do
    AshPostgres.Test.Through.School
    |> Ash.Changeset.for_create(:create, %{name: name})
    |> Ash.create!()
  end

  defp create_classroom(name, school_id) do
    AshPostgres.Test.Through.Classroom
    |> Ash.Changeset.for_create(:create, %{name: name, school_id: school_id})
    |> Ash.create!()
  end

  defp create_teacher(name) do
    AshPostgres.Test.Through.Teacher
    |> Ash.Changeset.for_create(:create, %{name: name})
    |> Ash.create!()
  end

  defp create_student(name, classroom_id) do
    AshPostgres.Test.Through.Student
    |> Ash.Changeset.for_create(:create, %{name: name, classroom_id: classroom_id})
    |> Ash.create!()
  end

  defp assign_teacher(classroom_id, teacher_id, opts \\ []) do
    attrs =
      %{classroom_id: classroom_id, teacher_id: teacher_id}
      |> Map.merge(Map.new(opts))

    AshPostgres.Test.Through.ClassroomTeacher
    |> Ash.Changeset.for_create(:assign, attrs)
    |> Ash.create!()
  end
end
