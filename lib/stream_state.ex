defmodule StreamState do
  @moduledoc """
  Documentation for StreamState.
  """

  defmacro __using__(_) do
    quote do
      import StreamState
    end
  end

  defmacro call(fun_call = {{:., _, _mod_list}, _, _args} ) do
    call = Macro.decompose_call(fun_call)
    mfa = Macro.escape {module(call), function(call), args(call)}
    quote do {:call, unquote(mfa)} end
  end

  def module({_fun, _args}), do: Kernel
  def module({{:__aliases__, [alias: false], mods}, _, _}), do: Module.concat(mods)
  def module({{:__aliases__, [alias: mods], _aliased_mod}, _, _}), do: Module.concat(mods)
  def module({{:__aliases__, _, mods}, _, _}), do: Module.concat(mods)

  def function({fun, _args}), do: fun
  def function({{:__aliases__, _, _}, fun, _args}), do: fun

  def args({_fun, args}), do: args
  def args({{:__aliases__, _, _}, _fun, args}), do: args

end
