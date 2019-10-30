defmodule AshEcto do
  defmacro __using__(opts) do
    quote bind_quoted: [data_layer: opts[:data_layer]] do
      @data_layer data_layer
      @mix_ins AshEcto
    end
  end

  def before_compile_hook(_env) do
    quote do
      require AshEcto.Schema

      AshEcto.Schema.define_schema(@name)
    end
  end
end
