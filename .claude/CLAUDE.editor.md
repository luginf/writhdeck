## Editor behavior

**Syntax highlighting** — line-level classification lives in shared parsers (`src/common.tcl`): `parse-heading`, `parse-comment`, `parse-list`. Whole-line precedence is **heading > comment > list**, then inline markup spans (bold/italic/underline/strikethrough). Applied in `highlight-headings` (GUI, `src/gui.tcl`, tags `heading`/`comment`/`list`/`bold`/…) and in the TUI draw loop (`src/tui.tcl`, flags `ish`/`isd` cached + `isl` computed inline via `parse-list`; attr `markup-line` emits the markup colour). `list` and inline markup both use the markup colour (`color_markup` / `tui_col_markup`).

**List highlighting (`parse-list`)** — a line is a list item when it starts (after optional leading whitespace) with `- ` (dash + space, always on) or `* ` (only when `cfg_markdown_support` is on). Whole line coloured in the markup colour. Note: French dialogue lines opening with `- ` are also matched.

**Markdown support (`cfg_markdown_support`)** — canonical config key `markdown_support` (`[behaviour]`, default `yes`) gates all Markdown-flavoured syntax: `#`..`######` headings (`parse-heading`/`heading-level`) and `* ` list bullets (`parse-list`). Legacy key `markdown_headings` is a **deprecated alias** still accepted on load and still written to the INI (both keys emitted, `markdown_support` last so it wins on reload). GUI checkbox on the Display tab (`config_markdown_support` label). More Markdown elements will be added incrementally under this same flag.

**GUI block cursor = overlay label, not Tk's `-blockcursor`** — `-blockcursor` is always 0; the block is a label `.ed.t.cur` placed by `cursor-place` (`src/gui.tcl`, "block cursor (terminal-style overlay)" section). Native block/tag approaches stretch on tabs and at wrapped line ends. Edge cases already fixed in `cursor-place` (each one appeared as a "cursor too wide" report): tab / `\n` / `\r` / empty → forced to one cell width (`cursor-cell-width`); **soft-wrap point** (the space the line breaks on gets a bbox stretched to the right margin) → width clamped to `font measure` of the glyph. If the block widens again, check that guard/clamp first; reproduce with a wish smoke test comparing `winfo width .ed.t.cur` to `font measure` at the offending index.

**Tab key** — inserts a literal tab character (`\t`), not spaces. Both GUI and TUI preserve tabs in files. In split pane bindings, always use `{%W insert insert "\t"; break}` — **never** `[list $w insert insert {\t}]` which would insert the 2-char literal `\t` instead (braces prevent escape interpretation).

**Reload (z key)** — closes current editor/scratchpad and returns to browser. Always relaunches the program without arguments, even if a file was open. Uses platform-specific process launching (Windows `start` command, Unix shell background execution). Configuration apply button also triggers reload.

**GUI copy/cut** — `bind $w <c>` in `bind-cmd-mode` intercepted Ctrl+C because in Tk a modifier-less binding matches all modifier states, and widget-level bindings override class-level `<<Copy>>`. Fix: explicit `<$::cfg_key_copy>` and `<$::cfg_key_cut>` bindings registered both on `.ed.t` (main section) and inside `bind-cmd-mode` (covers split/WS2 panes). Uses `tk_textCopy %W` / `tk_textCut %W`.

## Modal command mode

Editor mode activated by pressing the command-mode key (default: ESC) in the editor (GUI or TUI). Allows quick access to common functions without breaking focus from text.

**Configurable key** — set `key_cmd_mode` in `[keys]` section of `~/.writhdeck.ini` (default: `Escape`). Uses the same Tk key name format as other keys (`Control-e`, `F12`, etc.). The INI value maps through `tk-key-to-tui` → `$::cfg_tui_cmd_mode` (TUI) and `<$::cfg_key_cmd_mode>` binding (GUI). Label for display: `$::cfg_lbl_cmd_mode`.

