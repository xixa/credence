defmodule Credence.Rule.NoAnonFnApplicationInPipe do
  @moduledoc """
  Readability rule: Detects anonymous functions applied with `.()` inside
  a pipeline.

  Applying an anonymous function directly in a pipe (e.g.
  `|> (fn x -> ... end).()`) is non-idiomatic and hard to read.
  Use `then/2` instead, which was added in Elixir 1.12 specifically
  for this purpose.

  ## Bad

      list
      |> Enum.sort()
      |> (fn s -> [1 | s] end).()

  ## Good

      list
      |> Enum.sort()
      |> then(fn s -> [1 | s] end)

      # Or with capture syntax:
      |> then(&[1 | &1])
  """
  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Match: ... |> (fn ... end).()
        # The AST shape is: {:|>, meta, [left, {{:., _, [{:fn, _, _}]}, _, args}]}
        {:|>, meta, [_left, {{:., _, [{:fn, _, _}]}, _, _args}]} = node, issues ->
          issue = %Issue{
            rule: :no_anon_fn_application_in_pipe,
            severity: :warning,
            message:
              "Avoid applying anonymous functions with `.()` inside a pipeline. " <>
                "Use `then/2` instead: `|> then(fn x -> ... end)`.",
            meta: %{line: Keyword.get(meta, :line)}
          }

          {node, [issue | issues]}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end
end
