defmodule Credence.Pattern.NonGroupedClausesFixTest do
  use ExUnit.Case

  defp fix(code) do
    Credence.Pattern.NonGroupedClauses.fix(code, [])
  end

  describe "reorders stray clauses to join siblings" do
    test "simple case: def foo, def bar, def foo → grouped" do
      input = """
      defmodule M do
        def foo(1), do: 1
        def bar(x), do: x
        def foo(x), do: x + 1
      end
      """

      fixed = fix(input)
      # foo clauses should be consecutive
      assert fixed =~ "def foo(1), do: 1"
      assert fixed =~ "def foo(x), do: x + 1"
      assert fixed =~ "def bar(x), do: x"
      # foo(x) should come right after foo(1), before bar
      foo1_pos = :binary.match(fixed, "foo(1)") |> elem(0)
      foox_pos = :binary.match(fixed, "foo(x)") |> elem(0)
      bar_pos = :binary.match(fixed, "bar(x)") |> elem(0)
      assert foo1_pos < foox_pos
      assert foox_pos < bar_pos
    end

    test "three clauses of same function" do
      input = """
      defmodule M do
        def foo(1), do: 1
        def bar(x), do: x
        def foo(2), do: 2
        def baz(x), do: x
        def foo(x), do: x + 1
      end
      """

      fixed = fix(input)
      foo1_pos = :binary.match(fixed, "foo(1)") |> elem(0)
      foo2_pos = :binary.match(fixed, "foo(2)") |> elem(0)
      foox_pos = :binary.match(fixed, "foo(x)") |> elem(0)
      bar_pos = :binary.match(fixed, "bar(x)") |> elem(0)
      # All foos grouped before bar
      assert foo1_pos < foo2_pos
      assert foo2_pos < foox_pos
      assert foox_pos < bar_pos
    end

    test "defp clauses grouped" do
      input = """
      defmodule M do
        defp helper(1), do: :one
        defp other(x), do: x
        defp helper(x), do: :other
      end
      """

      fixed = fix(input)
      h1_pos = :binary.match(fixed, "helper(1)") |> elem(0)
      hx_pos = :binary.match(fixed, "helper(x)") |> elem(0)
      other_pos = :binary.match(fixed, "other(x)") |> elem(0)
      assert h1_pos < hx_pos
      assert hx_pos < other_pos
    end
  end

  describe "preserves content" do
    test "module attributes stay in place" do
      input = """
      defmodule M do
        @moduledoc false
        def foo(1), do: 1
        def bar(x), do: x
        def foo(x), do: x + 1
      end
      """

      fixed = fix(input)
      assert fixed =~ "@moduledoc false"
      assert fixed =~ "def foo(1)"
      assert fixed =~ "def foo(x)"
      assert fixed =~ "def bar(x)"
    end

    test "different arities not mixed" do
      input = """
      defmodule M do
        def foo(x), do: x
        def bar(x), do: x
        def foo(x, y), do: x + y
      end
      """

      # foo/1 and foo/2 are different functions — no reordering needed
      fixed = fix(input)
      foo1_pos = :binary.match(fixed, "foo(x), do: x\n") |> elem(0)
      bar_pos = :binary.match(fixed, "bar(x)") |> elem(0)
      foo2_pos = :binary.match(fixed, "foo(x, y)") |> elem(0)
      assert foo1_pos < bar_pos
      assert bar_pos < foo2_pos
    end
  end

  describe "no-ops" do
    test "already grouped — no change" do
      input = """
      defmodule M do
        def foo(1), do: 1
        def foo(x), do: x + 1
        def bar(x), do: x
      end
      """

      assert fix(input) == String.trim_trailing(input)
    end

    test "single clause per function — no change" do
      input = """
      defmodule M do
        def foo(x), do: x
        def bar(x), do: x * 2
      end
      """

      assert fix(input) == String.trim_trailing(input)
    end
  end
end
