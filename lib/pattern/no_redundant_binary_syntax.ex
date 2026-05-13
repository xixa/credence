defmodule Credence.Pattern.NoRedundantBinarySyntax do
  @moduledoc """
  Detects string literals needlessly wrapped in `<<>>` binary syntax.

  In Elixir, strings are already UTF-8 encoded binaries. Wrapping a
  string literal in `<<>>` is completely redundant — `<<"hello">>` is
  identical to `"hello"`. LLMs often add this wrapper when working with
  graphemes or character lists, carrying over intuitions from languages
  where strings and byte sequences are distinct types.

  ## Bad

      <<"hello">>
      [<<"b">>, <<"a">>, <<"n">>]

  ## Good

      "hello"
      ["b", "a", "n"]

  ## What is flagged

  Any `<<>>` binary form containing a single string literal with no type
  specifiers. Multi-segment binaries (`<<"a", "b">>`), byte values
  (`<<1, 2, 3>>`), and typed segments (`<<x::utf8>>`, `<<"a"::binary>>`)
  are not flagged.

  Sigil internals (`~r/pattern/`, `~s(text)`, `~w(words)`, etc.) are
  never flagged — their `<<>>` nodes are AST implementation details,
  not user-written binary syntax.

  ## Auto-fix

  Unwraps the string literal by removing the surrounding `<<` and `>>`.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        if sigil_node?(node) do
          # Replace with an opaque atom so prewalk does not recurse into
          # the sigil's children — their <<>> is an AST implementation
          # detail, not user-written binary syntax.
          {:__sigil_skip__, acc}
        else
          case detect_pattern(node) do
            {:ok, meta} -> {node, [build_issue(meta) | acc]}
            :skip -> {node, acc}
          end
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix(source, _opts) do
    source
    |> String.split("\n")
    |> Enum.map(&fix_line/1)
    |> Enum.join("\n")
  end

  # ── Detection ───────────────────────────────────────────────────

  # <<>> with a single child that is a plain string literal (binary).
  # This excludes: multi-segment binaries, byte values, variables,
  # and any segment with a type specifier (::).
  defp detect_pattern({:<<>>, meta, [child]}) when is_binary(child) do
    {:ok, meta}
  end

  defp detect_pattern(_), do: :skip

  # All sigils (built-in and custom) are {:sigil_X, meta, children}
  # where X is a letter. Their first child is always a <<>> node that
  # holds the sigil content — we must not inspect it.
  defp sigil_node?({name, _, _}) when is_atom(name) do
    case Atom.to_string(name) do
      "sigil_" <> _ -> true
      _ -> false
    end
  end

  defp sigil_node?(_), do: false

  # ── Fix ─────────────────────────────────────────────────────────

  @redundant_binary_re ~r/<<\s*("(?:[^"\\\\]|\\\\.)*")\s*>>/

  defp fix_line(line) do
    Regex.replace(@redundant_binary_re, line, fn _full, string_literal ->
      string_literal
    end)
  end

  # ── Issue ───────────────────────────────────────────────────────

  defp build_issue(meta) do
    %Issue{
      rule: :no_redundant_binary_syntax,
      message: """
      Wrapping a string literal in `<<>>` is redundant — strings \
      are already binaries in Elixir.

      Replace with the bare string literal:

          <<"hello">>    →    "hello"
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
