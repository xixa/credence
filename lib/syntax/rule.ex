defmodule Credence.Syntax.Rule do
  @moduledoc """
  Behaviour for syntax-level rules that fix code which won't parse.

  These rules work on raw source strings (no AST available).
  Each rule detects a known LLM syntax error pattern and can fix it.
  """

  @doc "Detect issues in unparseable source. Returns list of issues."
  @callback analyze(source :: String.t()) :: [Credence.Issue.t()]

  @doc "Attempt to fix the source. Returns the (possibly modified) source."
  @callback fix(source :: String.t()) :: String.t()

  defmacro __using__(_opts) do
    quote do
      @behaviour Credence.Syntax.Rule
    end
  end
end
