defmodule CredenceTest do
  @moduledoc """
  Sanity tests: idiomatic Elixir solutions that should pass ALL Credence rules.

  When a new rule is added, run these tests to make sure it doesn't produce
  false positives on clean, idiomatic code. If any of these fail, the new
  rule is too broad and needs tightening.
  """
  use ExUnit.Case

  defp assert_clean(code) do
    result = Credence.analyze(code)

    if result.valid do
      assert true
    else
      rules_triggered = Enum.map(result.issues, & &1.rule) |> Enum.uniq()

      flunk(
        "Expected no issues but got #{length(result.issues)}: #{inspect(rules_triggered)}\n" <>
          Enum.map_join(result.issues, "\n", fn i ->
            "  [#{i.severity}] #{i.rule}: #{i.message} (line #{i.meta[:line]})"
          end)
      )
    end
  end

  describe "idiomatic list processing" do
    test "prepend + reverse pattern in reduce" do
      assert_clean("""
      defmodule DoubleList do
        def double(list) do
          list
          |> Enum.reduce([], fn item, acc -> [item * 2 | acc] end)
          |> Enum.reverse()
        end
      end
      """)
    end

    test "Enum.map, filter, and pipe chains" do
      assert_clean("""
      defmodule DataPipeline do
        def process(records) do
          records
          |> Enum.filter(&(&1.active))
          |> Enum.map(& &1.name)
          |> Enum.sort()
          |> Enum.uniq()
        end
      end
      """)
    end

    test "pattern matching in function heads for dispatch" do
      assert_clean("""
      defmodule Factorial do
        def factorial(0), do: 1
        def factorial(num) when is_integer(num) and num > 0, do: do_factorial(num, 1)

        defp do_factorial(1, acc), do: acc
        defp do_factorial(num, acc), do: do_factorial(num - 1, num * acc)
      end
      """)
    end

    test "multi-clause recursive functions with pattern matching" do
      assert_clean("""
      defmodule ListSum do
        def sum([]), do: 0
        def sum([head | tail]), do: head + sum(tail)
      end
      """)
    end

    test "Enum.sort with :desc instead of sort + reverse" do
      assert_clean("""
      defmodule TopK do
        def top_three(nums) do
          Enum.sort(nums, :desc) |> Enum.take(3)
        end
      end
      """)
    end
  end

  describe "idiomatic string processing" do
    test "String.reverse for palindrome check" do
      assert_clean("""
      defmodule Palindrome do
        def palindrome?(text) do
          cleaned =
            text
            |> String.downcase()
            |> String.replace(~r/[^a-z0-9]/, "")

          cleaned == String.reverse(cleaned)
        end
      end
      """)
    end

    test "String.graphemes with Enum.frequencies" do
      assert_clean("""
      defmodule CharFrequency do
        def char_frequency(string) do
          string |> String.graphemes() |> Enum.frequencies()
        end
      end
      """)
    end

    test "binary pattern matching for ASCII parsing" do
      assert_clean("""
      defmodule BracketChecker do
        def balanced?(input) when is_binary(input), do: check(input, [])

        defp check(<<>>, stack), do: stack == []
        defp check(<<"(", rest::binary>>, stack), do: check(rest, [?( | stack])
        defp check(<<")", rest::binary>>, [?( | tail]), do: check(rest, tail)
        defp check(<<")", _rest::binary>>, _stack), do: false
        defp check(<<_::utf8, rest::binary>>, stack), do: check(rest, stack)
      end
      """)
    end

    test "Enum.join without redundant empty separator" do
      assert_clean("""
      defmodule Joiner do
        def join_graphemes(string) do
          string |> String.graphemes() |> Enum.reverse() |> Enum.join()
        end

        def join_with_comma(list) do
          Enum.join(list, ", ")
        end
      end
      """)
    end

    test "iodata accumulation for string building" do
      assert_clean("""
      defmodule StringBuilder do
        def build(graphemes) do
          graphemes
          |> Enum.reduce([], fn char, acc -> [char | acc] end)
          |> Enum.reverse()
          |> IO.iodata_to_binary()
        end
      end
      """)
    end
  end

  describe "idiomatic map usage" do
    test "Enum.frequencies instead of manual counting" do
      assert_clean("""
      defmodule WordCount do
        def count(words) do
          Enum.frequencies(words)
        end
      end
      """)
    end

    test "Map.get + Map.put instead of Map.update + Map.fetch" do
      assert_clean("""
      defmodule Counter do
        def increment(map, key) do
          count = Map.get(map, key, 0) + 1
          Map.put(map, key, count)
        end
      end
      """)
    end

    test "iterating map directly without Map.values or Map.keys" do
      assert_clean("""
      defmodule MapChecker do
        def all_positive?(map) do
          Enum.all?(map, fn {_k, v} -> v > 0 end)
        end

        def key_strings(map) do
          Enum.map(map, fn {k, _v} -> to_string(k) end)
        end
      end
      """)
    end

    test "MapSet for membership tracking" do
      assert_clean("""
      defmodule Deduplicator do
        def dedup(list) do
          {_seen, acc} =
            Enum.reduce(list, {MapSet.new(), []}, fn item, {seen, acc} ->
              if MapSet.member?(seen, item) do
                {seen, acc}
              else
                {MapSet.put(seen, item), [item | acc]}
              end
            end)

          Enum.reverse(acc)
        end
      end
      """)
    end

    test "group-by pattern with Map.update and list default" do
      assert_clean("""
      defmodule IndexByFirstLetter do
        def build(words) do
          Enum.reduce(words, %{}, fn word, acc ->
            first = String.first(word)

            Map.update(acc, first, [word], fn existing ->
              [word | existing]
            end)
          end)
        end
      end
      """)
    end
  end

  describe "idiomatic numeric and algorithmic patterns" do
    test "Gauss formula for missing number" do
      assert_clean("""
      defmodule MissingNumber do
        def missing_number(nums) do
          n = length(nums)
          div(n * (n + 1), 2) - Enum.sum(nums)
        end
      end
      """)
    end

    test "Kadane's algorithm with reduce" do
      assert_clean("""
      defmodule MaxSubarray do
        def max_subarray_sum([head | tail]) do
          {_current, global} =
            Enum.reduce(tail, {head, head}, fn num, {curr, glob} ->
              new_curr = max(num, curr + num)
              {new_curr, max(glob, new_curr)}
            end)

          global
        end
      end
      """)
    end

    test "sliding window with Enum.zip" do
      assert_clean("""
      defmodule MaxAverage do
        def find_max_average(nums, window_size) do
          {window, rest} = Enum.split(nums, window_size)
          initial_sum = Enum.sum(window)

          Stream.zip(rest, nums)
          |> Enum.reduce({initial_sum, initial_sum / window_size}, fn {incoming, outgoing}, {sum, max_avg} ->
            new_sum = sum + incoming - outgoing
            {new_sum, max(max_avg, new_sum / window_size)}
          end)
          |> elem(1)
        end
      end
      """)
    end

    test "stock profit with single-pass reduce" do
      assert_clean("""
      defmodule StockProfit do
        def max_profit([]), do: 0

        def max_profit([first | rest]) do
          {_, profit} =
            Enum.reduce(rest, {first, 0}, fn price, {min_p, max_p} ->
              {min(min_p, price), max(max_p, price - min_p)}
            end)

          profit
        end
      end
      """)
    end

    test "tail-recursive Fibonacci with accumulator" do
      assert_clean("""
      defmodule Fibonacci do
        def fib(0), do: 0
        def fib(1), do: 1

        def fib(num) when is_integer(num) and num > 1 do
          fib_loop(num, 0, 1)
        end

        defp fib_loop(1, _prev, curr), do: curr
        defp fib_loop(num, prev, curr), do: fib_loop(num - 1, curr, prev + curr)
      end
      """)
    end

    test "Integer.digits for digit extraction" do
      assert_clean("""
      defmodule DigitSum do
        def sum_of_digits(number) do
          number |> abs() |> Integer.digits() |> Enum.sum()
        end
      end
      """)
    end
  end

  describe "idiomatic control flow" do
    test "predicate with ? suffix" do
      assert_clean("""
      defmodule Validator do
        def valid?(age) when is_integer(age) and age > 0, do: true
        def valid?(_), do: false
      end
      """)
    end

    test "pattern matching on literals in function heads (not when ==)" do
      assert_clean("""
      defmodule Staircase do
        def count_ways(0), do: 1
        def count_ways(1), do: 1
        def count_ways(2), do: 2
        def count_ways(steps) when steps > 2,
          do: do_count(steps - 2, 1, 1, 2)

        defp do_count(0, _, _, prev1), do: prev1
        defp do_count(remaining, prev3, prev2, prev1), do: do_count(remaining - 1, prev2, prev1, prev3 + prev2 + prev1)
      end
      """)
    end

    test "with block for chaining results" do
      assert_clean("""
      defmodule Parser do
        def parse(input) do
          with {:ok, tokens} <- tokenize(input),
               {:ok, ast} <- build_ast(tokens) do
            {:ok, ast}
          end
        end

        defp tokenize(input), do: {:ok, String.split(input)}
        defp build_ast(tokens), do: {:ok, tokens}
      end
      """)
    end

    test "then/2 in pipelines" do
      assert_clean("""
      defmodule PipeHelper do
        def process(list) do
          list
          |> Enum.sort()
          |> then(fn sorted -> [0 | sorted] end)
        end
      end
      """)
    end
  end

  describe "idiomatic data structures" do
    test "MapSet.intersection for set operations" do
      assert_clean("""
      defmodule SetOps do
        def intersection(list1, list2) do
          MapSet.intersection(MapSet.new(list1), MapSet.new(list2))
          |> MapSet.to_list()
        end
      end
      """)
    end

    test "Stream.with_index for lazy indexing" do
      assert_clean("""
      defmodule IndexedProcessor do
        def process(list) do
          list
          |> Stream.with_index()
          |> Enum.reduce([], fn {val, idx}, acc ->
            [{idx, val * 2} | acc]
          end)
          |> Enum.reverse()
        end
      end
      """)
    end

    test "Enum.sort_by for sorting with key function" do
      assert_clean("""
      defmodule Sorter do
        def by_length(strings) do
          Enum.sort_by(strings, &String.length/1)
        end

        def by_name_desc(records) do
          Enum.sort_by(records, & &1.name, :desc)
        end
      end
      """)
    end

    test "reduce with distinct new_ prefixed accumulator variables" do
      assert_clean("""
      defmodule Processor do
        def process(items) do
          Enum.reduce(items, {0, []}, fn item, {count, acc} ->
            new_count = count + 1
            new_acc = [item * 2 | acc]
            {new_count, new_acc}
          end)
        end
      end
      """)
    end
  end

  describe "edge cases that should NOT trigger rules" do
    test "list ++ outside of any loop" do
      assert_clean("""
      defmodule SafeConcat do
        def concat(list_a, list_b), do: list_a ++ list_b
        def prepend_header(list), do: ["header"] ++ list
      end
      """)
    end

    test "String.length compared to non-1 values" do
      assert_clean("""
      defmodule LengthCheck do
        def long_enough?(string), do: String.length(string) >= 8
        def too_short?(string), do: String.length(string) < 3
      end
      """)
    end

    test "Enum.at outside of any loop (single access)" do
      assert_clean("""
      defmodule SingleAccess do
        def middle(list) do
          mid = div(length(list), 2)
          Enum.at(list, mid)
        end
      end
      """)
    end

    test "Enum.drop and Enum.take with positive counts" do
      assert_clean("""
      defmodule SliceOps do
        def skip_first_three(list), do: Enum.drop(list, 3)
        def take_five(list), do: Enum.take(list, 5)
      end
      """)
    end

    test "Map.put with non-boolean meaningful values" do
      assert_clean("""
      defmodule Config do
        def set_defaults(map) do
          map
          |> Map.put(:timeout, 5000)
          |> Map.put(:retries, 3)
          |> Map.put(:name, "default")
        end
      end
      """)
    end

    test "Map.update with non-frequency default (group-by)" do
      assert_clean("""
      defmodule Grouper do
        def group_by_type(items) do
          Enum.reduce(items, %{}, fn item, acc ->
            Map.update(acc, item.type, [item], fn existing ->
              [item | existing]
            end)
          end)
        end
      end
      """)
    end

    test "length/1 in function body (not guard)" do
      assert_clean("""
      defmodule BodyLength do
        def process(list) when is_list(list) do
          n = length(list)
          div(n * (n + 1), 2)
        end
      end
      """)
    end

    test "anonymous function without rebinding params" do
      assert_clean("""
      defmodule CleanReduce do
        def sum_evens(list) do
          Enum.reduce(list, 0, fn x, acc ->
            if rem(x, 2) == 0, do: acc + x, else: acc
          end)
        end
      end
      """)
    end
  end

  test "does NOT flag idiomatic word counting" do
    code = """
      defmodule WordCounter do
        def count(text) when is_binary(text) do
          text
          |> String.downcase()
          |> String.replace(~r/[^\p{L}\s]/u, "")
          |> String.split()
          |> Enum.frequencies()
        end
      end
    """

    result = Credence.analyze(code)
    assert result.valid == true
    assert result.issues == []
  end

  test "does NOT flag idiomatic chart counting" do
    code = """
      defmodule CharCounter do
        def count(text) when is_binary(text) do
          text
          |> String.graphemes()
          |> Enum.frequencies()
        end
      end
    """

    result = Credence.analyze(code)
    assert result.valid == true
    assert result.issues == []
  end

  test "does NOT flag idiomatic unique word extraction" do
    code = """
      defmodule UniqueWords do
        def extract(text) when is_binary(text) do
          text
          |> String.downcase()
          |> String.split(~r/\W+/u, trim: true)
          |> MapSet.new()
        end
      end
    """

    result = Credence.analyze(code)
    assert result.valid == true
    assert result.issues == []
  end

  test "does NOT flag idiomatic longest word extraction" do
    code = """
      defmodule LongestWord do
        def find(text) when is_binary(text) do
          text
          |> String.split(~r/\W+/u, trim: true)
          |> Enum.max_by(&String.length/1, fn -> "" end)
        end
      end
    """

    result = Credence.analyze(code)
    assert result.valid == true
    assert result.issues == []
  end

  test "does NOT flag idiomatic word grouping by length" do
    code = """
      defmodule WordGrouper do
        def group_by_length(text) when is_binary(text) do
          text
          |> String.split(~r/\W+/u, trim: true)
          |> Enum.group_by(&String.length/1)
        end
      end
    """

    result = Credence.analyze(code)
    assert result.valid == true
    assert result.issues == []
  end

  test "does NOT flag idiomatic recursive word counting" do
    code = """
      defmodule RecursiveCounter do
        def count(text) when is_binary(text) do
          text
          |> String.downcase()
          |> String.split(~r/\W+/u, trim: true)
          |> do_count(%{})
        end

        defp do_count([], acc), do: acc

        defp do_count([word | rest], acc) do
          updated =
            Map.update(acc, word, 1, fn count -> count + 1 end)

          do_count(rest, updated)
        end
      end
    """

    result = Credence.analyze(code)
    assert result.valid == true
    assert result.issues == []
  end

  test "does NOT flag idiomatic index by first letter" do
    code = """
      defmodule IndexByFirstLetter do
        def build(words) do
          Enum.reduce(words, %{}, fn word, acc ->
            first = String.first(word)

            Map.update(acc, first, [word], fn existing ->
              [word | existing]
            end)
          end)
        end
      end
    """

    result = Credence.analyze(code)
    assert result.valid == true
    assert result.issues == []
  end
end
