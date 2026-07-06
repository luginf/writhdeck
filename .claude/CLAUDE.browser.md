## Browser shortcuts and status bar

The browser status bar displays shortcuts with bold formatting on the first character:
- `h:help`, `n:new`, `t:scratchpad`, etc. — letter is bold, colon and label follow
- Built using a hardcoded foreach loop inserting pairs of bold key + label text
- Click handler uses `.br.bar.help tag bind` for each shortcut to invoke the command
- Cursor changes to hand2 on hover (Enter/Leave bindings)

Current browser keys (13 total): h (help), n (new), t (scratchpad), f (favorite), s (stats), b (backup), d (delete), r (rename), i (info), c (config), z (reload), / (incremental filter), q (quit).

## Adding a new browser key

6 places to update:
1. `br_help_gui` i18n (EN + FR)
2. `br_help_tui` i18n (EN + FR)
3. Add to the status bar foreach loop in browser frame init (`.br.bar.help`)
4. `bind .br.mid.lst <x>` in the GUI block (for keyboard binding)
5. `switch -- $key` in `tui-browser`
6. BROWSER section of `help-dialog`
7. Browser shortcut tables in `README.md` and `README.fr.md`

## Profile configuration dialog

Accessible via `c` key in browser. Invoked by `profile-config-dialog` proc. **Six tabs, in this order: Profile, Display, Fonts, Schemes, Timer, Misc.** Defined in `src/gui-config.tcl` (optional module — excluded with `make GUI_CONFIG=no`).

- **Profile tab**: Global settings (default profile/scheme/language); per-profile: margin width/height, word goal, dark mode, line spacing (%), bar height, line numbers, block cursor, blinking cursor
- **Fonts tab**: Per-profile font family (entry + available fonts listbox with scrollbar), font preview label (initialized with current font/size on open and on profile switch), font size spinbox
- **Timer tab**: Type (countdown/stopwatch), duration (spinbox), sound at end (checkbox), alert message (checkbox), show in status bar (checkbox)
- **Misc tab**: Autosave enabled/interval; Behaviour section: documents folder (entry + Browse button), browser file filter (entry, space-separated glob patterns, default `*.txt *.t2t *.md *.ini`), show all files / bypass filter (checkbox, default off), browser on start, watch file, Hemingway mode, split shrink margin, cursor restore, pinned TOC panel
- **Display tab**: Status bar zones (left/center/right entries); Editor section (heading marker); Markup section (comment/bold/italic/underline/strikethrough markers, Markdown support)
- **Apply button**: Packed before tab content via `pack -before` so it stays visible at top; saves all tabs to globals + `ini-save`, applies theme, triggers `br-reload`

Tab switching via `config-tab-switch {w tab}` — `pack forget` all frames, `pack` the active one, update button appearance. Tabs (in display order): `profile`, `display`, `fonts`, `schemes`, `timer`, `misc`.

Per-profile configuration stored in `::cfg_profiles` dict (keys: `font_family`, `font_size`, `margin_width`, `margin_height`, `word_goal`, `dark_mode`, `line_spacing`, `bar_height`, `line_numbers`, `block_cursor_gui`, `blink_cursor`). Values persist via `.writhdeck.json`.

Profile values loaded on profile switch via `profile-config-update-profile {w}` — reads each key from the profile dict, falls back to global if absent. Also updates the font preview label.

Key implementation details:
- Both Profile tab and Fonts tab have a profile selector linked to the same `::profile_config_profile` variable
- Font preview (`$w.tab_fonts.preview`) updated in `profile-config-update-profile` and on listbox select / entry KeyRelease / spinbox command
- `-command` option on font size spinbox to trigger preview updates on button clicks
- `profile-config-update-profile` called on initial load and on profile dropdown change (via trace)
- Markup marker entries use `marker-val` on load (shows empty string for disabled markers) and on save
- docs_dir Browse button uses `tk_chooseDirectory`, stores path with `~` substitution for HOME
- Dialog created inside a toplevel window, destroyed after user closes
- `c` shortcut and `bind .br.mid.lst <c>` guarded with `[info procs profile-config-dialog] ne ""` — absent when `GUI_CONFIG=no`

**TUI config dialog** (`tui-config-dialog`) — same two functional tabs (Timer, Misc); TAB key switches tabs; `\033[2J` on tab switch to clear stale lines from previous tab; UP/DOWN navigate fields, LEFT/RIGHT/SPACE adjust values, `s` saves, `q` cancels.

## Browser entry types (`::br_entries`)

| Type       | Notes                                                                                                |
| ---------- | ---------------------------------------------------------------------------------------------------- |
| `header`   | Section separator. `dir=""` → label = `name` field (Favorites, Recents). `dir≠""` → abbreviated path |
| `file`     | File in a watched folder                                                                             |
| `favorite` | Pinned file (any folder)                                                                             |
| `recent`   | Recent file outside watched folders (deduplicated)                                                   |

Section order: `DOCS_DIR_DEFAULT` → `DOCS_DIR` (if custom) → Favorites → Recents.
`br-active-dir` walks up to the nearest `header`; if `dir=""` returns `DOCS_DIR_DEFAULT`.

## Browser file filter

`list-docs {dir}` (`src/common.tcl`, shared GUI/TUI) filters the main directory listing by `::cfg_browser_filter` — a space-separated list of glob patterns (default `*.txt *.t2t *.md *.ini`), matched case-insensitively against the filename via `string match`. Empty filter = show everything. `::cfg_browser_show_all` (default off) bypasses the filter entirely regardless of `cfg_browser_filter`.

