defmodule Credence.Rule.NoManualEnumUniqTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoManualEnumUniq.check(ast, [])
  end

  describe "NoManualEnumUniq" do
    test "flags manual Enum.uniq/1 using MapSet and reduce" do
      code = """
      defmodule Example do
        def run(list) do
          Enum.reduce(list, {MapSet.new(), []}, fn item, {seen, acc} ->
            if MapSet.member?(seen, item) do
              {seen, acc}
            else
              {MapSet.put(seen, item), [item | acc]}
            end
          end)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags even if variable names are different or logic is inverted" do
      code = """
      defmodule Example do
        def run(list) do
          Enum.reduce(list, {[], MapSet.new()}, fn x, {results, tracked} ->
            unless MapSet.member?(tracked, x) do
              {[x | results], MapSet.put(tracked, x)}
            else
              {results, tracked}
            end
          end)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "does not flag normal Enum.reduce summing numbers" do
      code = """
      defmodule Example do
        def run(list) do
          Enum.reduce(list, 0, fn item, acc ->
            item + acc
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.reduce using MapSet purely as an accumulator" do
      code = """
      defmodule Example do
        def run(list) do
          Enum.reduce(list, MapSet.new(), fn item, acc ->
            MapSet.put(acc, item)
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag valid Enum.uniq/1 usages" do
      code = "Enum.uniq(list)"
      assert check(code) == []
    end
  end
end
