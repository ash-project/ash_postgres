alias AshPostgres.MultitenancyTest.{Api, Org, Post}

AshPostgres.TestRepo.start_link()

Code.ensure_loaded(Api)

unless Api.get!(Org, name: "test1") do
  Org
  |> Ash.Changeset.new(name: "test1")
  |> Api.create!()
end

unless Api.get!(Org, name: "test2") do
  Org
  |> Ash.Changeset.new(name: "test2")
  |> Api.create!()
end
