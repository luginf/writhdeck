## Module structure and builds

Source modules listed in **Generated file structure** above. Build via `Makefile`:

**Build targets** (via `make`):
- `make` or `make all` — generate both files with all available languages
- `make LANGUAGES="en"` — build with English only
- `make LANGUAGES="en fr de es ko"` — build with specific languages
- `make GUI_CONFIG=no` — omit GUI config dialog from `writhdeck.tcl` (excludes `src/gui-config.tcl`, ~700 lines saved; `c` key hidden from browser)
- `make ANALYSIS_TOOLS=no` — omit analysis tools (structure outline, word occurrences, repetitions; `src/analysis.tcl`) from `writhdeck.tcl`/`writhdeck-cli.tcl` (on by default); `make mini MINI_ANALYSIS_TOOLS=yes` / `make jimtcl JIM_ANALYSIS_TOOLS=yes` add them to those targets (off by default)
- `make compact` — generate `writhdeck-compact.tcl` + `writhdeck-cli-compact.tcl` (stripped, ~-20 to -25%)
- `make compact-cli` — generate `writhdeck-cli-compact.tcl` only
- `make jimtcl` — generate `writhdeck-jim.tcl` (JimTcl-compatible TUI build, see below)
- `make sfx` — generate `writhdeck-sfx` (Self-Extracting eXecutable: shell stub + jimsh binary + script, no external deps at runtime); override interpreter with `JIMSH=/path/to/jimsh`
- `make clean` — remove generated files (includes compact, jim, and sfx variants)
- `make test` — run regression tests
- `make test-i18n` — validate translations only
- `make test-syntax` — check Tcl syntax only

`tools/tcl-compact.tcl` — compact filter script. Uses a character-level context scanner to safely strip comments, blank lines, and leading whitespace from all code lines. Preserves content inside `"..."` strings (including those nested inside `{...}` blocks) where indentation is semantically significant.

The Makefile uses `AVAILABLE_LANGS` to auto-detect all `src/i18n/*.tcl` files, so new language files are automatically included in builds. English is always prepended (even if not listed).

Both generated files are:
- Executable (with shebang, +x mode)
- Tracked in git (not ignored)
- Have section headers (`# === state.tcl ===`) for readability during debugging

## Internationalization (i18n)

Modular language system with 6 supported languages. Store translations in `src/i18n/`:

**Language files** (135 keys each):
- `src/i18n/en.tcl` — English (always included, fallback language)
- `src/i18n/fr.tcl` — Français
- `src/i18n/de.tcl` — Deutsch
- `src/i18n/es.tcl` — Español
- `src/i18n/ko.tcl` — 한국어 (Korean)
- `src/i18n/no.tcl` — Norsk (Norwegian)

Each file is split into **two dicts** so TUI-only builds don't ship GUI-only strings:

```tcl
dict set ::i18n LANG { ...keys needed by the TUI/CLI build (common)... }
# >>> GUI-ONLY  (stripped from TUI/CLI builds by the Makefile)
dict set ::i18n_gui LANG { ...keys used only by gui.tcl / gui-config.tcl... }
# <<< GUI-ONLY
```

- **`::i18n`** — keys referenced anywhere in the TUI build path (`tui.tcl`, `common.tcl`, `analysis.tcl`, `config.tcl`, `state.tcl`, `main-cli.tcl`). Always included.
- **`::i18n_gui`** — keys used only by `gui.tcl` / `gui-config.tcl`. Present in the GUI build (`writhdeck.tcl`, GUI+TUI) and the mini build, **stripped** from `writhdeck-cli.tcl`, `writhdeck-jim.tcl`, `writhdeck-dos.tcl` (the Makefile runs `sed '/>>> GUI-ONLY/,/<<< GUI-ONLY/d'` when concatenating their i18n files).

`proc t` (in `src/config.tcl`) looks up `::i18n` first, then `::i18n_gui` (guarded by `info exists` — absent in TUI builds), then falls back to English, then returns the key name itself. So a GUI-only key accidentally requested in a TUI build degrades gracefully instead of erroring.

**Re-deriving the split** — `tools/i18n-split.tcl` regenerates the two-dict partition of every `src/i18n/*.tcl`: a key is "common" if its name appears as a whole word anywhere in the TUI build-path files, otherwise GUI-only. Run it after adding keys or moving a string between GUI and TUI code, then `make test-i18n`. **Adding a key by hand:** put it in the right block of all language files; if a TUI code path references it, it must be in the `::i18n` block (before the marker).

**Build with specific languages:**
```bash
make LANGUAGES="en"              # English only (~95KB)
make LANGUAGES="en fr de es"     # Selected languages (~250KB)
make                             # All available languages (~280KB) — auto-detected
```

English is always included as a fallback language (for missing keys in other languages).

**Using translations in code:**
```tcl
set msg [t help_date_time]              # Retrieves from ::i18n[$::cfg_lang]
set msg [format [t help_cur_time] "12:30"]  # With arguments
```

The proc `t {key args}` (in `src/config.tcl`) falls back to English if a key is missing. Users select language via `lang = CODE` in `~/.writhdeck.ini` or the language dropdown in the config dialog (`c` key in browser).

**Testing translations:**
```bash
make test-i18n    # Validates all languages have complete keys + matching format strings
```

See `src/i18n/README.md` for adding new languages and comprehensive i18n documentation.

## DOS-only code stripping

