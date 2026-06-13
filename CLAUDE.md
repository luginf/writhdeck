# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Running the program

```sh
wish writhdeck.tcl                     # GUI (Tk required)
wish writhdeck.tcl file.txt            # GUI, open file directly
tclsh writhdeck.tcl --tui              # TUI (--cli is an alias)
tclsh writhdeck.tcl --cli file.txt     # TUI, open file directly
./writhdeck.tcl --tui                  # polyglot sh/Tcl bootstrap, TUI mode
```

Build with `make` to generate `writhdeck.tcl` and `writhdeck-cli.tcl` from source modules in `src/`. Both generated files are executable and tracked in git. Dependencies: Tcl/Tk 8.5+ through 9.x (Tk only required for GUI mode).

Run tests to catch regressions:
```sh
make test              # Run all regression tests
make test-i18n        # Validate translations
make test-syntax      # Check Tcl syntax
make test-gui         # Test GUI build
make test-cli         # Test CLI build
```

Generate compact builds (comments, blank lines, and leading whitespace stripped):
```sh
make compact           # writhdeck-compact.tcl + writhdeck-cli-compact.tcl (~-20 to -25%)
make compact-cli       # writhdeck-cli-compact.tcl only
```

## Version

Format `vYYYYMMDD` (e.g. `v20260512`), defined near line 32:
```tcl
set ::version "v20260513"
```
Update it on every functional change.

## Generated file structure

After `make`, the generated `writhdeck.tcl` contains these sections (concatenated from source modules):

| Section        | Source module          | Content                                                                         |
| -------------- | ---------------------- | ------------------------------------------------------------------------------- |
| Bootstrap      | `src/boot.tcl`         | Polyglot sh/Tcl, args, Tk detection, `::HOME_DIR`, `tilde-expand`               |
| State          | `src/state.tcl`        | `.writhdeck.json` persistence, cursors, favorites, recents, daily stats         |
| Config         | `src/config.tcl`       | INI loading/saving, profiles, schemes, keys, i18n system, theme init            |
| Common         | `src/common.tcl`       | `list-docs`, `br-dirs`, `do-backup`, `build-extra-entries`, inline parsers      |
| **Analysis**   | `src/analysis.tcl`     | Structure outline, word occurrences, repetitions, spell-check — `get-word-occurrences`, `analyse-structure`, `find-repetitions`, `spell-check-document`, GUI+TUI dialogs |
| **GUI config** | `src/gui-config.tcl`   | `profile-config-dialog`, `config-tab-switch`, `profile-config-update-profile`   |
| **GUI**        | `src/gui.tcl`          | Wrapped in `if {!$::no_gui}` — browser, editor, dialogs, TOC, split view        |
| **TUI**        | `src/tui.tcl`          | Terminal UI — `tui-init`, `tui-browser`, `tui-editor`, `tui-main`, helpers      |
| Entry point    | `src/main.tcl`         | Dispatch: `if {$::no_gui}` → TUI, else → GUI                                   |

Both `src/gui-config.tcl` and `src/gui.tcl` are wrapped in `if {!$::no_gui} { ... }`. `src/gui-config.tcl` is optional — excluded with `make GUI_CONFIG=no` (~700 lines, hides `c` key in browser).

`src/analysis.tcl` contains only `proc` definitions (no top-level Tk-building code), so it is **not** wrapped in `if {!$::no_gui}` — safe to load in TUI-only builds. It is an optional all-or-nothing module: included by default in `writhdeck.tcl`/`writhdeck-cli.tcl` (`ANALYSIS_TOOLS=no` to exclude), excluded by default from `writhdeck-mini.tcl`/`writhdeck-jim.tcl` (`MINI_ANALYSIS_TOOLS=yes` / `JIM_ANALYSIS_TOOLS=yes` to include). When excluded, `gui.tcl`/`tui.tcl` guard every call site, binding, button, and help-bar entry with `if {[info procs <proc>] ne ""} { ... }`.

