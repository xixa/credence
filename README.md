# Credence

A semantic linter for LLM-generated Elixir code.

Elixir's compiler checks syntax. Credo checks style. Credence checks *semantics* — it mainly catches patterns that compile and pass tests but are non-idiomatic, inefficient, or ported from Python/JavaScript conventions that don't belong in Elixir.

## Three-phase pipeline

Credence runs code through three escalating phases:

```
Credence.Syntax    → can the parser read it?     (string-level fixes)
Credence.Semantic  → does the compiler accept it? (compiler warning fixes)
Credence.Pattern   → is it idiomatic Elixir?      (80+ AST-level rules)
```

**Syntax** repairs code that won't parse — e.g. `n * (n + 1) div 2` (Python's `//` translated as infix) becomes `div(n * (n + 1), 2)`.

**Semantic** captures compiler warnings via `Code.with_diagnostics/1` and fixes them — unused variables get `_` prefixed, undefined function calls get corrected(if possible).

**Pattern** detects and auto-fixes 80+ anti-patterns using AST analysis — `Enum.sort |> Enum.reverse` becomes `Enum.sort(:desc)`, manual frequency counting becomes `Enum.frequencies/1`, `acc ++ [x]` becomes `[x | acc]`.

Each phase has its own `Rule` behaviour. Rules are discovered automatically and run in priority order.

## Installation

```elixir
def deps do
[
  {:credence, "~> 0.4.3", only: [:dev, :test], runtime: false}
]
end
```

## Usage

**Analyze** — detect issues without modifying code:

```elixir
%{valid: true, issues: []} = Credence.analyze(code)
```

**Fix** — auto-fix what's fixable, report the rest:

```elixir
%{code: fixed, issues: remaining} = Credence.fix(code)
```

### Example

```elixir
code = ~S"""
defmodule StudentAnalyzer do
  @doc "Analyzes scores.\nReturns statistics.\n"

  def analyze(scores) do
    if length(scores) == 0 do
      %{error: "no scores"}
    else
      total = Enum.map(scores, fn s -> s end) |> Enum.sum()
      avg = total / Enum.count(scores) * 1.0
      freq = Enum.reduce(scores, %{}, fn s, acc ->
        Map.update(acc, s, 1, &(&1 + 1))
      end)
      ranked = Enum.sort(scores) |> Enum.reverse()
      top_3 = Enum.sort(scores) |> Enum.take(-3)
      unique = scores |> Enum.uniq_by(fn s -> s end)
      csv = Enum.map(unique, fn s -> Integer.to_string(s) end) |> Enum.join(",")

      %{average: avg, frequencies: freq, top_3: top_3,
        csv: csv, passing: is_passing(avg)}
    end
  end

  def is_passing(avg), do: avg |> Kernel.>=(60.0)
end
"""

%{code: fixed, issues: remaining} = Credence.fix(code)
```

You can run a subset of rules:

```elixir
Credence.analyze(code, rules: [
  Credence.Pattern.NoListAppendInRecursion,
  Credence.Pattern.NoSortForTopK,
  Credence.Pattern.NoListFold
])
```

## Writing custom rules

Each phase has its own `Rule` behaviour:

### Pattern rules (AST-level)

```elixir
defmodule Credence.Pattern.MyRule do
  use Credence.Pattern.Rule

  @impl true
  def priority, do: 500  # default; lower runs first

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        # pattern match on node
        {node, issues}
      end)
    Enum.reverse(issues)
  end

  @impl true
  def fixable?, do: true

  @impl true
  def fix(source, _opts) do
    # return modified source string
    source
  end
end
```

### Syntax rules (string-level, for unparseable code)

```elixir
defmodule Credence.Syntax.MyFix do
  use Credence.Syntax.Rule

  @impl true
  def analyze(source), do: []  # return [%Issue{}] for detected problems

  @impl true
  def fix(source), do: source  # return repaired source string
end
```

### Semantic rules (compiler warning fixes)

```elixir
defmodule Credence.Semantic.MyFix do
  use Credence.Semantic.Rule

  @impl true
  def match?(%{severity: :warning, message: msg}), do: false

  @impl true
  def to_issue(diagnostic), do: %Credence.Issue{rule: :my_fix, message: diagnostic.message, meta: %{}}

  @impl true
  def fix(source, diagnostic), do: source
end
```

## License

MIT