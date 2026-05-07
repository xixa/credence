Two **Credence bugs** and a few pattern observations from this log:

## Critical: Credence bugs breaking code

**1. `NoManualEnumUniq` leaves orphaned `elem(0)` (idx=10, unique_char_in_order)**

LLM wrote correct code:
```elixir
String.graphemes(input_string)
|> Enum.reduce({[], MapSet.new()}, fn char, {acc_list, acc_set} -> ... end)
|> elem(0)
|> Enum.reverse()
```

Credence replaced the reduce with `Enum.uniq()` but left the downstream `elem(0)` and `Enum.reverse()`:
```elixir
String.graphemes(input_string) |> Enum.uniq() |> elem(0) |> Enum.reverse()
```

`Enum.uniq()` returns a list, not a tuple — `elem(0)` crashes. This burned all 5 retries because Credence kept re-applying the same broken fix. The rule needs to strip the entire `|> elem(0) |> Enum.reverse()` tail when it replaces the reduce-based uniqueness pattern.

**2. `NoEagerWithIndexInReduce` strips `String.graphemes` (idx=9, length_of_longest_substring)**

LLM wrote:
```elixir
graphemes = String.graphemes(input_string)
Enum.reduce(Enum.with_index(graphemes), ...)
```

Credence changed it to:
```elixir
graphemes = input_string
Enum.reduce(Stream.with_index(graphemes), ...)
```

It correctly swapped `Enum.with_index` → `Stream.with_index`, but also stripped `String.graphemes()` from the assignment. Now `Stream.with_index` receives a raw string (not enumerable) → crash. Again burned all 5 retries with the same error.

## Observations for potential improvements

**`-Infinity`/`Infinity` (idx=5, binary_search_tree)** — LLM translates Python's `float('-inf')` as `-Infinity`. Elixir doesn't have this. A Semantic or Syntax rule could detect `Infinity` / `-Infinity` usage. The fix is context-dependent (use `nil` with guard, or `:infinity` atom) so maybe detection-only.

**Custom functions in guards (idx=5)** — LLM called `valid_min?(val, min_val)` inside a `when` guard. Only Kernel macros work in guards. Hard to auto-fix but worth detecting — the error message from the compiler is confusing and the LLM couldn't fix it in 5 attempts.

**Underscored variables used in code (idx=4, pascal_row)** — `_target_index` used in a function call. Your Semantic phase should now catch this with `--warnings-as-errors`, but only if the validator runs Credence first (the new pipeline order).

## Priority

The two bugs are critical — they're actively causing failures by **making working code worse**. Fix `NoManualEnumUniq` and `NoEagerWithIndexInReduce` before the next production run. Do you want me to look at those rule implementations?