defmodule Credence.Rule.NoNestedEnumOnSameEnumerableTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoNestedEnumOnSameEnumerable.check(ast, [])
  end

  describe "NoNestedEnumOnSameEnumerable" do
    test "detects filter inside map with specific advice" do
      code = """
      defmodule Bad do
        def process(list) do
          Enum.map(list, fn x ->
            Enum.filter(list, fn y -> y > x end)
          end)
        end
      end
      """

      [issue] = check(code)

      assert %Issue{} = issue
      assert issue.message =~ "Enum.filter/2"
      assert issue.message =~ "O(n²)"
      assert issue.message =~ "Avoid filtering the same list repeatedly"
    end

    test "detects member? and suggests MapSet" do
      code = """
      defmodule Bad do
        def process(list) do
          Enum.map(list, fn x ->
            Enum.member?(list, x + 1)
          end)
        end
      end
      """

      [issue] = check(code)

      assert issue.message =~ "MapSet"
      assert issue.message =~ "O(n²)"
    end

    test "falls back to generic message for other Enum functions" do
      code = """
      defmodule Bad do
        def process(list) do
          Enum.map(list, fn x ->
            Enum.count(list)
          end)
        end
      end
      """

      [issue] = check(code)

      assert issue.message =~ "Nested Enum.count"
      assert issue.message =~ "O(n²)"
    end

    test "does not flag different enumerables" do
      code = """
      defmodule Good do
        def process(a, b) do
          Enum.map(a, fn x ->
            Enum.filter(b, fn y -> y > x end)
          end)
        end
      end
      """

      assert check(code) == []
    end
  end
end
