## Editor behavior

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
- **s** — show daily writing statistics (calls `daily-update` first to include unsaved words, then `tui-stats-dialog` / `file-stats-dialog`)
- **w** — show word occurrences — calls `tui-word-occurrences` (same overlay as browser `w`)
- **a** — structure/repetitions/spelling analysis — calls `tui-analyse-dialog` (TUI) / `analyse-dialog` (GUI); only when `src/analysis.tcl` is included in the build
- **Other keys** — exit modal, revert to normal text entry

**Implementation details:**
- State tracked by `$::gui_cmd_mode` (GUI) and `$::tui_cmd_mode` (TUI)
- GUI status message: `"$::cfg_lbl_cmd_mode: exit mode  t/p: timer/pause  b: browser  q: quit  s: stats"` (+ `"  w: words  a: analyse"` when `tui-analyse-dialog`/`analyse-dialog` exists) — built in `ed-status` (`src/gui.tcl`)
- GUI binding: `proc bind-cmd-mode {w}` in `src/gui.tcl` — sets all command-mode bindings (cfg_key_cmd_mode, p/P/t/T/c/C/q/Q/s/S/w/W, Alt-t, Any-KeyPress) on widget `$w`. Called for `.ed.t`, `split-make-pane` peer panes, and `split-ws2-open` independent pane. The catch-all `<Any-KeyPress>` binding (`break` unless the key is the cmd-mode key) is what already blocks arrow-key text movement while modal in the GUI.
- TUI: `$key eq $::cfg_tui_cmd_mode` in editor key handler
- After closing `s`/`w`/`a` overlay: `set wrap_dirty 1` forces editor redraw (TUI)

**TUI arrow-key menu navigation** — while `::tui_cmd_mode` is active, the editor's main key `switch` is preceded by a guard (`src/tui.tcl`, in `tui-editor`) that intercepts movement/edit keys before they reach the normal text-editing cases:
- `LEFT`/`RIGHT` cycle `::tui_cmd_idx` (with wraparound) through the menu returned by `tui-cmd-menu` and redraw the bottom bar via `tui-cmd-message`, which wraps the highlighted entry in `[brackets]` (e.g. `[b:browser]`)
- `ENTER` rewrites `$key` to the letter of the currently highlighted entry (e.g. `t`), so it falls through to the same dispatch used for a direct letter press
- `UP`/`DOWN`/`SHIFT-*`/`CTRL-*`/`HOME`/`END`/`PPAGE`/`NPAGE`/`BACKSPACE`/`DC`/`TAB` are neutralized (rewritten to `""`) — none of them move the cursor or edit text while modal
- `tui-cmd-menu` returns `{t timer} {p pause} {b browser} {q quit} {s stats}` plus `{w words} {a analyse}` when `tui-analyse-dialog` exists — kept in sync with the letters actually dispatched inside the `elseif {$::tui_cmd_mode}` block, so the menu always lists every option
- `::tui_cmd_idx` (declared in `src/state.tcl`) is reset to `0` every time modal mode is entered

## Second workspace (F10)

Two independent editor workspaces accessible via `key_workspace` (default F10). Only one workspace is visible at a time in the editor; the other is preserved in memory.

**State variables** (`src/config.tcl`):
- `::ws_n` — active workspace number (1 or 2)
- `::ws_dual_mode` — set to 1 the first time F10 is pressed; controls `[1]`/`[2]` display in status bar and title
- `::ws1_filename`, `::ws1_scratchpad`, `::ws1_dirty`, `::ws1_content`, `::ws1_cursor`, `::ws1_file_mtime` — saved state of WS1 when WS2 is active
- `::ws2_*` — same set for WS2 (initialized with `ws2_scratchpad=1` so WS2 starts as empty scratchpad)
- `::split_ws2_mode` — 1 when right split pane shows WS2 independently

**GUI — key procs** (`src/gui.tcl`):
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
