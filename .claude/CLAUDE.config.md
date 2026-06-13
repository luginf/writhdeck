## State persistence (`.writhdeck.json`)

Hand-rolled JSON (no external parser):
```json
{
  "cursors":   {"path": [cy, cx]},
  "favorites": ["path"],
  "recent":    ["path"],
  "daily":     ["path\tYYYY-MM-DD\tN\tYYYY-MM-DD\tN..."]
}
```
- One `daily` entry per file; all its dates packed as `\t`-separated pairs after the path.
- `\t` is written as the two-char JSON escape sequence `\t`, not a literal tab (which is invalid JSON).
- `state-parse-array` uses `regexp -indices` to find quoted strings in raw JSON, extracts them using `string range`, then `state-load` calls `string map [list {\t} "\t"]` before `split`. This correctly handles escape sequences without attempting to match unescaped content. Note: `{\t}` in Tcl braces is 2 chars (backslash + t), not 1 — do not write `{\\t}` (3 chars) by mistake.
- `state-load` / `state-save` rewrite the whole file each time.
- `state-load` has a guard (`$::state_cache_valid`) — call `set ::state_cache_valid 0` to force reload.
- Daily stats use a high-water mark: word deletions never reduce the count.

## INI parser

**Comment characters** — both `#` and `%` are accepted as comment characters:
- Line comments: lines starting with `#` or `%` are skipped entirely.
- Inline comments: `regsub {\s+[#%].*$}` strips everything after a `#` or `%` preceded by whitespace. Applied after `string trim`, so values starting with `#` (hex colors like `#1a1a1a`) are preserved.

**`ini-save` format** — comments use `%`; section titles use WrithDeck heading syntax `= title =` so they appear in the F11 TOC when the INI is opened in the editor. The `= title =` lines are silently ignored by the parser (no match for `[section]` or `key = value` patterns). Sections: `editor`, `behaviour`, `timer` (subsection), `misc`, `tui_colors`, `keys`, `profiles`, `schemes` — plus one heading per named profile/scheme block.

**Boolean values** — `ini-save` writes `yes`/`no` for all 20 boolean settings using `[expr {$::cfg_xxx ? "yes" : "no"}]`. All forms are accepted on load via `string is true $v`: `yes`, `no`, `1`, `0`, `true`, `false`, `on`, `off`.

**Browser filter (`[behaviour]`)** — `browser_filter` (default `*.txt *.t2t *.md *.ini`, space-separated glob patterns; empty = show all) and `browser_show_all` (boolean, default `no`, bypasses `browser_filter` entirely) control which files `list-docs` shows. Both are written with explanatory `%` comments above their values.

**Repetition detection (`[behaviour]`)** — `repetition_scope` (default `100`, word distance checked in each direction), `repetition_min_len` (default `4`, minimum word length for hidden-substring checks), `repetition_hidden` (boolean, default `no`, enables the hidden-substring tier). See `find-repetitions` in `src/analysis.tcl` and the Repetitions dialog (`repetitions-dialog` GUI / `tui-repetitions-dialog` TUI).

**`key_toc_pinned` (`[keys]`)** — default `Control-Shift-F11`; toggles the pinned TOC side panel (`toc-panel-toggle`) independently of `key_toc` (F11).
