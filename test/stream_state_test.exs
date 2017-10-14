defmodule StreamStateTest do
  use ExUnit.Case
  doctest StreamState
  use ExUnitProperties
  use StreamState

  test "call macro with a proper call" do
    mfa = call StreamState.run_commands([1, 2, 3])
    assert mfa == {:call, {StreamState, :run_commands, [[1, 2, 3]]}}
  end

  property "reversing a list doesn't change its length" do
    check all list <- list_of(integer()) do
      assert length(list) == length(:lists.reverse(list))
    end
  end

  test "use bind to produce pairs of lists and a member" do
    pairs = StreamData.integer()
    |> StreamData.list_of()
    |> StreamData.nonempty()
    |> StreamData.bind(fn list ->
      list
      |> StreamData.member_of()
      |> StreamData.bind(fn elem -> StreamData.constant({list, elem}) end)
    end)
    |> Enum.take(10)
    assert pairs |> Enum.all?(fn {l, m} -> Enum.member?(l, m) end)
  end

end
