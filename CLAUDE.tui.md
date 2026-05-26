## TUI dialogs — pattern no-flicker

TUI dialogs (config, help, stats, words) must not clear the screen on each redraw. The correct pattern:
1. `puts -nonewline "\033\[2J\033\[H"; flush stdout` — once **before** the `while 1` loop (clears previous content)
2. `puts -nonewline "\033\[H"` — inside the loop (cursor home, no erase; lines are overwritten with `\033\[K`)
3. No `\033\[2J` after the loop — the caller (browser or editor) redraws its own content

**`tui-getch` blocking** — when called with default argument (no timer active), performs a true blocking `read stdin 1` instead of returning `""` immediately. This keeps the cursor visible until the user types. When timer is active (`cfg_chrono_show`), uses 50ms poll to allow timer display updates.

**TUI timer tick fast path — skip draw + zero output** — the main editor loop polls every 50ms when timer or autosave is active. To avoid cursor flickering (especially on HaikuOS Terminal, which renders terminal output more progressively than Linux/macOS), the loop minimises terminal output on ticks where nothing changed:

- `_need_draw` is computed before the layout section: `$wrap_dirty || $tw != $prev_tw || $dirty_line > 0`
- `_do_draw = $_need_draw || !$_skip_draw` — true on first iteration and after any key press; false on pure timer ticks
- `_skip_draw` is set to 1 by the fast path (`continue`) and reset to 0 at the start of each iteration before computing `_do_draw`
- The draw block (`if {$_do_draw}`) contains the full screen draw, `tui-move`, and `\033[?25h]` + flush — **nothing outside this block writes to stdout**
- `\033[?25l]` is used **only inside** `if {$_do_draw}` (at the start of the draw block). Since draws only happen after key presses, this hide/show cycle occurs at typing speed — imperceptible, and prevents cursor artefacts (cursor briefly appearing at status bar row during draw)
- The fast path caches the last rendered status bar strings (`_last_bar_l`, `_last_bar_c`, `_last_bar_r`). On a timer tick: compute new strings; if identical to cache → **zero bytes sent to terminal**; if changed (≈1×/sec for clock/timer) → `\033[s]` + bar + `\033[u]` + flush only

**Result**: on unchanged ticks, no terminal output whatsoever — no cursor hide/show, no tui-move, no flush. Cursor remains visible at text position from the last full draw. Status bar updates ≈1×/sec with save/restore only (no cursor manipulation).

**TUI dialog procs** (defined in `src/tui.tcl`):
- `tui-info-dialog {text rows cols}` — centered reverse-video overlay, waits for any key. Used by browser `i` key (full path) and `tui-word-occurrences` (no words found).
- `tui-stats-dialog {filepath rows cols}` — writing stats overlay: sorted by date descending, reverse-video headers, total line, `c` to clear, `q`/Ctrl+H to close. Returns `[t br_stats_no_data]` if no data (caller sets status message).
- `tui-word-occurrences {fpath rows cols}` — scrollable word occurrences overlay (UP/DOWN/HOME/END), `q` to close. Scroll bounds: `max(0, total - usable)` to avoid negative indices when content fits on one screen.

**Browser `i` key (TUI)** — calls `tui-info-dialog` (persistent overlay) instead of setting the `msg` variable. `msg` is cleared after one loop tick; for persistent display an overlay is required.
