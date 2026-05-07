defmodule Credence.Pattern.FixWithTraceSourceAwarenessTest do
  use ExUnit.Case

  # ── Prove the bug: checks give different results with/without source ──

  describe "check behaviour depends on :source in opts" do
    test "PreferHeredocForMultiLineDoc falsely flags multi-line heredoc without source" do
      # Multi-line content is required — single-line heredocs don't trigger multi_line? check
      code = ~S'''
      defmodule Example do
        @doc """
        Summary line.

        ## Details

        More explanation here.
        """
        def foo, do: :ok
      end
      '''

      {:ok, ast} = Code.string_to_quoted(code)

      # Without source: check cannot tell it's already a heredoc → flags it
      issues_no_source = Credence.Pattern.PreferHeredocForMultiLineDoc.check(ast, [])

      assert length(issues_no_source) > 0,
             "Expected check to false-detect multi-line heredoc when :source is missing"

      # With source: check sees """ on the source line → skips it
      issues_with_source =
        Credence.Pattern.PreferHeredocForMultiLineDoc.check(ast, source: code)

      assert issues_with_source == [],
             "Expected check to skip heredoc when :source is provided"
    end

    test "NoTrailingNewlineInDoc falsely flags single-line heredoc without source" do
      # A single-line heredoc's AST value is "Content.\n" — trailing newline only
      code = ~S'''
      defmodule Example do
        @moduledoc """
        Just one line of module docs.
        """
        def foo, do: :ok
      end
      '''

      {:ok, ast} = Code.string_to_quoted(code)

      issues_no_source = Credence.Pattern.NoTrailingNewlineInDoc.check(ast, [])

      assert length(issues_no_source) > 0,
             "Expected check to false-detect single-line heredoc when :source is missing"

      issues_with_source =
        Credence.Pattern.NoTrailingNewlineInDoc.check(ast, source: code)

      assert issues_with_source == [],
             "Expected check to skip heredoc when :source is provided"
    end
  end

  # ── Confirm fix_with_trace passes :source so checks don't false-trigger ──

  describe "fix_with_trace passes :source to rule checks" do
    test "PreferHeredocForMultiLineDoc not in applied list for multi-line heredoc" do
      code = ~S'''
      defmodule Example do
        @doc """
        Summary line.

        ## Details

        More explanation here.
        """
        def foo, do: :ok
      end
      '''

      {fixed, applied} =
        Credence.Pattern.fix_with_trace(code,
          rules: [Credence.Pattern.PreferHeredocForMultiLineDoc]
        )

      assert fixed == code

      assert applied == [],
             "Expected no rules applied but got: #{inspect(applied)}"
    end

    test "NoTrailingNewlineInDoc not in applied list for single-line heredoc" do
      code = ~S'''
      defmodule Example do
        @moduledoc """
        Just one line of module docs.
        """
        def foo, do: :ok
      end
      '''

      {fixed, applied} =
        Credence.Pattern.fix_with_trace(code,
          rules: [Credence.Pattern.NoTrailingNewlineInDoc]
        )

      assert fixed == code

      assert applied == [],
             "Expected no rules applied but got: #{inspect(applied)}"
    end

    test "still fixes actual single-line string issues alongside heredocs" do
      code = ~S'''
      defmodule Example do
        @moduledoc """
        Multi-line heredoc.

        Should not be touched.
        """

        @doc "Function doc with trailing newline.\n"
        def foo, do: :ok
      end
      '''

      {fixed, applied} =
        Credence.Pattern.fix_with_trace(code,
          rules: [
            Credence.Pattern.NoTrailingNewlineInDoc,
            Credence.Pattern.PreferHeredocForMultiLineDoc
          ]
        )

      # The single-line @doc trailing \n should be fixed
      refute fixed =~ ~S|"Function doc with trailing newline.\n"|
      assert fixed =~ ~S|"Function doc with trailing newline."|

      # The heredoc should be untouched
      assert fixed =~ "Should not be touched."

      # Only NoTrailingNewlineInDoc should appear in applied
      applied_rules = Enum.map(applied, fn {rule, _} -> rule end)
      assert Credence.Pattern.NoTrailingNewlineInDoc in applied_rules
      refute Credence.Pattern.PreferHeredocForMultiLineDoc in applied_rules
    end
  end
end
