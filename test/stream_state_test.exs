defmodule StreamStateTest do
  use ExUnit.Case
  doctest StreamState

  use ExUnitProperties

  test "greets the world" do
    assert StreamState.hello() == :world
  end

  property "reversing a list doesn't change its length" do
    check all list <- list_of(integer()) do
      assert length(list) == length(:lists.reverse(list))
    end
  end

end
