defmodule AshPostgres.Test.ComplexCalculations.Registry do
  @moduledoc false
  use Ash.Registry

  entries do
    entry(AshPostgres.Test.ComplexCalculations.Certification)
    entry(AshPostgres.Test.ComplexCalculations.Skill)
    entry(AshPostgres.Test.ComplexCalculations.Documentation)
    entry(AshPostgres.Test.ComplexCalculations.Channel)
    entry(AshPostgres.Test.ComplexCalculations.ChannelMember)
  end
end