Both settings are editable on the Misc tab (`ffilter` entry, immediately followed by the standalone `fshowall` checkbox right below it, then the `fsubdirs` checkbox for `browser_subdirs`). Note: favorites/recents (`build-extra-entries`) are **not** filtered — only the main directory listing.

## Incremental filter ("/" key)

Live substring filter on top of the extension filter above. Shared state: `::br_type_filter` + `br-filter-match {name}` (`src/common.tcl`) — case-insensitive `string first` (no glob), empty = match all. Applied to `file`/`favorite`/`recent` entries in `br-refresh` (GUI) and the `tui-browser` entry-building loop; `dir`/`updir`/`header` entries are never filtered. Not persisted (transient, reset on restart).

- **GUI**: `/` calls `br-filter-begin` — packs a `.br.filter` frame (label `/` + entry bound to `::br_type_filter`) above the status bar, `<KeyRelease>` triggers `br-refresh`. ESC in the entry or in the list calls `br-filter-end` (clears + destroys + refocuses list); Return/Up/Down refocus the list keeping the filter (bar stays visible as indicator). Also a clickable `/:filter` shortcut in the help bar (`br_key_filter`).
- **TUI**: `/` sets the local `fmode` flag in `tui-browser`; while set, printable keys append to `::br_type_filter`, BACKSPACE deletes (exits when empty), ENTER keeps the filter and returns to normal keys, ESC clears; UP/DOWN/HOME/END fall through to navigation. Bottom-left bar shows `/text` (+ trailing `_` while typing). ESC with a filter active (outside fmode) clears it.
- i18n keys: `br_key_filter`, `br_help_filter` (GUI-only block); `/:filter` added to `br_help_tui`/`br_help_gui` in all 6 languages.

## Subfolder navigation (optional module `src/subdirs.tcl`)

Explorer-style browsing of subdirectories inside the document folders. Optional all-or-nothing module (`SUBDIRS_NAV` build flag, excluded by default from `writhdeck-mini.tcl`/`writhdeck-jim.tcl`, same pattern as analysis); every call site is guarded with `[info procs list-subdirs] ne ""`. Also gated at runtime by `::cfg_browser_subdirs` (`browser_subdirs` in `[behaviour]`, default `yes`).

- **Module exports**: `list-subdirs {dir}` (immediate subdirs, tails, sorted, hidden dirs + `backups` skipped), `br-is-root {dir}` (is `dir` one of `br-dirs`?), and the state var `::br_cwd` (`""` = normal multi-section root view; a path = single-folder navigation view of that dir).
- **Two new `::br_entries` types**: `dir` (`{dir parentdir subname}`, rendered `subname/`) and `updir` (`{updir parentdir ".."}`, rendered `../`). Both are selectable but excluded from `br-selected` (file ops never act on them).
- **Root view** (`br_cwd == ""`): Favorites/Recents as before, then under each `br-dirs` header the subfolders (`dir` entries) followed by files. **Nav view** (`br_cwd != ""`): single header + `..` + subfolders + files, no Favorites/Recents.
- **GUI** (`gui.tcl`): `br-open` routes `dir`→`br-cwd-enter`, `updir`→`br-cwd-up`; `br-selected-raw` returns the raw entry. Up-level bound on `<BackSpace>` and `<Left>`. New files (`br-new` via `br-active-dir`) land in the current folder (header dir = `br_cwd`).
- **TUI** (`tui-browser`): local `cwd` var (not the global), `_subnav` flag, `fidx` includes dir/updir, ENTER navigates, `BACKSPACE`/`LEFT` go up, file ops (i/f/s/b/d/r) guarded by `$ctype in {file recent favorite}`. Bottom bar shows `cwd` when navigating.

## Pinned TOC panel — F11 vs Shift+Ctrl+F11

`cfg_key_toc` (default `F11`) opens the TOC: as a floating popup (`toc-show`) normally, or toggles the pinned side panel (`toc-panel-toggle`) when `cfg_toc_pinned` is on. `cfg_key_toc_pinned` (default `Control-Shift-F11`) always toggles the pinned panel via `toc-panel-toggle`, regardless of `cfg_toc_pinned` — letting users open the panel once even while in popup mode.

`toc-panel-toggle` calls `toc-panel-open`/`toc-panel-close` based on `::toc_panel_open`. Bound (GUI only, not in `writhdeck-cli.tcl`) on: `.ed.t` (main editor), each `split-make-pane` peer, the WS2 pane (`.ed.pw.r.t`), and `.ed.toc.lst` (closes the panel from inside it).

All `toc-panel-*` procs live in the optional module `src/gui-toc-panel.tcl` (`GUI_TOC_PANEL=no` to exclude); every binding/call site is guarded with `[info procs toc-panel-toggle] ne ""` or gated by `::toc_panel_open` (see CLAUDE.md **Generated file structure**).

## GUI-specific patterns

**Help dialog close** — use `after idle [list destroy $w]; break` on keyboard bindings inside the Text widget; plain `destroy` triggers `<<TkTextBackspace>>` on the already-destroyed widget.

**`grab $w` after `update`** — in Toplevel dialogs, `grab $w` must be called only after `update` and after all widgets are packed. Calling it immediately after `toplevel $w` (before any widgets exist) fails with "grab failed: window not viewable".

**`quit-app`** — only prompts to save if `$::filename ne "" || $::scratchpad`.

**`open-file-dialog`** — uses `[file dirname $::filename]` as `initialdir` when a file is open, otherwise `DOCS_DIR_DEFAULT`.
