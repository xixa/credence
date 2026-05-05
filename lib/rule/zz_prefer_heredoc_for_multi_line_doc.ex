defmodule Credence.Rule.ZzPreferHeredocForMultiLineDoc do
  @moduledoc """
  Detects `@doc`, `@moduledoc`, and `@typedoc` strings that contain
  escaped newlines (`\\n`) and should use heredoc syntax instead.

  LLMs generate documentation as single-line strings with `\\n` escapes
  because that's how Python docstrings work. In Elixir, multi-line
  documentation should use the heredoc (`\"\"\"`) syntax for readability.

  ## Bad

      @doc "Finds the second largest number in a list.\\nThe list must have at least two distinct values.\\n"

  ## Good

      @doc \"\"\"
      Finds the second largest number in a list.
      The list must have at least two distinct values.
      \"\"\"

  ## Auto-fix

  Converts single-line `@doc`/`@moduledoc`/`@typedoc` strings containing
  `\\n` escapes into heredoc format. The fixer preserves indentation and
  strips unnecessary trailing `\\n` (since heredocs naturally end with a
  newline). Strings containing `\\\"\\\"\\\"` are left unchanged.
  """

  use Credence.Rule
  alias Credence.Issue

  @doc_attrs [:doc, :moduledoc, :typedoc]

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:@, meta, [{attr, _, [value]}]} = node, acc
        when attr in @doc_attrs and is_binary(value) ->
          if multi_line_in_single_string?(value) do
            {node, [build_issue(meta, attr) | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix(source, _opts) do
    line_fixed = fix_by_lines(source)

    if line_fixed != source do
      line_fixed
    else
      result = fix_by_ast(source)
      result
    end
  end

  # The string value (in AST) has at least one internal \n, meaning it
  # contains multi-line content. We require at least one \n that is not
  # merely trailing — i.e., the content before the trailing newlines
  # contains a newline.
  defp multi_line_in_single_string?(value) do
    trimmed = String.trim_trailing(value, "\n")
    String.contains?(trimmed, "\n")
  end

  # ══════════════════════════════════════════════════════════════════
  # Path A: Line-level fix (works on fresh source with \n escapes)
  # ══════════════════════════════════════════════════════════════════

  defp fix_by_lines(source) do
    source
    |> String.split("\n")
    |> fix_lines([])
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  defp fix_lines([], acc), do: acc

  defp fix_lines([line | rest], acc) do
    case try_extract_doc_string(line) do
      {:ok, attr, indent, content_raw} ->
        if safe_to_convert?(content_raw) do
          heredoc_lines = build_heredoc(attr, indent, content_raw)
          fix_lines(rest, Enum.reverse(heredoc_lines) ++ acc)
        else
          fix_lines(rest, [line | acc])
        end

      :skip ->
        fix_lines(rest, [line | acc])
    end
  end

  defp try_extract_doc_string(line) do
    case Regex.run(
           ~r/^(\s*)@(doc|moduledoc|typedoc)\s+"(.*)"(\s*)$/,
           line
         ) do
      [_full, indent, attr, content, _trailing] ->
        if has_internal_escaped_newlines?(content) do
          {:ok, attr, indent, content}
        else
          :skip
        end

      _ ->
        :skip
    end
  end

  defp has_internal_escaped_newlines?(content) do
    stripped = Regex.replace(~r/(\\n)+$/, content, "")
    String.contains?(stripped, "\\n")
  end

  defp safe_to_convert?(content_raw) do
    not String.contains?(content_raw, ~S("""))
  end

  defp build_heredoc(attr, indent, content_raw) do
    content =
      content_raw
      |> String.replace("\\\\", "\x00BACKSLASH\x00")
      |> String.replace("\\n", "\n")
      |> String.replace("\\\"", "\"")
      |> String.replace("\\t", "\t")
      |> String.replace("\x00BACKSLASH\x00", "\\")

    content = String.trim_trailing(content, "\n")

    doc_lines =
      content
      |> String.split("\n")
      |> Enum.map(fn doc_line ->
        if doc_line == "", do: "", else: "#{indent}#{doc_line}"
      end)

    opening = "#{indent}@#{attr} \"\"\""
    closing = "#{indent}\"\"\""

    [opening | doc_lines] ++ [closing]
  end

  # ══════════════════════════════════════════════════════════════════
  # Path B: AST-based fix (works after Sourceror has unescaped \n)
  # ══════════════════════════════════════════════════════════════════

  defp fix_by_ast(source) do
    ast = Sourceror.parse_string!(source)

    if has_fixable_multi_line_doc?(ast) do
      fixed_ast = Macro.postwalk(ast, &fix_doc_node/1)
      result = Sourceror.to_string(fixed_ast)
      result = fix_heredoc_closings(result)

      if String.ends_with?(source, "\n") and not String.ends_with?(result, "\n") do
        result <> "\n"
      else
        result
      end
    else
      source
    end
  end

  defp fix_doc_node({:@, meta, [{attr, attr_meta, [{:__block__, str_meta, [value]}]}]} = node)
       when attr in @doc_attrs and is_binary(value) do
    cond do
      raw_multi_line?(value) ->
        content = unescape_value(value)
        content = String.trim_trailing(content, "\n")
        new_str_meta = Keyword.put(str_meta, :delimiter, ~s("""))
        {:@, meta, [{attr, attr_meta, [{:__block__, new_str_meta, [content]}]}]}

      real_multi_line?(value) ->
        content = String.trim_trailing(value, "\n")
        new_str_meta = Keyword.put(str_meta, :delimiter, ~s("""))
        {:@, meta, [{attr, attr_meta, [{:__block__, new_str_meta, [content]}]}]}

      true ->
        node
    end
  end

  defp fix_doc_node(node), do: node

  defp has_fixable_multi_line_doc?(ast) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        {:@, _, [{attr, _, [{:__block__, _, [value]}]}]} = node, acc
        when attr in @doc_attrs and is_binary(value) ->
          {node, acc or raw_multi_line?(value) or real_multi_line?(value)}

        node, acc ->
          {node, acc}
      end)

    found
  end

  # Raw form: has internal \\n (backslash + n) beyond just trailing
  defp raw_multi_line?(value) do
    trimmed = String.trim_trailing(value, "\\n")
    String.contains?(trimmed, "\\n")
  end

  # Resolved form: has internal \n (real newline) beyond just trailing
  defp real_multi_line?(value) do
    trimmed = String.trim_trailing(value, "\n")
    String.contains?(trimmed, "\n")
  end

  defp unescape_value(value) do
    value
    |> String.replace("\\\\", "\x00BACKSLASH\x00")
    |> String.replace("\\n", "\n")
    |> String.replace("\\t", "\t")
    |> String.replace("\\\"", "\"")
    |> String.replace("\x00BACKSLASH\x00", "\\")
  end

  # ── Post-process: fix Sourceror's malformed heredoc closing ─────
  #
  # Sourceror puts the closing """ on the same line as the last content:
  #     Line two."""
  # We need it on its own line:
  #     Line two.
  #     """

  defp fix_heredoc_closings(source) do
    source
    |> String.split("\n")
    |> Enum.flat_map(fn line ->
      trimmed = String.trim_trailing(line)

      if needs_heredoc_split?(trimmed) do
        before = String.slice(trimmed, 0, String.length(trimmed) - 3)
        indent = leading_whitespace(line)
        [before, indent <> ~s(""")]
      else
        [line]
      end
    end)
    |> Enum.join("\n")
  end

  # A line needs splitting if it ends with """ AND has content before it,
  # but is NOT an opening @attr """ or a standalone """.
  defp needs_heredoc_split?(trimmed) do
    String.ends_with?(trimmed, ~s(""")) and
      String.length(trimmed) > 3 and
      not Regex.match?(~r/^\s*@(doc|moduledoc|typedoc)\s+"""$/, trimmed) and
      not Regex.match?(~r/^\s*"""$/, trimmed)
  end

  defp leading_whitespace(line) do
    case Regex.run(~r/^(\s*)/, line) do
      [_, ws] -> ws
      _ -> ""
    end
  end

  defp build_issue(meta, attr) do
    %Issue{
      rule: :prefer_heredoc_for_multi_line_doc,
      message: """
      `@#{attr}` contains multi-line content using `\\n` escape sequences. \
      Use heredoc (`\"\"\"`) syntax instead for readability.
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
