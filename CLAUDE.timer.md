## Timer and stopwatch

Configurable countdown timer and stopwatch accessible via modal command mode or ALT+t keybinding:

**Configuration** (`src/config.tcl`):
- `cfg_timer_duration` — default duration in minutes (25 default)
- `cfg_timer_sound` — play bell sound on completion (boolean)
- `cfg_timer_type` — "countdown" or "stopwatch"
- `cfg_timer_alert` — show alert dialog on completion (boolean)

**Status bar display:**
- Timer displays as `m'ss"` format (e.g., `4'00"` for 4 minutes)
- Active timer shows as `[4'00"]`, inactive as ` 4'00"`
- Handled by `status-build` proc in `src/common.tcl` (token: "timer")

**Timer control procs** (`src/config.tcl`):
- `timer-start` — start from the beginning (resets `timer_remaining`)
- `timer-pause` — pause, preserving `timer_remaining`
- `timer-resume` — resume from current `timer_remaining` without resetting it
- `timer-reset` — stop and reset `timer_remaining` to full duration; sets `timer_last_tick = 0`
- `timer-tick` — background update (called by `after` every second)
- `timer-alert` — show alert when countdown reaches zero

**Timer display state** — `timer_last_tick` distinguishes "never started / reset" from "paused":
- `timer_active=1` → running → show `timer_remaining`
- `timer_active=0, timer_last_tick≠0` → paused → show `timer_remaining`
- `timer_active=0, timer_last_tick=0` → fresh/reset → show `cfg_timer_duration * 60` (countdown) or `0` (stopwatch)
- Condition used in all three display sites: `$::timer_active || $::timer_last_tick != 0`

**Alert implementation:**
- **GUI** (`timer-alert-gui`): Toplevel dialog with "Timer finished!" message + `bell` command
- **TUI** (`tui-timer-alert`): Full-screen overlay with "TIMER FINISHED!" message + `bell` command
- Sound controlled by `$::cfg_timer_sound` setting

## Autosave

Periodic snapshot of the active workspace to `~/Documents/writhdeck/autosave_ws01.txt` (WS1) or `autosave_ws02.txt` (WS2). Overwrite mode — single latest snapshot, not a log.

**Configuration** (`src/config.tcl`, section `[misc]` in INI):
- `cfg_autosave_enabled` — boolean, default `yes`
- `cfg_autosave_interval` — integer minutes, default `1`

**File format:**
```
folder/filename          (or "scratchpad")
YYYY-MM-DD HH:MM:SS

-------------------------
content (unsaved changes included)
```

**`do-autosave {ws_n content filepath}`** (`src/common.tcl`) — shared GUI/TUI. Opens in `w` mode. Guard: `max(1, $::cfg_autosave_interval)` prevents zero-interval tight loop.

**GUI** (`src/gui.tcl`):
- `autosave-start` — cancels any pending schedule, schedules `autosave-tick` after `max(1,interval)*60000` ms
- `autosave-stop` — cancels pending schedule
- `autosave-tick` — saves active WS from `[[primary-ed] get 1.0 end-1c]` + inactive WS from `::ws{n}_content` if `ws_dual_mode`; reschedules via `autosave-start`
- `show-editor` calls `autosave-start`; `close-editor` calls `autosave-stop`

**TUI** (`src/tui.tcl`):
- `set ::autosave_last_time [clock seconds]` at start of `tui-editor`
- Check at top of main loop: `if {$_now - $::autosave_last_time >= max(1, $::cfg_autosave_interval) * 60}`
- `tui-getch` timeout: `50ms` when autosave enabled (same as timer), **never 1000ms** — 1000ms causes up to 1 second latency per keystroke because a key arriving after the first non-blocking read waits out the full sleep.
