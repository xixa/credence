defmodule Credence.Rule.NoEagerWithIndexInReduce do
  @moduledoc """
  Performance rule: Detects `Enum.with_index/1` passed directly as the
  enumerable argument to `Enum.reduce/3` (or piped into it).

  `Enum.with_index/1` is eager — it traverses the entire list and allocates
  a new list of `{value, index}` tuples before `Enum.reduce` begins. This
  doubles memory consumption for large lists.

  ## Bad

      Enum.reduce(Enum.with_index(list), acc, fn {val, idx}, acc -> ... end)

      list |> Enum.with_index() |> Enum.reduce(acc, fn ...)

  ## Good

      # Option 1: Use Stream.with_index for lazy evaluation
      list |> Stream.with_index() |> Enum.reduce(acc, fn {val, idx}, acc -> ... end)

      # Option 2: Track the index in the accumulator
      Enum.reduce(list, {0, acc}, fn val, {idx, acc} -> {idx + 1, ...} end)
  """
  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Direct: Enum.reduce(Enum.with_index(list), acc, fn ...)
        {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, meta,
         [
           {{:., _, [{:__aliases__, _, [:Enum]}, :with_index]}, _, _} | _rest
         ]} = node,
        issues ->
          {node, [build_issue(meta) | issues]}

        # Piped: list |> Enum.with_index() |> Enum.reduce(acc, fn ...)
        {:|>, meta,
         [
           left,
           {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, _}
         ]} = node,
        issues ->
          if with_index_on_right?(left) do
            {node, [build_issue(meta) | issues]}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  # Check if the rightmost call in a pipe chain is Enum.with_index
  defp with_index_on_right?({:|>, _, [_, right]}), do: with_index_call?(right)
  defp with_index_on_right?(node), do: with_index_call?(node)

  defp with_index_call?({{:., _, [{:__aliases__, _, [:Enum]}, :with_index]}, _, _}), do: true
  defp with_index_call?(_), do: false

  defp build_issue(meta) do
    %Issue{
      rule: :no_eager_with_index_in_reduce,
      severity: :warning,
      message:
        "`Enum.with_index/1` eagerly allocates a new list of tuples before `Enum.reduce/3` begins. " <>
          "Use `Stream.with_index/1` for lazy evaluation, or track the index in the accumulator.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
