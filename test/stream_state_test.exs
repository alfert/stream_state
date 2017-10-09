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

end
