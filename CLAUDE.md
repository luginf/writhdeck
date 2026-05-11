# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Running the program

```sh
wish writhdeck.tcl                     # GUI (Tk required)
wish writhdeck.tcl file.txt            # GUI, open file directly
tclsh writhdeck.tcl --no-gui           # TUI
tclsh writhdeck.tcl --no-gui file.txt  # TUI, open file directly
./writhdeck.tcl                        # polyglot sh/Tcl bootstrap
```

No build step. The entire application is `writhdeck.tcl` (single file, ~4700 lines). There are no tests, no dependencies beyond Tcl/Tk 8.6+.

## Version

Format `vYYYYMMDD` (e.g. `v20260508`), defined near line 32:
```tcl
set ::version "v20260509"
```
Update it on every functional change.

## Code structure

The file has two major runtime branches controlled by `$::no_gui`:

| Zone | Lines (approx.) | Content |
|---|---|---|
| Bootstrap | 1–125 | Polyglot sh/Tcl, args, Tk detection, `::HOME_DIR`, `tilde-expand` |
| State persistence | 126–272 | `.writhdeck.json`, cursors, favorites, recents, daily stats |
| INI / config | 273–835 | `ini-load`, `ini-save`, profiles, schemes, keys, i18n |
| Shared utils | 836–1345 | `list-docs`, `br-dirs`, `do-backup`, `build-extra-entries`, inline parsers |
| **GUI block** (`if {!$::no_gui}`) | 1346–3040 | Browser frame, editor frame, dialogs, TOC, split view, typewriter |
| TUI core | 3042–3527 | `tui-init`, `tui-getch`, `tui-bar`, word-wrap, layout |
| TUI helpers | 3528–3668 | Prompt, clipboard, selection |
| TUI browser | 3669–3976 | `tui-browser` |
| TUI editor | 3977–4684 | `tui-toc`, `tui-editor`, `tui-main` |
| Entry point | 4685–end | Dispatch GUI / TUI |

The GUI block is a single `if {!$::no_gui} { ... } ;# end if {!$::no_gui}` spanning lines 1346–3040.

## Key rules

**Absolute paths everywhere** — all paths stored in `.writhdeck.json` must be absolute. Call `file normalize $path` at the top of any proc that reads or writes a path (`cursor-get/put`, `recent-push/remove/rename`, `toggle-favorite`, `daily-open`, `daily-clear`).

**`tilde-expand` before `file normalize`** — Tcl 9 no longer expands `~` in `file normalize`. Always call `tilde-expand $path` first when the path comes from user input (config file, prompts). The proc is defined after `::HOME_DIR` near line 110.

**Procs shared between GUI and TUI must be defined outside the `if {!$::no_gui}` block.** Currently outside: all `state-*`, `daily-*`, `recent-*`, `build-extra-entries`, `toggle-favorite`, `do-backup`.

**i18n — always add both languages.** Any new string key must appear in both `en {}` and `fr {}` blocks of `::i18n`. Use `proc t {key args}` to retrieve.

**`chan configure` not `fconfigure`.** The codebase uses `chan configure` throughout (Tcl 8.5+ compatible, not deprecated in Tcl 9).

**No Unicode symbols or em-dashes in user-visible strings.** Use ASCII equivalents: `->` not `→`, `-` not `—`, `[+]`/`[-]` not `★`/`☆`, `|` not `·`, etc. French accented characters (é, à, è, ê, É…) are the only intentional non-ASCII. This applies to i18n strings, help text, status bar, and all TUI output.

## Adding a new browser key

6 places to update:
1. `br_help_gui` i18n (EN + FR)
2. `br_help_tui` i18n (EN + FR)
3. `bind .br.mid.lst <x>` in the GUI block
4. `switch -- $key` in `tui-browser`
5. BROWSER section of `help-dialog`
6. Browser shortcut tables in `README.md` and `README.fr.md`

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
- `state-parse-array` uses regex `(?:[^"\\]|\\.)*` to handle escape sequences; `state-load` then calls `string map [list {\t} "\t"]` before `split`. Note: `{\t}` in Tcl braces is 2 chars (backslash + t), not 1 — do not write `{\\t}` (3 chars) by mistake.
- `state-load` / `state-save` rewrite the whole file each time.
- `state-load` has a guard (`$::state_cache_valid`) — call `set ::state_cache_valid 0` to force reload.
- Daily stats use a high-water mark: word deletions never reduce the count.

## Browser entry types (`::br_entries`)

| Type | Notes |
|---|---|
| `header` | Section separator. `dir=""` → label = `name` field (Favorites, Recents). `dir≠""` → abbreviated path |
| `file` | File in a watched folder |
| `favorite` | Pinned file (any folder) |
| `recent` | Recent file outside watched folders (deduplicated) |

Section order: `DOCS_DIR_DEFAULT` → `DOCS_DIR` (if custom) → Favorites → Recents.
`br-active-dir` walks up to the nearest `header`; if `dir=""` returns `DOCS_DIR_DEFAULT`.

## GUI-specific patterns

**Help dialog close** — use `after idle [list destroy $w]; break` on keyboard bindings inside the Text widget; plain `destroy` triggers `<<TkTextBackspace>>` on the already-destroyed widget.

**`quit-app`** — only prompts to save if `$::filename ne "" || $::scratchpad`.

**`open-file-dialog`** — uses `[file dirname $::filename]` as `initialdir` when a file is open, otherwise `DOCS_DIR_DEFAULT`.

## Known limitations

- No emoji support in GUI (Tk 8.6 color font limitation)
- TUI mode blocked on Windows (`stty` absent)
- No no-wrap mode and no tab mode (not planned)
- Split view GUI only (TUI adaptation not planned yet)
- `font_weight` not exposed in INI (removed, unreliable across fonts)

## Git & commits

**Never commit on behalf of the user.** Always let the user decide when and how to commit. Prepare changes but wait for explicit instruction before running `git commit`.

## SKILLS.md

`SKILLS.md` in the repo root is the developer reference in French. It contains detailed rules, patterns, and a list of ideas not yet implemented — consult it before adding features.
