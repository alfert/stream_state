defmodule StreamState.TreeTest do
  use ExUnit.Case
  alias StreamState.Test.Tree
  use ExUnitProperties
  use StreamState

  ################################
  ### Properties of the tree


  property "Tree.delete/2 has a bug" do
    # Generate a tree, which has member x more often
    faulty_tree = integer()
    |> bind(fn x ->
      {constant(x),
       my_tree(one_of([constant(x), integer()]))}
    end)

    assert_raise(ExUnit.AssertionError, fn ->
      check all {x, t} <- faulty_tree,
        Tree.member(t, x) do
          # this one should fail and throw an AssertionError
          assert Tree.member(t, x)
          assert not Tree.member(Tree.delete(t, x), x)
      end
    end)
  end

  property "delete2 has no bug" do
    check all {x, t} <- {integer(), my_tree(integer())} do
      assert not Tree.member(Tree.delete2(t, x), x)
    end
  end


  # Example of a PBT strategy: finding two distinct computations that should
  # result in the same value.
  property "sum" do
    check all t <- my_tree(integer()) do
      l = Tree.pre_order(t)
      assert Enum.all?(l, &is_number/1)
      assert Tree.pre_order(t) |> Enum.sum == Tree.tree_sum(t)
    end
  end

  def aggregate(stream, matcher) when not is_list(matcher),
    do: aggregate(stream, [matcher])
  def aggregate(stream, matcher) do
    # ensure that the stream's element is pair of the old value and
    # a (initially empty) list of assigned aggregrate values
    stream
    |> Stream.map(fn
      e = {_v, l} when is_list(l) -> e
      e -> {e, []}
    end)
    # now match the values
    |> Stream.map(fn {e, stats} ->
      # for each element apply the matchers
      ms = Enum.reduce(matcher, [], fn
        f, matches when is_function(f, 1) -> [f.(e) | matches]
        ^e, matches  -> [e | matches]
        _, matches -> matches
      end)
      {e, [ms | stats]}
    end)
  end

  @spec aggregate_reducer(Enum.t) :: {%{term => number}, number}
  def aggregate_reducer(stream) do
    stream
    |> Enum.reduce({%{}, 0}, fn {_, [keys]}, {map, counter} ->
      new_map = keys
      |> Enum.reduce(map, fn k, m -> Map.update(m, k, 1, &(&1 + 1)) end)
      {new_map, counter + 1}
    end)
  end

  def aggregate_printer({map, total_counter}) do
    IO.puts("\nStats:")
    for {tag, c} <- Map.to_list(map) do
      IO.puts "#{inspect tag}: #{(c*100.0)/total_counter}%"
    end
  end

  test "Generate a proper tree" do
    trees = my_tree(integer())
    |> Stream.take(200)
    # |> Enum.to_list()
    # |> aggregate([:leaf, {:node, 0, :leaf, :leaf}, {:node, 4, :leaf, :leaf}])
    # |> aggregate(&Tree.size/1)
    |> aggregate(&Tree.height/1)
    |> Enum.to_list()
    |> aggregate_reducer()
    |> aggregate_printer()

    assert trees |> Enum.all?(fn x -> x == :ok end)
  end

  test "Nested list tree" do
    require Logger
    trees = tree_list_gen(integer())
    |> Stream.take(100)
    # |> Enum.to_list()
    |> aggregate(&tree_list_height/1)
    |> Enum.to_list()
    |> aggregate_reducer()
    |> aggregate_printer()
    # Logger.debug "trees: #{inspect trees}"
  end

  defp tree_list_height(:leaf), do: 0
  defp tree_list_height([:node, _, left, right]), do:
  1 + max(tree_list_height(left), tree_list_height(right))

  ##################################
  ## Custom Generators for trees
  def my_tree(g), do: tree_gen(g) # sd_tree(g) #

  defp tree_gen(g), do: sized(fn size -> tree_gen(size, g) end)
  defp tree_gen(0, _g), do: :leaf
  defp tree_gen(size, g), do:
    frequency([
      {1, tree_gen(0, g)},
      {9, ({:node, g,
        resize(tree_gen(g), div(size, 2)),
        resize(tree_gen(g), div(size, 2))})}
    ])

  defp tree_list_gen(g), do: sized(fn size -> tree_list_gen(size, g) end)
  defp tree_list_gen(0, _g), do: constant(:leaf)
  defp tree_list_gen(size, g), do:
    frequency([
      {1, tree_gen(0, g)},
      {9, fixed_list([:node, g,
        resize(tree_list_gen(g), div(size, 2)),
        resize(tree_list_gen(g), div(size, 2))])}
    ])

  defp empty_tree?(:leaf), do: true
  defp empty_tree?({:node, _, _, _}), do: false

  def sd_tree(g) do
    tree(:leaf, fn leaf_data ->
      {:node, g, leaf_data, leaf_data}
    end)
  end

  test "recursive values" do
    for_many(tree_gen(integer()), # |> StreamData.filter(fn t -> not empty_tree?(t) end),
      fn {:node, v, left, right} ->
          assert is_integer(v)
          assert left == :leaf or match?({:node, _, _, _}, left)
          assert right == :leaf or match?({:node, _, _, _}, right)
        t -> assert empty_tree?(t)
      end
      )
  end

  defp for_many(data, count \\ 200, fun) do
    data
    |> Stream.take(count)
    |> Enum.each(fun)
  end

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
