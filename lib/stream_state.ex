defmodule StreamState do
  @moduledoc """
  Documentation for StreamState.
  """

  alias StreamData
  require Logger

  defmacro __using__(_) do
    quote do
      import StreamState
    end
  end

  @type call_t :: StreamData.t({:call, mfa})
  @type call_t_gen :: {:call, {atom, atom, StreamData.t(list())}}

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

  @doc """
  A generator for commands. Requires the test module as parameter.
  In this module the callback `commands(state)` is required.
  """
  @spec command_gen(atom) :: StreamData.t(call_t)
  def command_gen(mod) do
    StreamData.sized(fn size -> command_gen(mod, size) end)
  end
  def command_gen(mod, size) do
    initial = mod.initial_state()
    commands = mod.commands()
    l = command_gen(size, initial, commands, mod) #  |> Enum.at(0)
    Logger.flush()
    Logger.debug "Generated command list (to be put into fixed_list): #{inspect l}"
    [l] |> StreamData.fixed_list()
  end

# TODO:
# Implement the generator from PropEr exactly with StreamData
# LET => bind
# SUCHTHAT => filter / bind_filter
# command_gen: generator for a list. How to do that? Perhaps we need
#   help from tree/list?

  @spec command_gen(integer, :atom, list({integer, call_t}), atom) :: StreamData.t(call_t)
  def command_gen(0, _, _, _), do: StreamData.fixed_list([])
  def command_gen(size, state, command_list, mod) when size > 0
        and is_list(command_list) and is_atom(state) do
    Logger.debug "command_gen: command_list is #{inspect command_list}"
    command_list
    # TODO: filter does not work, since call has is generator not an mfa!
    # |> Enum.filter(fn {_, call} -> mod.precondition(state, call) end)
    |> StreamData.frequency()
    |> StreamData.bind(fn cmd ->
      Logger.debug "command_gen: (old) state is #{inspect state}"
      Logger.debug "command_gen: new command is #{inspect cmd}"
      Logger.debug "command_gen: command is #{inspect cmd}"
      new_state = mod.transition(state, cmd)
      Logger.debug "new state is: #{inspect new_state}"
      StreamData.bind(StreamData.tuple({state, StreamData.constant(cmd)}),
        fn sc when is_tuple(sc) ->
          Logger.debug "bind: sc is #{inspect sc}"
          tail = command_gen(size - 1, new_state, command_list, mod)
          Logger.debug "bind: tail is #{inspect tail}"
          l = StreamData.fixed_list([StreamData.tuple(sc) | tail])
          Logger.debug "bind: cmd seq is #{inspect l}"
          l
        end)
    end)
  end

  def flatten_nested_list([]), do: []
  def flatten_nested_list([h | t]), do: [h | flatten_nested_list(t)]

end
