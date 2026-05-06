defmodule Credence.Semantic.UndefinedFunctionTest do
  use ExUnit.Case

  alias Credence.Semantic.UndefinedFunction

  # ── Unit tests (rule logic with synthetic diagnostics) ──────────

  describe "match?/1" do
    test "matches known undefined function" do
      diag = %{
        severity: :warning,
        message: "Enum.last/1 is undefined or private",
        position: {5, 10}
      }

      assert UndefinedFunction.match?(diag)
    end

    test "matches arity-0 variant" do
      diag = %{
        severity: :warning,
        message: "Enum.last/0 is undefined or private",
        position: {5, 10}
      }

      assert UndefinedFunction.match?(diag)
    end

    test "does not match unknown undefined function" do
      diag = %{
        severity: :warning,
        message: "MyModule.foo/2 is undefined or private",
        position: {5, 10}
      }

      refute UndefinedFunction.match?(diag)
    end

    test "does not match unrelated warning" do
      diag = %{
        severity: :warning,
        message: "some other warning",
        position: {5, 10}
      }

      refute UndefinedFunction.match?(diag)
    end

    test "does not match error severity" do
      diag = %{
        severity: :error,
        message: "Enum.last/1 is undefined or private",
        position: {5, 10}
      }

      refute UndefinedFunction.match?(diag)
    end
  end

  describe "fix/2 (unit)" do
    test "replaces Enum.last with List.last" do
      source = """
      def run(list) do
        Enum.last(list)
      end
      """

      diag = %{
        severity: :warning,
        message: "Enum.last/1 is undefined or private",
        position: {2, 5}
      }

      fixed = UndefinedFunction.fix(source, diag)
      assert fixed =~ "List.last(list)"
      refute fixed =~ "Enum.last"
    end

    test "replaces only on the reported line" do
      source = """
      first = Enum.at(list, 0)
      last = Enum.last(list)
      count = Enum.count(list)
      """

      diag = %{
        severity: :warning,
        message: "Enum.last/1 is undefined or private",
        position: {2, 8}
      }

      fixed = UndefinedFunction.fix(source, diag)
      lines = String.split(fixed, "\n")
      assert Enum.at(lines, 1) =~ "List.last"
      # Other lines untouched
      assert Enum.at(lines, 0) =~ "Enum.at"
      assert Enum.at(lines, 2) =~ "Enum.count"
    end

    test "handles piped form" do
      source = """
      def run(list) do
        list |> Enum.last()
      end
      """

      diag = %{
        severity: :warning,
        message: "Enum.last/0 is undefined or private",
        position: {2, 15}
      }

      fixed = UndefinedFunction.fix(source, diag)
      assert fixed =~ "List.last"
      refute fixed =~ "Enum.last"
    end

    test "returns source unchanged for unknown function" do
      source = """
      def run(x) do
        MyModule.foo(x)
      end
      """

      diag = %{
        severity: :warning,
        message: "MyModule.foo/1 is undefined or private",
        position: {2, 5}
      }

      assert UndefinedFunction.fix(source, diag) == source
    end
  end

  describe "to_issue/1" do
    test "builds issue with correct rule and line" do
      diag = %{
        severity: :warning,
        message: "Enum.last/1 is undefined or private",
        position: {10, 5}
      }

      issue = UndefinedFunction.to_issue(diag)
      assert issue.rule == :undefined_function
      assert issue.meta.line == 10
      assert issue.message =~ "Enum.last"
    end
  end
end
