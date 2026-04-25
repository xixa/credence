defmodule Credence.Rule.NoSortForTopKTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoSortForTopK.check(ast, [])
  end

  describe "NoSortForTopK" do
    test "detects sort |> take(1)" do
      code = """
      defmodule Bad do
        def f(list) do
          Enum.sort(list) |> Enum.take(1)
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.max"
    end

    test "detects sort |> take(2)" do
      code = """
      defmodule Bad do
        def f(list) do
          Enum.sort(list) |> Enum.take(2)
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "top 2"
    end

    test "detects sort |> hd" do
      code = """
      defmodule Bad do
        def f(list) do
          Enum.sort(list) |> hd()
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "hd"
    end

    test "detects sort |> Enum.at(0)" do
      code = """
      defmodule Bad do
        def f(list) do
          Enum.sort(list) |> Enum.at(0)
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.min"
    end

    test "detects sort |> reverse |> take" do
      code = """
      defmodule Bad do
        def f(list) do
          Enum.sort(list) |> Enum.reverse() |> Enum.take(2)
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "top 2"
    end

    test "does not flag unrelated pipelines" do
      code = """
      defmodule Good do
        def f(list) do
          list |> Enum.map(&(&1 * 2)) |> Enum.take(2)
        end
      end
      """

      assert check(code) == []
    end
  end
end
