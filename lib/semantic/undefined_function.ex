defmodule Credence.Semantic.UndefinedFunction do
  @moduledoc """
  Fixes compiler warnings about undefined functions with known replacements.

  LLMs sometimes use functions that don't exist in the expected module.
  This rule maintains a mapping of known corrections.

  ## Example

      # Warning: Enum.last/1 is undefined or private
      list |> Enum.last()

      # Fixed:
      list |> List.last()
  """
  use Credence.Semantic.Rule
  alias Credence.Issue

  # Map of {module, function, arity} → {correct_module, correct_function}
  @replacements %{
    {"Enum", "last", 1} => {"List", "last"},
    {"Enum", "last", 0} => {"List", "last"},
    {"List", "reverse", 1} => {"Enum", "reverse"}
  }

  @impl true
  def match?(%{severity: :warning, message: msg}) do
    String.contains?(msg, "is undefined or private") and
      parse_function_ref(msg) != nil and
      Map.has_key?(@replacements, parse_function_ref(msg))
  end

  def match?(_), do: false

  @impl true
  def to_issue(%{message: msg, position: position}) do
    %Issue{
      rule: :undefined_function,
      message: msg,
      meta: %{line: extract_line(position)}
    }
  end

  @impl true
  def fix(source, %{message: msg, position: position}) do
    line_no = extract_line(position)

    case parse_function_ref(msg) do
      {mod, fun, _arity} = key ->
        case Map.get(@replacements, key) do
          {new_mod, new_fun} ->
            replace_on_line(source, line_no, "#{mod}.#{fun}", "#{new_mod}.#{new_fun}")

          nil ->
            source
        end

      nil ->
        source
    end
  end

  defp extract_line({line, _col}) when is_integer(line), do: line
  defp extract_line(line) when is_integer(line), do: line
  defp extract_line(_), do: nil

  defp parse_function_ref(msg) do
    case Regex.run(~r/(\w+)\.(\w+)\/(\d+) is undefined or private/, msg) do
      [_, mod, fun, arity] -> {mod, fun, String.to_integer(arity)}
      _ -> nil
    end
  end

  defp replace_on_line(source, line_no, old, new) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map(fn
      {line, ^line_no} -> String.replace(line, old, new, global: false)
      {line, _} -> line
    end)
    |> Enum.join("\n")
  end
end
