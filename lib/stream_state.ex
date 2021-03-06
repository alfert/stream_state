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

  defmodule TooLongRunWithoutFailureError do
    defexception [:message]
  end

  @doc """
  The `fail_eventually` macro is used for negative testing and states that
  the property will fail eventually.

  For negative testing, we want to show that the system under test behaves properly
  when tested with illegal data. If we want to prove that the data will fail
  in every case, then it is sufficient to negate the assertions. But if only
  some of the data does not satify the assertions, then `fail_eventually` will
  ensure that at least once in each run of the property the assertions are not satisfied.

  `fail_eventually` detects all errors of `ExUnitProperties` and all ExUnit
  assertion errors.

  ## Bad usage of `fail_eventually`
  The macro can be used to specify sloppy properties, which are allowed to fail
  somehow. This does not help to improve the quality assessment and should be
  avoided. Another bad use case to have properties that should show that
  bad designed implemention fails to hold the property. Here it is better to
  use an `assert_raise` to make explicetly clear, that the property will raise
  an (assertion) exception and everything is fine this is called. You can
  see an example for this approach in the `tree_test.exs` example.

  ## Examples

  The first examples shows that some integers are negative.

      property "all integers are positive" do
        fail_eventually do
          check all n <- integer() do
            assert n >= 0
          end
        end
      end

  The second example shows that some lists have no heads. In this case,
  the assignment `n = hd(l)` raises an exception and `l` is empty: the
  `ArgumentError` exception is caught during executing the property check, resulting
  in an `ExUnitProperties.Error`. This exception is caught by `fail_eventually`
  and lets the entire property succeed.

      property "not all lists have a head" do
        fail_eventually do
          check all l <- list_of(positive_integer()) do
            n = hd(l)
            assert n > 0
          end
        end
      end

  The third example shows a failing property because no values are generated
  that will not satisfy the assertion: Positive integers are always greater
  or equal to 0.

      property "all positive integers are positive" do
        fail_eventually do
          check all n <- positive_integer() do
            assert n >= 0
          end
        end
      end
      #=>     ** (StreamState.TooLongRunWithoutFailureError) all tests succeeded, but should eventually fail
      #=> code: fail_eventually do
      #=> stacktrace:
      #=>   test/stream_state_test.exs:95: (test)



  """

  defmacro fail_eventually(block) do
    quote do
      try do
        unquote(block)
        raise TooLongRunWithoutFailureError, message: "all tests succeeded, but should eventually fail"
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

  @type failure :: :precondition_failed | :postcondition_failed | :caught_exception | :caught_error

  @spec run_commands(list({any, call}), atom) :: {true | failure, list}
  def run_commands(command_list, mod) do
    {result_list, result} = command_list
    |> Enum.map_reduce(true, & run_single_command(&1, mod, &2))
    executed_commands = result_list |> Enum.filter(fn x -> x != :not_executed end)
    {result, executed_commands}
  end

  @spec run_single_command({any, call}, atom, :ok) :: {any, any}
  def run_single_command({state, call = {:call, {m, f, a}}}, mod, true) do
    if not mod.precondition(state, call) do
      {{state, call}, :precondition_failed}
    else
      try do
        result = apply(m, f, a)
        new_acc = case mod.postcondition(state, call, result) do
          false -> :postcondition_failed
          true -> true
        end
        {{state, call, result}, new_acc}
      rescue
        exc -> {{state, call}, {:caught_exception, exc}}
      catch
        error, reason -> {{state, call}, {:caught_error, error, reason}}
      end
    end
  end
  def run_single_command({_state, _call}, _mod, failure) do
    {:not_executed, failure}
  end

  @doc """
  Creates an Inspect.Algebra document for a symbolic call.
  """
  @spec pretty_print_command({:call, mfa}) :: Inspect.Algebra.t
  def pretty_print_command({:call, {m, f, args}}) do
    import Inspect.Algebra
    the_args = surround_many("(", args, ")", %Inspect.Opts{limit: :infinity, pretty: true},
        fn arg, _opts -> to_string(arg) end)
    the_call = concat("#{m}.#{f}", the_args)
    glue("call", the_call)
  end

  @spec pretty_print_commands(list(call)) :: String.t
  def pretty_print_commands(cmds) when is_list(cmds) do
    import Inspect.Algebra
    width = IEx.width()
    surround_many("[", cmds, "]", %Inspect.Opts{limit: :infinity, pretty: true},
      fn cmd, _opts -> cmd |> pretty_print_command |> group end)
    |> format(width)
    |> IO.iodata_to_binary
  end

  def pretty_print_hist_element({state, call, result}) do
    import Inspect.Algebra
    state_s = "#{inspect state}:"
    result_s = "#{inspect result} = "
    fold_doc([state_s, result_s, pretty_print_command(call)], fn(doc, acc) ->
      glue(doc, acc)
    end)
  end
  def pretty_print_hist_element(something) do
    "#{inspect something}"
  end

  def pretty_print_history(hist) when is_list(hist) do
    import Inspect.Algebra
    width = IEx.width()
    surround_many("[", hist, "]", %Inspect.Opts{limit: :infinity, pretty: true},
      fn cmd, _opts -> cmd |> pretty_print_hist_element |> group end)
    |> format(width)
    |> IO.iodata_to_binary
  end
  #################################################################
  ##
  # List functions for a cons list out of tuples since stream_date
  # cannot handle lists as generic combinators of generators.
  # They have property based test to ensure functionalty, but
  # no docs, since they are not part of the regular API.
  ##
  #################################################################
  @doc false
  def cons(a,b), do: {a, b}
  @doc false
  def append(head, tail), do: cons(head, tail)
  @doc false
  def head(_pair_list={head, _tail}), do: head
  @doc false
  def tail(_pair_list={_head, tail}), do: tail
  @doc false
  def empty?({}), do: true
  def empty?({_a, _b}), do: false
  @doc false
  def len({}), do: 0
  def len({_head, tail}), do: 1 + len(tail)
  @doc false
  def pair_list(l) do
    Enum.reverse(l)
    |> Enum.reduce({}, fn element, new_list -> cons(element, new_list) end)
  end
  @doc false
  def to_list({}), do: []
  def to_list({head, tail}), do: [head | to_list tail]

  @doc false
  def flatten_nested_list([]), do: []
  def flatten_nested_list([h | t]), do: [h | flatten_nested_list(t)]

end