The FreeDOS/DJGPP port is maintained as a separate project (`../writhdeck-dos/`) and the DOS build is non-functional/anecdotal here. The handful of `$::tcl_platform(os) eq "msdosdjgpp"` branches in `src/state.tcl` and `src/tui.tcl` are wrapped in markers:

```tcl
set ::STATE_FILE [file join $::DOCS_DIR_DEFAULT ".writhdeck.json"]   ;# default
# >>> DOS-ONLY (stripped from non-DOS builds by the Makefile)
if {$::tcl_platform(os) eq "msdosdjgpp"} { set ::STATE_FILE ... }     ;# DOS override
# <<< DOS-ONLY
```

**Rule:** the non-DOS default must come *before* the marked block and be valid on its own, because the Makefile deletes everything between the markers (`$(DOS_FILTER)` = `sed '/>>> DOS-ONLY/,/<<< DOS-ONLY/d'`) for **every build except `writhdeck-dos.tcl`**. The dos target overrides `DOS_FILTER = cat` (target-specific variable) to keep the blocks — it is the source for `../writhdeck-dos/`. `DOS_FILTER` is applied only to `src/state.tcl` and `src/tui.tcl` (the only files with markers). Inline DOS conditions are refactored into a default value + a marked override (see `_stty_fail`, `skip_leading_enters`) so a clean strip leaves correct non-DOS code. `src/compat-dos.tcl` stays dos-only via `DOS_SRCS`.

## JimTcl compatibility (`make jimtcl`)

`writhdeck-jim.tcl` is a TUI-only build that runs under JimTcl 0.84+ (`/opt/jimsh`). Built via `make jimtcl`. Source files are **not modified** — all fixes live in `src/compat-jim.tcl`, loaded immediately after `src/boot-jim.tcl`.

**Six incompatibilities fixed by `src/compat-jim.tcl`:**

| Incompatibility | Fix |
|---|---|
| `chan configure` — no `chan` ensemble in JimTcl | `proc chan` wrapping `fconfigure`; strips `-encoding` option |
| `string is true` — class `true` unknown in JimTcl | Override of `string`: `switch` on `tolower` value (1/yes/true/on) |
| `string is integer -strict` — `-strict` flag not supported | Strip `-strict`, forward to original `string is integer` |
| `file normalize` on non-existent paths — JimTcl errors | Override of `file`: `catch` + manual path normalization fallback |
| `min()`/`max()` in `expr {}` — no math functions in JimTcl | Override of `expr`: depth-counting scanner transforms `min(a,b)` → `[_min [__expr_orig {a}] [__expr_orig {b}]]` |
| `encoding convertfrom`/`convertto` — no `encoding` command | `proc encoding` returning bytes as-is; JimTcl is natively UTF-8 so raw stdin bytes are already valid strings |

**Critical rule for `compat-jim.tcl`:** All internal code in the shim must call `__expr_orig`, `__str_jim`, `__file_jim` directly — never the overridden `expr`/`string`/`file` — to prevent infinite recursion.

**Usage:**
```sh
make jimtcl
/opt/jimsh writhdeck-jim.tcl --tui [file.txt]
```

## SFX (`make sfx`)

**SFX = Self-Extracting eXecutable** — a single standalone file that bundles the jimsh binary and the Tcl script. At runtime, a small shell stub extracts both to a temp directory via `dd`, then `exec`s jimsh on the script. No external interpreter required on the target machine.

```sh
make jimtcl && make sfx          # → writhdeck-sfx
make sfx JIMSH=/usr/local/jimsh  # override interpreter path
./writhdeck-sfx --tui
```

File structure: `[shell stub ~214B][jimsh binary][writhdeck-jim.tcl]`. Offsets are calculated by `tools/make-sfx.py` and embedded in the stub. Portability depends on the jimsh binary: if dynamically linked (check with `ldd /opt/jimsh`), target systems need compatible shared libraries (`libssl`, `libcrypto`, `libc`…). For a fully portable SFX, recompile jimsh as a static binary (musl or `--disable-shared -static`).

## selfx (`make selfx`)

**Self-extracting, zlib-compressed pure-Tcl build** — `writhdeck-selfx.tcl`, ~110 KB vs ~470 KB for `writhdeck.tcl` (-76%). Unlike SFX it bundles **no** binary: it needs a `tclsh`/`wish` already on the machine, but **Tcl/Tk 8.6+** (for `zlib` and `binary decode base64`). Runs both GUI and TUI exactly like the normal build (same `--tui`/`--gui`/`--help` handling).

```sh
make selfx          # → writhdeck-selfx.tcl
wish writhdeck-selfx.tcl            # GUI
tclsh writhdeck-selfx.tcl --tui     # TUI
```

Built by `tools/make-selfx.tcl`: it gzip-compresses the **compact** GUI build (`make selfx` runs `tcl-compact` on `writhdeck.tcl` into a temp file first), base64-encodes it, and writes a tiny wrapper. The wrapper keeps the same sh/Tcl polyglot header as `src/boot.tcl`, then `eval [zlib gunzip [binary decode base64 $_wd_payload]]` at global scope (equivalent to sourcing the program). A `package vcompare [info patchlevel] 8.6` guard prints a friendly error on Tcl 8.5. Trade-offs vs the normal build: not human-readable, and drops the Tcl 8.5 floor — so it is a distribution-only artifact (not part of `make all`, like `sfx`/`dos`).
