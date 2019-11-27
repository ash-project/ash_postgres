defmodule AshEcto.MixProject do
  use Mix.Project

  def project do
    [
      app: :ash_ecto,
      version: "0.1.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto_sql, "~> 3.0"},
      {:postgrex, ">= 0.0.0"},
      {:ash, path: "../ash"}
    ]
  end
end
