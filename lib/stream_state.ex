defmodule StreamState do
  @moduledoc """
  Documentation for StreamState.
  """

  alias StreamData
  require Logger
  import ExUnit.Assertions

  defmacro __using__(_) do
    quote do
      import StreamState
    end
  end

  @type call :: {:call, mfa}
  @type call_t :: StreamData.t(call)
  @type call_t_gen :: {:call, {atom, atom, StreamData.t(list())}}

  @doc """
  Creates a `{:call, mfa}` like tuple from a regular function call, where
  the arguments are translated into a `StreamData.fixed_list/1`, since the
  arguments to the call are meant to be resolved via `StreamData`.

  **IMPORTANT**: The `call` macro cannot deal with aliased remote functions,
  you have always(!) to use the full module name.
  """
  defmacro call(fun_call = {{:., _, _mod_list}, _, my_args} ) do
    call = Macro.expand(fun_call, __ENV__)
    # IO.puts "call = #{inspect call}"
    mfa = Macro.decompose_call(call)
    # IO.puts "mfa = #{inspect mfa}"
    m = module(mfa)
    f = function(mfa)

    quote do {:call, {unquote(m), unquote(f), StreamData.fixed_list(unquote(my_args))}} end
  end

  def module({_fun, _args}), do: Kernel
  def module({{:__aliases__, [alias: false], mods}, _, _}), do: Module.concat(mods)
  def module({{:__aliases__, [alias: mods], _aliased_mod}, _, _}), do: mods
  def module({{:__aliases__, _meta, mods}, _, _}), do: Module.concat(mods)

  def function({fun, _args}), do: fun
  def function({{:__aliases__, _, _}, fun, _args}), do: fun

  def args({_fun, args}) when is_list(args), do: args
  def args({{:__aliases__, _, _}, _fun, args}) when is_list(args), do: args

  defmacro fail_eventually(block) do
    quote do
      try do
        unquote(block)
        raise ExUnitProperties.Error, "all test succeeded, but should eventually fail"
      rescue
        ExUnit.AssertionError -> {:ok, %{}}
        ExUnitProperties.Error -> {:ok, %{}}
      end
    end
  end

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
    command_gen(size, initial, commands, mod)
    |> StreamData.map(&to_list/1)
  end

  @spec command_gen(integer, :atom, list({integer, call_t}), atom) :: StreamData.t(call_t)
  def command_gen(0, _, _, _), do: StreamData.constant({})
  def command_gen(size, state, command_list, mod) when size > 0
        and is_list(command_list) and is_atom(state) do
    # Logger.debug "command_gen<#{size}>: command_list is #{inspect command_list}"
    command_list
    # TODO: filter does not work, since call has is generator not an mfa!
    # |> Enum.filter(fn {_, call} -> mod.precondition(state, call) end)
    |> StreamData.frequency()
    |> StreamData.bind(fn cmd ->
      # Logger.debug "command_gen<#{size}>: (old) state is #{inspect state}"
      # Logger.debug "command_gen<#{size}>: new command is #{inspect cmd}"
      # Logger.debug "command_gen<#{size}>: command is #{inspect cmd}"
      new_state = mod.transition(state, cmd)
      # Logger.debug "command_gen<#{size}>: new state is: #{inspect new_state}"
      StreamData.bind(StreamData.tuple({state, StreamData.constant(cmd)}),
        fn sc when is_tuple(sc) ->
          # Logger.debug "command_gen<#{size}>: bind: sc is #{inspect sc}"
          tail = command_gen(size - 1, new_state, command_list, mod)
          # Logger.debug "command_gen<#{size}>: bind: tail is #{inspect tail}"
          l = cons(StreamData.tuple(sc), tail)
          # Logger.debug "command_gen<#{size}>: bind: cmd seq is #{inspect l}"
          l
        end)
    end)
  end

  def run_commands(command_list, mod) do
    command_list |> Enum.map(& run_single_command(&1, mod))
  end

  @spec run_single_command({any, call}, atom) :: any
  def run_single_command({state, call = {:call, mfa}}, mod) do
    assert mod.precondition(state, call)
    {m, f, a} = mfa
    # all exceptions let the command abort, but how to deal with the history?
    result = apply(m, f, a)
    assert mod.postcondition(state, call, result)
    result
  end

  def cons(a,b), do: {a, b}
  def append(head, tail), do: cons(head, tail)
  def head(_pair_list={head, _tail}), do: head
  def tail(_pair_list={_head, tail}), do: tail
  def empty?({}), do: true
  def empty?({_a, _b}), do: false
  def len({}), do: 0
  def len({_head, tail}), do: 1 + len(tail)
  def pair_list(l) do
    Enum.reverse(l)
    |> Enum.reduce({}, fn element, new_list -> cons(element, new_list) end)
  end
  def to_list({}), do: []
  def to_list({head, tail}), do: [head | to_list tail]


  def flatten_nested_list([]), do: []
  def flatten_nested_list([h | t]), do: [h | flatten_nested_list(t)]

end
