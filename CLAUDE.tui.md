## TUI dialogs — pattern no-flicker

TUI dialogs (config, help, stats, words) must not clear the screen on each redraw. The correct pattern:
1. `puts -nonewline "\033\[2J\033\[H"; flush stdout` — once **before** the `while 1` loop (clears previous content)
2. `puts -nonewline "\033\[H"` — inside the loop (cursor home, no erase; lines are overwritten with `\033\[K`)
3. No `\033\[2J` after the loop — the caller (browser or editor) redraws its own content

**`tui-getch` blocking** — when called with default argument (no timer active), performs a true blocking `read stdin 1` instead of returning `""` immediately. This keeps the cursor visible until the user types. When timer is active (`cfg_chrono_show`), uses 50ms poll to allow timer display updates.

**TUI timer tick fast path** — when `tui-getch` returns `""` (timer tick, no key) and `!$wrap_dirty && $dirty_line < 0`, the editor skips the full text redraw and only updates the status bar using ANSI cursor save/restore (`\033[s` / `\033[u`). This eliminates cursor flicker caused by 20 full redraws per second. Full redraw only happens after real key presses or content changes. The `\033[?25l` hide is placed just before `tui-move` + `\033[?25h` at the end of the draw loop so hide and show are always in the same buffer flush.

**TUI dialog procs** (defined in `src/tui.tcl`):
- `tui-info-dialog {text rows cols}` — centered reverse-video overlay, waits for any key. Used by browser `i` key (full path) and `tui-word-occurrences` (no words found).
- `tui-stats-dialog {filepath rows cols}` — writing stats overlay: sorted by date descending, reverse-video headers, total line, `c` to clear, `q`/Ctrl+H to close. Returns `[t br_stats_no_data]` if no data (caller sets status message).
- `tui-word-occurrences {fpath rows cols}` — scrollable word occurrences overlay (UP/DOWN/HOME/END), `q` to close. Scroll bounds: `max(0, total - usable)` to avoid negative indices when content fits on one screen.

**Browser `i` key (TUI)** — calls `tui-info-dialog` (persistent overlay) instead of setting the `msg` variable. `msg` is cleared after one loop tick; for persistent display an overlay is required.