### Section headers

Generated files have readable section headers:
```tcl
# ===================================================================
# state.tcl
# ===================================================================
```
These markers help navigate the ~5000-line file during development.

## Key rules

**Absolute paths everywhere** — all paths stored in `.writhdeck.json` must be absolute. Call `file normalize $path` at the top of any proc that reads or writes a path (`cursor-get/put`, `recent-push/remove/rename`, `toggle-favorite`, `daily-open`, `daily-clear`).

**`tilde-expand` before `file normalize`** — Tcl 9 no longer expands `~` in `file normalize`. Always call `tilde-expand $path` first when the path comes from user input (config file, prompts). The proc is defined after `::HOME_DIR` near line 110.

**Procs shared between GUI and TUI must be defined outside the `if {!$::no_gui}` block.** Currently outside: all `state-*`, `daily-*`, `recent-*`, `build-extra-entries`, `toggle-favorite`, `do-backup`. Analysis helpers (`get-word-occurrences`, `analyse-structure`, `find-repetitions`, ...) live in `src/analysis.tcl`, which is entirely outside `if {!$::no_gui}` (proc-only file, see **Generated file structure** above).

**`get-word-occurrences {fpath}`** — returns a list of `{word count}` pairs sorted by count descending. Opens with `-encoding utf-8`, reads, and closes the file itself. Callers iterate with `foreach pair $word_data { lassign $pair word count }` — do not re-read the file.

**`do-backup {dir name}`** — copies to `$DOCS_DIR/backups/` with timestamp `%Y-%m-%dT%Hh%Mm%S` (includes seconds). Returns the full destination path `$dst`. Success message shows `[string map [list $::HOME_DIR ~] [file dirname $dst]]` (the backup folder path with ~ substitution).

**i18n — always add both languages.** Any new string key must appear in both `en {}` and `fr {}` blocks of `::i18n`. Use `proc t {key args}` to retrieve.

**`chan configure` not `fconfigure`.** The codebase uses `chan configure` throughout (Tcl 8.5+ compatible, not deprecated in Tcl 9).

**No Unicode symbols or em-dashes in user-visible strings.** Use ASCII equivalents: `->` not `→`, `-` not `—`, `[+]`/`[-]` not `★`/`☆`, ` | ` not `·`, etc. French accented characters (é, à, è, ê, É…) are the only intentional non-ASCII. This applies to i18n strings, help text, status bar, and all TUI output.

## Known limitations

- No emoji support in GUI (Tk 8.6 color font limitation)
- TUI mode blocked on Windows (`stty` absent)
- No no-wrap mode (not planned)
- Split view GUI only (TUI adaptation not planned yet)
- `font_weight` not exposed in INI (removed, unreliable across fonts)
- TUI split view : l'affichage du panneau droit peut être perturbé si le fichier contient des tabulations (les tabs sont expansés en 4 espaces dans le panneau gauche mais pas compensés dans le rendu droit)

## Git & commits

**Never commit on behalf of the user.** Always let the user decide when and how to commit. Prepare changes but wait for explicit instruction before running `git commit`.

## SKILLS.md

`SKILLS.md` in the repo root is the developer reference in French. It contains detailed rules, patterns, and a list of ideas not yet implemented — consult it before adding features.

## Android app (`../writhdeck-android/`)

Dépôt séparé, **pure Kotlin + Jetpack Compose** (pas de Tcl/JNI). Build : `./gradlew assembleDebug`. Référence complète dans `../writhdeck-android/CLAUDE.md`.

---

@.claude/CLAUDE.browser.md
@.claude/CLAUDE.editor.md
@.claude/CLAUDE.config.md
@.claude/CLAUDE.themes.md
@.claude/CLAUDE.timer.md
@.claude/CLAUDE.tui.md
@.claude/CLAUDE.build.md
