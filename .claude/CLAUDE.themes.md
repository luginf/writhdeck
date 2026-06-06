## Color schemes

Scheme files live in `src/schemes/` — one `.tcl` file per scheme, auto-detected by the Makefile (`AVAILABLE_SCHEMES`). Each file calls `dict set ::scheme_defs NAME { ... }` with 18 color keys:

| Key | Description |
|-----|-------------|
| `color_bg` / `color_bg_alt` | Background (dark / light) |
| `color_fg` / `color_fg_alt` | Text foreground (dark / light) |
| `color_bg_bar` / `color_bg_bar_alt` | Status bar background |
| `color_fg_bar` / `color_fg_bar_alt` | Status bar foreground |
| `color_bg_sel` / `color_bg_sel_alt` | Selection background |
| `color_heading` / `color_heading_alt` | Heading color |
| `color_comment` / `color_comment_alt` | Comment/dim color |
| `color_markup` / `color_markup_alt` | Inline markup color |
| `color_bg2` / `color_bg2_alt` | Editor frame outer background (falls back to `color_bg` if absent) |

**Available schemes and their canonical references:**

| Scheme | Reference | Notes |
|--------|-----------|-------|
| `default` | WrithDeck built-in | Defined in `src/schemes/default.tcl` and written to INI by `ini-save` |
| `solarized` | Ethan Schoonover — ethanschoonover.com/solarized | All base colors canonical; `color_bg_sel` (#004555) is a custom choice |
| `gruvbox` | morhetz — github.com/morhetz/gruvbox | Fully canonical |
| `everforest` | sainnhe — github.com/sainnhepark/everforest | Dark medium variant; comment greys are reasonable approximations |
| `nord` | Arctic Ice Studio — nordtheme.com | Fully canonical (nord0–nord10 palette) |
| `alt01` | WrithDeck built-in | Dark red/bordeaux palette |
| `alt02` | WrithDeck built-in | Warm brown/orange palette (derived from alt01 variant) |
| `retro` | WrithDeck built-in | Dark: phosphor green (#33ff33) on near-black (#0a0a0a); light: black on white |

**RULE — never modify color values without asking the user explicitly.** Color choices are deliberate aesthetic decisions. When working on scheme files, only change what the user has explicitly approved.

**Selection text color** — always pair `-selectbackground $bg_sel` with `-selectforeground $fg` on every Tk Text widget. Without `-selectforeground`, Tk inverts the text color in dark mode, making selected text unreadable. Required on all Text widget creations: `.br.mid.lst`, `.br.bar.help`, `.ed.t`, `.ed.ln`, dialog text widgets (`$w.t` in info/stats/help dialogs), `split-make-pane` peer widgets, `split-ws2-open` independent widget. Also needed in `theme-reload` configure calls (~lines 1303, 1336).

## TUI colors (`[tui_colors]` INI section)

ANSI 16-color palette for TUI/TTY mode. Disabled by default (`tui_colors = no`).

**Config keys** (`src/config.tcl` defaults, `[tui_colors]` section in INI):
- `tui_colors` — `yes`/`no` master switch
- `tui_col_heading` — heading lines (`#` marker) → default `cyan`
- `tui_col_comment` — comment/dim lines (`//`, `>`) → default `green`
- `tui_col_markup` — inline bold/italic markers → default `magenta`
- `tui_col_bar_fg` / `tui_col_bar_bg` — status bar fg/bg → default `black` / `cyan`
- `tui_col_sel_bg` — selection background (empty = reverse video) → default empty

**Color names**: `black red green yellow blue magenta cyan white` + `bright_black bright_red bright_green bright_yellow bright_blue bright_magenta bright_cyan bright_white`.

**Implementation** (`src/tui.tcl`):
- `tui-ansi-color {name is_bg}` — converts color name or numeric index to ANSI escape. In 16-color mode: `3x`/`9x` fg, `4x`/`10x` bg. In 256-color mode: `38;5;N` fg, `48;5;N` bg. Returns `""` for unknown names.
- `tui-attr heading` / `tui-attr dim-text` — emit color when `cfg_tui_colors` is on
- `tui-attr sel` — emits `sel_bg` color or falls back to reverse video (`\033[7m`)
- `tui-bar` — uses `bar_fg`/`bar_bg` colors instead of reverse video
- `tui-inline-esc` — includes `markup` color in inline span escapes; uses `sel_bg` for selection instead of code 7

**256-color mode** (`tui_256colors = yes`): uses `\033[38;5;Nm]` / `\033[48;5;Nm]`. Named colors map to indices 0-15 (same palette, always distinct). Numeric values 0-255 accepted directly in INI (e.g. `tui_col_heading = 214` for orange). Note: `bright_*` in 16-color mode may look identical to the normal variant on some TTY (terminal-palette dependent); 256-color mode guarantees the distinction.

**RULE** — `tui-attr dim` (typewriter focus, line numbers, separators) is always dim regardless of color settings. Only `dim-text` (comment marker lines) uses the comment color.

**Activation** — edit `~/.writhdeck.ini` (`tui_colors = yes`) and restart. TUI has no `z` reload; INI changes require a full restart.
