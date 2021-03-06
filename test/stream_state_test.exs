defmodule StreamStateTest do
  use ExUnit.Case
  doctest StreamState
  import StreamData
  use ExUnitProperties
  use StreamState

  alias StreamState.Test.Counter

  test "call macro with a proper call" do
    #mfa = call StreamState.run_commands([1, 2, 3])
    #assert {:call, {StreamState, :run_commands, %StreamData{}}} = mfa
  end

  test "call macros with an aliased call" do
    mfa = call StreamState.Test.Counter.get()
    assert {:call, {StreamState.Test.Counter, :get, %StreamData{}}} = mfa
  end

  property "reversing a list doesn't change its length" do
    check all list <- list_of(integer()) do
      assert length(list) == length(:lists.reverse(list))
    end
  end

  test "use bind to produce pairs of lists and a member" do
    pairs = StreamData.integer()
    |> list_of()
    |> nonempty()
    |> bind(fn list ->
      list
      |> member_of()
      |> bind(fn elem -> constant({list, elem}) end)
    end)
    |> Enum.take(10)
    assert pairs |> Enum.all?(fn {l, m} -> Enum.member?(l, m) end)
  end

  test "generate nested values" do
    pair_gen = tuple({integer(), fixed_list([integer(), :what])})
    pair = pair_gen |> Enum.at(0)
    {n, l} = pair
    assert is_number(n)
    assert is_list(l)
    assert [_, :what] = l
  end

  test "generated nested fixed lists" do
    l = fixed_list([integer() | [integer()]])
    my_list = l |> Enum.at(0)
    assert length(my_list) == 2
    empty = fixed_list([]) |> Enum.at(0)
    assert [] == empty
  end

  test "generate a list of intertwined values" do
    odd = fn -> 1 + positive_integer()*2 end
    even = fn -> positive_integer() * 2 end
  end

  property "a pair_list is like a normal list" do
    check all l <- list_of(integer()) do
      pl = StreamState.pair_list(l)
      assert Enum.empty?(l) == StreamState.empty?(pl)
      assert length(l) == StreamState.len(pl)
      if not Enum.empty?(l) do
        assert hd(l) == StreamState.head(pl)
      end
      assert l == StreamState.to_list(pl)
    end
  end

  # test fail_eventually
  property "all integers are positive" do
    fail_eventually do
      check all n <- integer() do
        assert n >= 0
      end
    end
  end

  # test fail_eventually
  property "all lists have a head" do
    fail_eventually do
      check all l <- list_of(positive_integer()) do
        assert length(l) >= 0
        n = hd(l)
        assert n >= 0
      end
    end
  end

  # test fail_eventually will fail, because nothing fails inside
  property "all non negative integers are positive" do
    assert_raise(StreamState.TooLongRunWithoutFailureError, fn ->
      fail_eventually do
        check all n <- positive_integer() do
          assert n >= 0
        end
      end
    end)
  end


  # test fail_eventually, because nothing fails inside
  property "all nonempty lists have a head" do
    assert_raise(StreamState.TooLongRunWithoutFailureError, fn ->
      fail_eventually do
        check all l <- nonempty(list_of(positive_integer())) do
          assert length(l) >= 0
          n = hd(l)
          assert n >= 0
        end
      end
    end)
  end

  test "Pretty print a command sequence" do
    require Logger
    cmds = [call: {StreamState, :fun, [1, 2, 3]},
            call: {StreamState.Test.Counter, :start, []}]
    output = StreamState.pretty_print_commands(cmds)
    Logger.debug "output= #{output}"
    assert output =~ ~r/call/
    assert output =~ "call Elixir.StreamState.Test.Counter.start()"

  end
end
