defmodule Credence.Rule.NoEagerWithIndexInReduceTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoEagerWithIndexInReduce.check(ast, [])
  end

  describe "NoEagerWithIndexInReduce" do
    test "passes Stream.with_index piped into Enum.reduce" do
      code = """
      defmodule GoodStream do
        def process(list) do
          list
          |> Stream.with_index()
          |> Enum.reduce([], fn {val, idx}, acc -> [{idx, val} | acc] end)
        end
      end
      """

      assert check(code) == []
    end

    test "passes index tracked in accumulator" do
      code = """
      defmodule GoodAccumulator do
        def process(list) do
          Enum.reduce(list, {0, []}, fn val, {idx, acc} ->
            {idx + 1, [{idx, val} | acc]}
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "passes Enum.with_index used without reduce" do
      code = """
      defmodule SafeWithIndex do
        def indexed(list) do
          Enum.with_index(list)
        end
      end
      """

      assert check(code) == []
    end

    test "detects Enum.reduce(Enum.with_index(list), ...)" do
      code = """
      defmodule BadDirect do
        def process(list) do
          Enum.reduce(Enum.with_index(list), [], fn {val, idx}, acc ->
            [{idx, val} | acc]
          end)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_eager_with_index_in_reduce
      assert issue.severity == :warning
      assert issue.message =~ "Enum.with_index"
      assert issue.message =~ "Stream.with_index"
      assert issue.meta.line != nil
    end

    test "detects list |> Enum.with_index() |> Enum.reduce(...)" do
      code = """
      defmodule BadPiped do
        def process(list) do
          list
          |> Enum.with_index()
          |> Enum.reduce([], fn {val, idx}, acc ->
            [{idx, val} | acc]
          end)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_eager_with_index_in_reduce
    end

    test "passes Enum.with_index piped into Enum.map (not reduce)" do
      code = """
      defmodule SafeMap do
        def process(list) do
          list
          |> Enum.with_index()
          |> Enum.map(fn {val, idx} -> {idx, val} end)
        end
      end
      """

      assert check(code) == []
    end
  end
end
