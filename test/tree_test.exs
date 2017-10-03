defmodule StreamState.TreeTest do
  use ExUnit.Case
  alias StreamState.Test.Tree
  use ExUnitProperties

  ################################
  ### Properties of the tree

  # # delete is faulty, therefore we expect it fail now and then
  # property "delete" do
  #   # the faulty tree has a default-value, which occurs more often
  #   # than other values. We also delete this default-value, hence
  #   # the buggy delete method should fail.
  #   faulty_tree = let x <- integer() do
  #     {x, tree(default(x, integer()))}
  #   end
  #
  #   fails(forall {x, t} <- faulty_tree do
  #     not Tree.member(Tree.delete(t, x), x)
  #   end)
  #
  # end
  #
  # # delete2 is not faulty
  # property "delete2", [:verbose, {:max_size, 20}]  do
  #   forall {x, t} <- {integer(), tree(integer())} do
  #       tsize = t |> Tree.pre_order |> Enum.count
  #       (not Tree.member(Tree.delete2(t, x), x))
  #       |> collect(tsize)
  #       |> measure("Tree Size", tsize)
  #   end
  # end
  #
  # Example of a PBT strategy: finding two distinct computations that should
  # result in the same value.

  property "sum" do
    check all t <- my_tree(integer()) do
      l = Tree.pre_order(t)
      assert Enum.all?(l, &is_number/1)
      assert Tree.pre_order(t) |> Enum.sum == Tree.tree_sum(t)
    end
  end

  def aggregate(stream, matcher) do
    stream
    |> Stream.map(fn
      e = {_v, l} when is_list(l) -> e
      e -> {e, []}
    end)
    |> Stream.map(fn {e, stats} ->
      ms = Enum.reduce(matcher, [], fn
        (^e, matches)  -> [e | matches]
        (_, matches) -> matches
      end)
      {e, [ms | stats]}
    end)
  end

  @spec aggregate_reducer(Enum.t) :: {%{term => number}, number}
  def aggregate_reducer(stream) do
    stream
    |> Enum.reduce({%{}, 0}, fn {_, [keys]}, {map, counter} ->
      new_map = keys |> Enum.reduce(map, fn k, m -> Map.update(m, k, 1, &(&1 + 1))end)
      {new_map, counter + 1}
    end)
  end

  def aggregate_printer({map, total_counter}) do
    for {tag, c} <- Map.to_list(map) do
      IO.puts "#{inspect tag}: #{(c*100.0)/total_counter}%"
    end
  end

  test "Generate a proper tree" do
    trees = my_tree(integer())
    |> Stream.take(10)
    |> aggregate([:leaf, {:node, 0, :leaf, :leaf}, {:node, 4, :leaf, :leaf}])
    # |> Enum.to_list()
    |> aggregate_reducer()
    |> aggregate_printer()

    assert trees == []
  end

  ##################################
  ## Custom Generators for trees
  def my_tree(g), do: tree1a(g)

  @doc "Attempts at writing a generator for trees."
  # def tree1(g) do
  #   # wie kann man denn aus %{left: xx, right: yy} ein {:node, xx, left, right} machen???
  #   leaf = fn _g -> :leaf end
  #   basic_node = fn gen -> {:node, gen, nil, nil} end
  #   node = one_of([leaf.(g), basic_node.(g)])
  #
  #   nodes = fn gen -> StreamData.map({gen, gen, gen}, fn {l, r, n} -> {:node, n, l, r} end) end
  #   StreamData.tree(node, nodes.(g))
  # end

  def tree1a(g) do
    leaf = one_of([:leaf, {:node, g, :leaf, :leaf}])
    nodes = fn gen ->
      StreamData.map({gen, gen},
        fn {l, r} -> {:node, g, l, r}
      end)
    end
    StreamData.tree(leaf, nodes)
  end

  # @doc "Erlang is eager: we need to enforce lazy evaluation to avoid infinite recursion"
  # def tree2(g), do:
  #   union([
  #     :leaf,
  #     lazy {:node, g, tree2(g), tree2(g)}
  #   ])
  #
  # @doc """
  # Generation might not terminate: we need to introduce a bound on the number
  # of recursive calls (and thus the size of the produced term), by handling the
  # `size` parameter manually.
  #
  # The base case is delegated to the 0-size clause.
  # All non-recursive cases are replaced by fallbacks to that clause.
  # """
  # def tree3(g), do: sized(s, tree3(s, g))
  # def tree3(0, _), do: :leaf
  # def tree3(s, g), do:
  #   union([
  #     tree3(0, g),
  #     lazy {:node, g, tree3(s, g), tree3(s, g)}
  #   ])
  #
  # @doc """
  # 50% of the time, the tree is empty: we should set the weights in the union
  # to ensure a satisfactory average size of produced instances.
  # """
  # def tree4(g), do: sized(s, tree4(s, g))
  # def tree4(0, _), do: :leaf
  # def tree4(s, g), do:
  #   frequency [
  #     {1, tree4(0, g)},
  #     {9, lazy {:node, g, tree4(s, g), tree4(s, g)}}
  #   ]
  #
  # @doc """
  # The trees grow too fast: we should distribute the size evenly to all subtrees
  # """
  # def tree5(g), do: sized(s, tree5(s, g))
  # def tree5(0, _), do: :leaf
  # def tree5(s, g), do:
  #   frequency [
  #     {1, tree5(0, g)},
  #     {9, lazy {:node, g, tree5(div(s, 2), g), tree5(div(s, 2), g)}}
  #   ]
  #
  # @doc """
  # Finally, we set up a more efficient shrinking strategy: pick each of the
  # subtrees in place of the tree that fails the property.
  # """
  # def tree6(g), do: sized(s, tree6(s, g))
  # def tree6(0, _), do: :leaf
  # def tree6(s, g), do:
  #   frequency [
  #     {1, tree6(0, g)},
  #     {9, let_shrink([
  #         l <- tree6(div(s, 2), g),
  #         r <- tree6(div(s, 2), g)
  #       ]) do
  #         {:node, g, l, r}
  #       end
  #       }
  #   ]
  #

end
