defmodule Credence.Pattern.NoRedundantListTraversal do
  @moduledoc """
  Detects multiple traversals of the same list that could be merged into
  a single pass.

  LLMs routinely produce code like `count = length(numbers)` followed by
  `sum = Enum.sum(numbers)` — two O(n) passes where one `Enum.reduce/3`
  would do. Similarly, separate `Enum.min/1` and `Enum.max/1` calls can be
  replaced by the built-in `Enum.min_max/1`.

  Only flags calls that are:
  - bare assignments (`var = func(list)`) in the same block
  - arity-1 calls on a plain variable (not an expression or field access)
  - on the same variable with no rebinding between them

  ## Detected functions

      length/1          →  :count
      Enum.count/1      →  :count
      Enum.sum/1        →  :sum
      Enum.min/1        →  :min
      Enum.max/1        →  :max

  ## Auto-fixable pairs

      length/Enum.count + Enum.sum  →  single Enum.reduce/3
      Enum.min + Enum.max           →  Enum.min_max/1

  Other combinations are flagged but not auto-fixed.

  ## Bad

      count = length(numbers)
      sum = Enum.sum(numbers)

  ## Good

      {count, sum} = Enum.reduce(numbers, {0, 0}, fn x, {c, s} -> {c + 1, s + x} end)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  # Pairs we know how to auto-fix
  @fixable_pairs [
    MapSet.new([:count, :sum]),
    MapSet.new([:min, :max])
  ]

  # Enum functions we track (arity 1 only — arity 2 has different semantics)
  @tracked_enum_funcs [:count, :sum, :min, :max]

  @impl true
  def fixable?, do: true

  # ── Check ─────────────────────────────────────────────────────────

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:__block__, _meta, statements} = node, acc when is_list(statements) ->
          {node, build_issues(statements) ++ acc}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  # ── Fix ───────────────────────────────────────────────────────────

  @impl true
  def fix(source, _opts) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        groups = collect_all_fixable_groups(ast)

        if groups == [] do
          source
        else
          ast
          |> Macro.postwalk(&maybe_rewrite_block/1)
          |> Sourceror.to_string()
        end

      {:error, _} ->
        source
    end
  end

  # ── Shared: scanning and grouping ─────────────────────────────────

  # Scans a block's direct children for bare traversal assignments.
  # Returns a list of entry maps, each: %{result_var, list_var, type, label, index, line}
  defp scan_statements(statements) do
    statements
    |> Enum.with_index()
    |> Enum.flat_map(fn {stmt, idx} ->
      case scan_statement(stmt, idx) do
        {:ok, entry} -> [entry]
        :skip -> []
      end
    end)
  end

  # Matches: result_var = traversal_func(list_var)
  # Only bare assignments where the RHS is exactly the call (not nested).
  defp scan_statement({:=, meta, [lhs, rhs]}, index) do
    with {:ok, result_var} <- plain_variable_name(lhs),
         {:ok, list_var, type, label} <- identify_call(rhs) do
      {:ok,
       %{
         result_var: result_var,
         list_var: list_var,
         type: type,
         label: label,
         index: index,
         line: Keyword.get(meta, :line)
       }}
    else
      _ -> :skip
    end
  end

  defp scan_statement(_, _), do: :skip

  # Groups entries by list variable and returns only valid groups:
  # 2+ distinct aggregate types, no rebinding between first and last.
  defp find_valid_groups(statements) do
    scan_statements(statements)
    |> Enum.group_by(& &1.list_var)
    |> Enum.flat_map(fn {list_var, entries} ->
      distinct_types = entries |> Enum.map(& &1.type) |> Enum.uniq()

      if length(distinct_types) >= 2 do
        sorted = Enum.sort_by(entries, & &1.index)
        first_idx = hd(sorted).index
        last_idx = List.last(sorted).index

        if not variable_rebound?(statements, list_var, first_idx, last_idx) do
          [%{list_var: list_var, entries: sorted}]
        else
          []
        end
      else
        []
      end
    end)
  end

  # ── Call identification ───────────────────────────────────────────

  # length(var) — Kernel BIF
  defp identify_call({:length, _, [arg]}) do
    with {:ok, var_name} <- plain_variable_name(arg) do
      {:ok, var_name, :count, "length/1"}
    end
  end

  # Enum.func(var) — tracked functions, arity 1 only
  defp identify_call({{:., _, [module, func_ref]}, _, [arg]}) do
    func = unwrap_atom(func_ref)

    if enum_module?(module) and func in @tracked_enum_funcs do
      with {:ok, var_name} <- plain_variable_name(arg) do
        {:ok, var_name, func, "Enum.#{func}/1"}
      end
    else
      :skip
    end
  end

  defp identify_call(_), do: :skip

  # ── Variable helpers ──────────────────────────────────────────────

  # Returns {:ok, name} for a plain variable, :skip for anything else
  # (underscore, pattern, expression, field access, etc.)
  defp plain_variable_name({name, _, context})
       when is_atom(name) and is_atom(context) and name != :_ do
    {:ok, name}
  end

  defp plain_variable_name(_), do: :skip

  # Sourceror wraps bare atoms in {:__block__, meta, [atom]}.
  defp unwrap_atom({:__block__, _, [atom]}) when is_atom(atom), do: atom
  defp unwrap_atom(atom) when is_atom(atom), do: atom
  defp unwrap_atom(_), do: nil

  defp enum_module?({:__aliases__, _, [:Enum]}), do: true
  defp enum_module?({:__aliases__, _, [{:__block__, _, [:Enum]}]}), do: true
  defp enum_module?(_), do: false

  # ── Rebinding detection ──────────────────────────────────────────

  # Returns true if `var_name` is bound on the LHS of any assignment
  # between statement indices from_idx (exclusive) and to_idx (exclusive).
  defp variable_rebound?(statements, var_name, from_idx, to_idx) do
    statements
    |> Enum.with_index()
    |> Enum.any?(fn {stmt, idx} ->
      idx > from_idx and idx < to_idx and rebinds_variable?(stmt, var_name)
    end)
  end

  defp rebinds_variable?({:=, _, [lhs, _rhs]}, var_name) do
    ast_binds_name?(lhs, var_name)
  end

  defp rebinds_variable?(_, _), do: false

  # Recursively checks if an AST node (the LHS of =) binds a variable name.
  # Handles plain variables, list patterns, tuple patterns, map patterns, etc.
  defp ast_binds_name?({name, _, context}, target)
       when is_atom(name) and is_atom(context),
       do: name == target

  defp ast_binds_name?({_, _, args}, target) when is_list(args),
    do: Enum.any?(args, &ast_binds_name?(&1, target))

  defp ast_binds_name?(list, target) when is_list(list),
    do: Enum.any?(list, &ast_binds_name?(&1, target))

  defp ast_binds_name?(_, _), do: false

  # ── Check: issue generation ──────────────────────────────────────

  defp build_issues(statements) do
    find_valid_groups(statements)
    |> Enum.map(fn %{list_var: list_var, entries: entries} ->
      labels = entries |> Enum.map(& &1.label) |> Enum.join(" and ")

      %Issue{
        rule: :no_redundant_list_traversal,
        message:
          "#{labels} both traverse `#{list_var}` — " <>
            "consider merging into a single pass.",
        meta: %{line: hd(entries).line}
      }
    end)
  end

  # ── Fix: block rewriting ─────────────────────────────────────────

  # Pre-scan: collects all fixable groups across the entire AST.
  # Used to short-circuit Sourceror.to_string() when nothing to fix.
  defp collect_all_fixable_groups(ast) do
    {_ast, groups} =
      Macro.prewalk(ast, [], fn
        {:__block__, _meta, statements} = node, acc when is_list(statements) ->
          fixable = find_fixable_groups(statements)
          {node, fixable ++ acc}

        node, acc ->
          {node, acc}
      end)

    groups
  end

  defp find_fixable_groups(statements) do
    find_valid_groups(statements)
    |> Enum.filter(fn group ->
      types = group.entries |> Enum.map(& &1.type) |> MapSet.new()

      length(group.entries) == 2 and
        Enum.any?(@fixable_pairs, &MapSet.equal?(&1, types))
    end)
  end

  # Postwalk callback: rewrites a __block__ if it contains fixable groups.
  defp maybe_rewrite_block({:__block__, meta, statements} = node)
       when is_list(statements) do
    fixable = find_fixable_groups(statements)

    if fixable == [] do
      node
    else
      {:__block__, meta, apply_fixes(statements, fixable)}
    end
  end

  defp maybe_rewrite_block(node), do: node

  # Applies all fixes to a statement list: replaces the first call with
  # the merged version and removes the second call.
  defp apply_fixes(statements, groups) do
    {replacements, removals} =
      Enum.reduce(groups, {%{}, MapSet.new()}, fn group, {repls, rems} ->
        [first, second] = group.entries
        replacement = build_replacement(group.list_var, first, second)
        {Map.put(repls, first.index, replacement), MapSet.put(rems, second.index)}
      end)

    statements
    |> Enum.with_index()
    |> Enum.flat_map(fn {stmt, idx} ->
      cond do
        Map.has_key?(replacements, idx) -> [replacements[idx]]
        idx in removals -> []
        true -> [stmt]
      end
    end)
  end

  # ── Fix: replacement AST builders ────────────────────────────────

  defp build_replacement(list_var, first, second) do
    types = MapSet.new([first.type, second.type])

    cond do
      MapSet.equal?(types, MapSet.new([:min, :max])) ->
        build_min_max_ast(list_var, first, second)

      MapSet.equal?(types, MapSet.new([:count, :sum])) ->
        build_reduce_ast(list_var, first, second)
    end
  end

  # {min_var, max_var} = Enum.min_max(list_var)
  # Always min first, max second — matching Enum.min_max/1 return order.
  defp build_min_max_ast(list_var, entry_a, entry_b) do
    {min_entry, max_entry} =
      if entry_a.type == :min, do: {entry_a, entry_b}, else: {entry_b, entry_a}

    Code.string_to_quoted!(
      "{#{min_entry.result_var}, #{max_entry.result_var}} = Enum.min_max(#{list_var})"
    )
  end

  # {var_a, var_b} = Enum.reduce(list_var, {init_a, init_b}, fn x, {a, b} -> {upd_a, upd_b} end)
  # Tuple position follows source order (first-appearing entry first).
  defp build_reduce_ast(list_var, first, second) do
    entries = Enum.sort_by([first, second], & &1.index)

    parts =
      Enum.map(entries, fn entry ->
        case entry.type do
          :count -> %{var: entry.result_var, init: "0", acc: "c", update: "c + 1"}
          :sum -> %{var: entry.result_var, init: "0", acc: "s", update: "s + x"}
        end
      end)

    lhs = parts |> Enum.map(&"#{&1.var}") |> Enum.join(", ")
    inits = parts |> Enum.map(& &1.init) |> Enum.join(", ")
    accs = parts |> Enum.map(& &1.acc) |> Enum.join(", ")
    updates = parts |> Enum.map(& &1.update) |> Enum.join(", ")

    Code.string_to_quoted!(
      "{#{lhs}} = Enum.reduce(#{list_var}, {#{inits}}, fn x, {#{accs}} -> {#{updates}} end)"
    )
  end
end
