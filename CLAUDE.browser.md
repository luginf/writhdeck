## Browser shortcuts and status bar

The browser status bar displays shortcuts with bold formatting on the first character:
- `h:help`, `n:new`, `t:scratchpad`, etc. — letter is bold, colon and label follow
- Built using a hardcoded foreach loop inserting pairs of bold key + label text
- Click handler uses `.br.bar.help tag bind` for each shortcut to invoke the command
- Cursor changes to hand2 on hover (Enter/Leave bindings)

Current browser keys (12 total): h (help), n (new), t (scratchpad), f (favorite), s (stats), b (backup), d (delete), r (rename), i (info), c (config), z (reload), q (quit).

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

Accessible via `c` key in browser. Invoked by `profile-config-dialog` proc. Three tabs: **Profile**, **Timer**, **Misc**.

- **Profile tab**: Dropdown to select active profile + scheme + language; controls for font family (listbox), font size (spinbox), margin width/height (spinbox), word goal, dark mode
- **Timer tab**: Type (countdown/stopwatch), duration (spinbox), sound at end (checkbox), alert message (checkbox), show in status bar (checkbox)
- **Misc tab**: Autosave enabled (checkbox), autosave interval in minutes (spinbox 1–60)
- **Apply button**: Saves all tabs to globals + `ini-save`, applies theme, triggers `br-reload`

Tab switching via `config-tab-switch {w tab}` — `pack forget` all frames, `pack` the active one, update button appearance. Tabs: `profile`, `timer`, `misc`.

Per-profile configuration stored in `::cfg_profiles` dict. Values persist via `.writhdeck.json`.

Key implementation details:
- Uses `-command` option on spinbox to trigger preview updates on button clicks (not just keyboard entry)
- `profile-apply-fonts` helper saves to dict and applies to editor frame
- `br-refresh` called after apply to reload browser with fresh configuration
- Dialog created inside a toplevel window, destroyed after user closes

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

## GUI-specific patterns

**Help dialog close** — use `after idle [list destroy $w]; break` on keyboard bindings inside the Text widget; plain `destroy` triggers `<<TkTextBackspace>>` on the already-destroyed widget.

**`grab $w` after `update`** — in Toplevel dialogs, `grab $w` must be called only after `update` and after all widgets are packed. Calling it immediately after `toplevel $w` (before any widgets exist) fails with "grab failed: window not viewable".

**`quit-app`** — only prompts to save if `$::filename ne "" || $::scratchpad`.

**`open-file-dialog`** — uses `[file dirname $::filename]` as `initialdir` when a file is open, otherwise `DOCS_DIR_DEFAULT`.
