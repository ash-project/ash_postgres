defmodule AshPostgres.Test.ComplexCalculations.Domain do
  @moduledoc false
  use Ash.Domain

  resources do
    resource(AshPostgres.Test.ComplexCalculations.Certification)
    resource(AshPostgres.Test.ComplexCalculations.Skill)
    resource(AshPostgres.Test.ComplexCalculations.Documentation)
    resource(AshPostgres.Test.ComplexCalculations.Channel)
    resource(AshPostgres.Test.ComplexCalculations.DMChannel)
    resource(AshPostgres.Test.ComplexCalculations.ChannelMember)
  end

  authorization do
    authorize(:when_requested)
  end
end
