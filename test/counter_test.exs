defmodule StreamState.Test.CounterTest do
  @moduledoc """
  A simple state machine for property testing the  `StreamState.Test.Counter`.

  We use only three states: `:init`, `:zero` and `:one`.

  ## TODO:
  * define functions for the three states, their pre- and postconditions
    ==> Do we call from these functions the regular ones, i.e. the System
        under test?
  * define a generator `commands` for symbolic calls -> in `StreamState`
  * define a function `run_commands` in StreamState to run the commands in
    `StreamState`

  """
  alias StreamState.Test.Counter
  use ExUnit.Case
  use StreamState
  use ExUnitProperties

  require Logger

  @typedoc """
  The type for the state of the state machine model.
  """
  @type state_t :: :init | :zero | :one

  @type call_t :: {:call, mfa}


  ##########################
  #
  # Testing the generators
  #
  #########################
  test "the command specifier" do

  end

  test "Generate single commands" do
    assert {} == StreamState.command_gen(0, :init, commands(), __MODULE__) |> Enum.at(0)
    cmds = StreamState.command_gen(2, :init, commands(), __MODULE__)
    cmd = cmds |> Enum.at(0) |> StreamState.to_list
    assert [{:init, _}, {_, _}] = cmd
    assert [{:init, {:call, {StreamState.Test.Counter, _, _}}}, _] = cmd
  end

  property "generate a command sequence" do
    check all cmds <- StreamState.command_gen(__MODULE__) do
      # Logger.debug("cmds: #{inspect cmds}")
      assert {:init, _} = Enum.at(cmds, 0)
      assert length(cmds) > 0
      # assert length(cmds) < 100
    end
  end

  def when_fail(what_ever) do
    Logger.error "when_fail: #{inspect what_ever}"
  end

  property "run a command sequence" do
    check all cmds <- StreamState.command_gen(__MODULE__) do
      Process.flag(:trap_exit, true)
      {:ok, pid} = Counter.start_link()
      run_commands(cmds, __MODULE__)
      |> when_fail()
      GenServer.stop(pid, :normal)
    end
  end

  ##########################
  ##
  # The pre- and postconditions for executing the model
  #
  ##
  ##########################

  @doc """
  Every call can be made everytime. It is called for generating commands
  and for executing them.
  """
  @spec precondition(state_t, call_t) :: boolean
  def precondition(_state, {:call, _mfa}), do: true

  @doc "The expected outcome. Only called after executing the command"
  @spec postcondition(state_t, call_t, any) :: boolean
  def postcondition(:init, {:call, {_,:inc, _}}, _result), do: true
  def postcondition(:init, {:call, {_,:clear, _}}, _result), do: true
  def postcondition(:init, {:call, {_,:get, _}}, -1), do: true
  def postcondition(:zero, {:call, {_,:clear, _}}, _result), do: true
  def postcondition(:zero, {:call, {_,:inc, _}}, _result), do: true
  def postcondition(:inc, {:call, {_,:inc, _}}, _result), do: true
  def postcondition(:inc, {:call, {_,:clear, _}}, _result), do: true
  def postcondition(:zero, {:call, {_,:get, _}}, 0), do: true
  def postcondition(:one,  {:call, {_,:get, _}}, result), do: result > 0
  def postcondition(:one, {:call, {_,:inc, _}}, result) do
    # generate a consistent failure
    result != 5
    # true
  end
  def postcondition(:one, {:call, {_,:clear, _}}, _result), do: true
  def postcondition(_old_state, {:call, _mfa}, _result) do
    false
  end

  def transition(:init, {:call, {_,:inc, _}}), do: :zero
  def transition(:init, {:call, {_,:clear, _}}), do: :zero
  def transition(:zero, {:call, {_,:clear, _}}), do: :zero
  def transition(:zero, {:call, {_,:inc, _}}), do: :one
  def transition(:one, {:call, {_,:inc, _}}), do: :one
  def transition(:one, {:call, {_,:clear, _}}), do: :zero
  def transition(state, {:call, {_,:get, _}}), do: state

  def initial_state(), do: :init

  def commands(), do: [
    {1, constant(call StreamState.Test.Counter.clear())},
    {3, constant(call StreamState.Test.Counter.inc())},
    {1, constant(call StreamState.Test.Counter.get())}
  ]

  ##########################
  ##
  # The state machine model of the counter
  # It is not integrated into the property testing!
  ##
  ##########################

  @spec init() :: state_t
  def init, do: :init

  @spec clear(state_t) :: state_t
  def clear(_state), do: :zero

  @spec inc(state_t) :: state_t
  def inc(:init), do: :zero
  def inc(_state), do: :one

  @spec get(state_t) :: integer
  def get(:init), do: -1
  def get(:zero), do: 0
  def get(:one), do: 1

end