**Modal mode features:**
- **cmd-mode key** — toggle modal on/off (press again to exit)
- **t** — start timer if inactive; reset (stop + return to full duration) if active
- **p** — pause if running; resume from saved `timer_remaining` if paused (uses `timer-resume`)
- **b** — go to browser (with save prompt if dirty)
- **q** — quit/close current file (with save prompt if dirty)
- **s** — show daily writing statistics (calls `daily-update` first to include unsaved words, then `tui-stats-dialog` / `br-stats`). Works for the **scratchpad** too (no filename): `scratchpad-stats-open`/`scratchpad-stats-record` (`src/common.tcl`) give it a stable virtual path `~/.writhdeck_scratchpad.txt` so daily stats accumulate and totals are read off a live snapshot, independent of ever saving to a real document. `scratchpad-stats-open` is called on scratchpad entry (`open-scratchpad` GUI, `tui-editor` filepath=="" branch) to capture the baseline; the stats dialogs display the name "scratchpad" instead of the dotfile. Same high-water-mark semantics as files (reopening an emptied scratchpad holds the day's count).
- **w** — show word occurrences — calls `tui-word-occurrences` (same overlay as browser `w`)
- **a** — structure/repetitions/spelling analysis — calls `tui-analyse-dialog` (TUI) / `analyse-dialog` (GUI); only when `src/analysis.tcl` is included in the build
- **y** — synonyms for the word under the cursor — calls `tui-synonyms-dialog`/`tui-word-at` (TUI) or `synonyms-dialog` with the Tk `wordstart`/`wordend` indices (GUI); only when `src/analysis.tcl` is included in the build, and only shows results when a Mythes thesaurus is installed (see **Synonyms (Mythes thesaurus)** below)
- **Other keys** — exit modal, revert to normal text entry

**Implementation details:**
- State tracked by `$::gui_cmd_mode` (GUI) and `$::tui_cmd_mode` (TUI)
- GUI status message: `"$::cfg_lbl_cmd_mode: exit mode  t/p: timer/pause  b: browser  q: quit  s: stats"` (+ `"  w: words  a: analyse"` when `tui-analyse-dialog`/`analyse-dialog` exists, `"  y: synonyms"` when `synonyms-dialog` exists) — built in `ed-status` (`src/gui.tcl`)
- GUI binding: `proc bind-cmd-mode {w}` in `src/gui.tcl` — sets all command-mode bindings (cfg_key_cmd_mode, p/P/t/T/c/C/q/Q/s/S/w/W/y/Y, Alt-t, Any-KeyPress) on widget `$w`. Called for `.ed.t`, `split-make-pane` peer panes, and `split-ws2-open` independent pane. The catch-all `<Any-KeyPress>` binding (`break` unless the key is the cmd-mode key) is what already blocks arrow-key text movement while modal in the GUI.
- TUI: `$key eq $::cfg_tui_cmd_mode` in editor key handler
- After closing `s`/`w`/`a` overlay: `set wrap_dirty 1` forces editor redraw (TUI)

**TUI arrow-key menu navigation** — while `::tui_cmd_mode` is active, the editor's main key `switch` is preceded by a guard (`src/tui.tcl`, in `tui-editor`) that intercepts movement/edit keys before they reach the normal text-editing cases:
- `LEFT`/`RIGHT` cycle `::tui_cmd_idx` (with wraparound) through the menu returned by `tui-cmd-menu` and redraw the bottom bar via `tui-cmd-message`, which wraps the highlighted entry in `[brackets]` (e.g. `[b:browser]`)
- `ENTER` rewrites `$key` to the letter of the currently highlighted entry (e.g. `t`), so it falls through to the same dispatch used for a direct letter press
- `UP`/`DOWN`/`SHIFT-*`/`CTRL-*`/`HOME`/`END`/`PPAGE`/`NPAGE`/`BACKSPACE`/`DC`/`TAB` are neutralized (rewritten to `""`) — none of them move the cursor or edit text while modal
- `tui-cmd-menu` returns `{t timer} {p pause} {b browser} {q quit} {s stats}` plus `{w words} {a analyse}` when `tui-analyse-dialog` exists, plus `{y synonyms}` when `tui-synonyms-dialog` exists — kept in sync with the letters actually dispatched inside the `elseif {$::tui_cmd_mode}` block, so the menu always lists every option
- `::tui_cmd_idx` (declared in `src/state.tcl`) is reset to `0` every time modal mode is entered

## Synonyms (Mythes thesaurus)

Word-level synonym lookup via the [Mythes](https://github.com/LibreOffice/dictionaries) thesaurus data used by LibreOffice — the same `mythes-fr`/`mythes-en-us`/`mythes-de`/`mythes-es`/`mythes-no` Debian/Ubuntu packages. Unlike hunspell, Mythes ships **no CLI binary** (`libmythes` is a shared library only), so `src/analysis.tcl` parses its `.dat`/`.idx` files directly instead of piping to an external process:

- `thes-candidate-dirs {}` — fixed list of directories to search: `/usr/share/mythes`, `/usr/share/hunspell`, `/usr/local/share/mythes`, `/opt/homebrew/share/mythes`
- `thes-files-resolve {dict}` — returns `{dat idx}` for `th_${dict}_v2.{dat,idx}` in the first candidate dir where both files exist, or `{}`. `dict` reuses `spell-dict-resolve` (`src/analysis.tcl`) as-is — Mythes and hunspell dictionary names are identical (e.g. `fr_FR`), verified against the actual Debian packages
- `thes-available {}` — `[thes-files-resolve [spell-dict-resolve]] ne {}`; checked before every lookup to distinguish "no thesaurus installed" from "word not in thesaurus"
- `thes-idx-load {idxpath}` / `thes-idx-find {lines word}` — the `.idx` file is loaded once per path and cached in `::thes_idx_cache($idxpath)` as a flat list of raw `word|offset` lines; `thes-idx-find` binary-searches it with plain `string compare`. This only works because the Mythes `.idx` files are sorted in exact Tcl `lsort` order (verified against `thes_fr.idx`) — if a future dictionary format sorts differently (e.g. locale-aware collation), the binary search would need to fall back to a linear scan
- `thes-dat-entry {datpath offset}` — `seek`s to the byte offset (Tcl channel offsets are byte-based regardless of `-encoding utf-8`, confirmed against the actual files) and parses the `word|N` header followed by `N` `(Category)|syn1|syn2|...` lines into `{category {syn1 syn2 ...}}` pairs
- `thes-lookup {word}` — ties the above together; tries `$word` then `[string tolower $word]` (thesaurus entries are lowercase, so a capitalised word at a sentence start would otherwise miss) and returns the entry list (possibly `{}` if genuinely not found — caller must have already checked `thes-available`)
- `tui-word-at {line cx}` — extracts the word touching column `cx` (0-based) in `line`, same word regex as `spell-check-document`; shared helper for the TUI editor's `y` cmd-mode key

**GUI** (`src/gui.tcl`/`src/analysis.tcl`): `synonyms-dialog {word}` shows results in a toplevel (`.syndlg`), one `(category)` heading per sense; clicking a listed synonym re-runs `synonyms-dialog` for that word via `after idle` (destroying `.syndlg` synchronously from inside its own tag binding is the same pitfall as the Help dialog close — see **GUI-specific patterns** in `CLAUDE.browser.md`). `synonyms-prompt {}` wraps `input-dialog` for manual word entry (the "Synonyms" button in `analyse-dialog`). The editor's `y`/`Y` cmd-mode key looks up `[$t get "insert wordstart" "insert wordend"]` on `[primary-ed]` directly (Tk's native word-boundary indices).

**TUI**: see `tui-synonyms-dialog` in `CLAUDE.tui.md`.

Both entry points degrade gracefully when `thes-available` is false: `[format [t br_synonyms_unavailable] [spell-dict-resolve]]` names the missing dictionary, mirroring `br_spellcheck_unavailable`.

## Second workspace (F10)

Two independent editor workspaces accessible via `key_workspace` (default F10). Only one workspace is visible at a time in the editor; the other is preserved in memory.

**State variables** (`src/config.tcl`):
- `::ws_n` — active workspace number (1 or 2)
- `::ws_dual_mode` — set to 1 the first time F10 is pressed; controls `[1]`/`[2]` display in status bar and title
- `::ws1_filename`, `::ws1_scratchpad`, `::ws1_dirty`, `::ws1_content`, `::ws1_cursor`, `::ws1_file_mtime` — saved state of WS1 when WS2 is active
- `::ws2_*` — same set for WS2 (initialized with `ws2_scratchpad=1` so WS2 starts as empty scratchpad)
- `::split_ws2_mode` — 1 when right split pane shows WS2 independently

**GUI — key procs** (`src/gui.tcl`, except the `split-*` procs which live in the optional module `src/gui-split.tcl` — see CLAUDE.md **Generated file structure**):
- `workspace-toggle` — saves active workspace to ws{n}_*, loads other workspace into `.ed.t`; in split mode redirects to `split-ws2-open`/`split-cycle-focus`; sets `ws_dual_mode=1`; cancels/restarts watch-file timer with correct `file_mtime_known`
- `ed-update-title` — shows `[1]`/`[2]` in window title when `ws_dual_mode==1`
- `split-pane-padding` — returns `{padx_in padx_out pady_in pady_out}` for pane widgets; shared by `split-make-pane` and `split-ws2-open`
- `split-ws2-open` — replaces the right peer pane with an independent `text` widget loaded with WS2 content; sets `split_ws2_mode=1`; has own save/open/close bindings
- `split-ws2-save`, `split-ws2-save-as`, `split-ws2-load-file`, `split-ws2-save-state` — WS2 pane operations
- `ws-check-inactive-dirty` — called by `quit-app`; prompts to save the inactive workspace if dirty; writes directly from `ws{n}_content`
- `open-file-dialog` — detects `split_ws2_mode && focus eq .ed.pw.r.t` and routes Ctrl+O to WS2

**Status bar tokens** (`status-build` in `src/common.tcl`): `workspace filename dirty sel ln col words chars goal clock timer space help_bar`. Any unrecognized token falls through to a `default` clause and is appended as literal text — allows custom separators like `|` or `--` directly in `status_left/center/right` INI values. Multi-word literals must be quoted in the INI (Tcl list syntax).

**Status bar token** `workspace`: appends `[ws_n] ` when `ws_dual_mode==1`; added at front of `cfg_status_left` default.

**Quit handling:**
- `quit-app` calls `ws-check-inactive-dirty` after the active-workspace prompt
- Browser `q` and status bar `q` button call `quit-app` (not `exit` directly)
- ESC+q modal calls `close-editor` (returns to browser in same process); quit-app is called when user quits from browser
- `br-reload` uses `after 200 exit` for app restart — never call it for close-editor flow

**Rules:**
- `show-editor` resets `ws_n=1` only when `.br` is mapped (`winfo ismapped .br`)
- `close-editor` saves WS2 state if `ws_n==2` but does NOT reset `ws_n` (preserves context for quit-app to check inactive workspace)
- `open-scratchpad` always resets `ws_n=1`

**TUI — key procs** (`src/tui.tcl`):
- `tui-ws-run {fp}` — wrapper loop; handles `__ws_toggle__` (F10) and `__ws2_open__` (Ctrl+O in WS2); sets `ws_dual_mode=1` on first toggle
- `tui-editor` returns `"__ws_toggle__"` on F10, `"__ws2_open__"` on Ctrl+O when `ws_n==2`
- On `__ws2_open__`: `tui-ws-run` shows browser, user picks file, re-enters `tui-editor` with `ws_n` still 2
- `tui-ws-check-inactive-dirty {rows cols}` — TUI counterpart of `ws-check-inactive-dirty`; called in browser `q`, editor Ctrl+W, and editor ESC+q
- `tui-split-save-right` — saves the right pane state (split_r_*) to ws1_*/ws2_* before closing split or returning from editor

**TUI split view** — F3: if `ws_dual_mode==1` opens WS2 in right pane (`split_ws2_mode=1`), otherwise same-file split. F4 toggles focus. `_fswap` (value `1`/`2`) swaps `cy/cx/scroll/layout/lines/dirty` between left and right pane when `split_focus==2`. Right pane shares the undo stack and has no independent syntax highlighting. See SKILLS.md for full state variable list.
