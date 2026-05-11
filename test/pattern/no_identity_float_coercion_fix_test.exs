defmodule Credence.Pattern.NoIdentityFloatCoercionFixTest do
  use ExUnit.Case

  defp fix(code) do
    Credence.Pattern.NoIdentityFloatCoercion.fix(code, [])
  end

  # ═══════════════════════════════════════════════════════════════════
  # MULTIPLY BY 1.0 — removal
  # ═══════════════════════════════════════════════════════════════════

  describe "fix * 1.0" do
    test "removes trailing * 1.0" do
      assert fix("n * 1.0") =~ "n"
      refute fix("n * 1.0") =~ "1.0"
    end

    test "removes leading 1.0 *" do
      assert fix("1.0 * n") =~ "n"
      refute fix("1.0 * n") =~ "1.0"
    end

    test "removes * 1.0 from complex expression" do
      fixed = fix("Enum.at(list, 0) * 1.0")
      assert fixed =~ "Enum.at(list, 0)"
      refute fixed =~ "* 1.0"
    end

    test "removes * 1.0 in arithmetic context" do
      fixed = fix("a + b * 1.0")
      assert fixed =~ "a + b"
      refute fixed =~ "1.0"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # DIVIDE BY 1.0 — removal
  # ═══════════════════════════════════════════════════════════════════

  describe "fix / 1.0" do
    test "removes / 1.0" do
      fixed = fix("n / 1.0")
      assert fixed =~ "n"
      refute fixed =~ "1.0"
      refute fixed =~ "/"
    end

    test "removes / 1.0 from complex expression" do
      fixed = fix("Enum.at(combined, mid_index) / 1.0")
      assert fixed =~ "Enum.at(combined, mid_index)"
      refute fixed =~ "/ 1.0"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # ADD 0.0 — removal
  # ═══════════════════════════════════════════════════════════════════

  describe "fix + 0.0" do
    test "removes trailing + 0.0" do
      fixed = fix("n + 0.0")
      assert fixed =~ "n"
      refute fixed =~ "0.0"
    end

    test "removes leading 0.0 +" do
      fixed = fix("0.0 + n")
      assert fixed =~ "n"
      refute fixed =~ "0.0"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SUBTRACT 0.0 — removal
  # ═══════════════════════════════════════════════════════════════════

  describe "fix - 0.0" do
    test "removes trailing - 0.0" do
      fixed = fix("n - 0.0")
      assert fixed =~ "n"
      refute fixed =~ "0.0"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SELF-ASSIGNMENT — line deletion
  # ═══════════════════════════════════════════════════════════════════

  describe "self-assignment deletion" do
    test "deletes var = var * 1.0" do
      code = """
      defmodule Example do
        def run(count) do
          count = count * 1.0
          count
        end
      end
      """

      fixed = fix(code)
      refute fixed =~ "count = count"
      refute fixed =~ "1.0"
      assert fixed =~ "count"
    end

    test "deletes var = 1.0 * var" do
      code = """
      defmodule Example do
        def run(n) do
          n = 1.0 * n
          n
        end
      end
      """

      fixed = fix(code)
      refute fixed =~ "n = 1.0"
      refute fixed =~ "n = n"
    end

    test "deletes var = var / 1.0" do
      code = """
      defmodule Example do
        def run(n) do
          n = n / 1.0
          n
        end
      end
      """

      fixed = fix(code)
      refute fixed =~ "n = n"
      refute fixed =~ "/ 1.0"
    end

    test "deletes var = var + 0.0" do
      code = """
      defmodule Example do
        def run(n) do
          n = n + 0.0
          n
        end
      end
      """

      fixed = fix(code)
      refute fixed =~ "n = n"
      refute fixed =~ "0.0"
    end

    test "deletes var = var - 0.0" do
      code = """
      defmodule Example do
        def run(n) do
          n = n - 0.0
          n
        end
      end
      """

      fixed = fix(code)
      refute fixed =~ "n = n"
      refute fixed =~ "0.0"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SURROUNDING CODE — preservation
  # ═══════════════════════════════════════════════════════════════════

  describe "preserves surrounding code" do
    test "only touches the offending line" do
      code = """
      defmodule Example do
        def foo(n), do: n + 1

        def bar(n), do: n * 1.0

        def baz(n), do: n - 1
      end
      """

      fixed = fix(code)
      assert fixed =~ "def foo(n), do: n + 1"
      assert fixed =~ "def bar(n), do: n"
      assert fixed =~ "def baz(n), do: n - 1"
      refute fixed =~ "1.0"
    end

    test "fixes multiple identity ops in one module" do
      code = """
      defmodule Example do
        def foo(n), do: n * 1.0
        def bar(n), do: n / 1.0
      end
      """

      fixed = fix(code)
      refute fixed =~ "1.0"
      assert fixed =~ "def foo(n)"
      assert fixed =~ "def bar(n)"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SAFETY — must not touch
  # ═══════════════════════════════════════════════════════════════════

  describe "does not modify clean code" do
    test "leaves * 2.0 alone" do
      code = "def run(n), do: n * 2.0"
      assert fix(code) == code
    end

    test "leaves * 1.05 alone" do
      code = "def run(n), do: n * 1.05"
      assert fix(code) == code
    end

    test "leaves / 1 (integer) alone" do
      code = "def run(n), do: n / 1"
      assert fix(code) == code
    end

    test "leaves / 2.0 alone" do
      code = "def run(n), do: n / 2.0"
      assert fix(code) == code
    end

    test "leaves 0.0 - expr alone (negation)" do
      code = "def run(n), do: 0.0 - n"
      assert fix(code) == code
    end

    test "leaves + 1.0 alone" do
      code = "def run(n), do: n + 1.0"
      assert fix(code) == code
    end

    test "returns source unchanged when nothing to fix" do
      code = """
      defmodule Example do
        def run(n), do: n / 1
      end
      """

      assert fix(code) == code
    end

    test "leaves * 1.0e5 alone" do
      code = """
      defmodule Example do
        def run(n), do: n * 1.0e5
      end
      """

      assert fix(code) == code
    end
  end
end
