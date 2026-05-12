# Color Schemes

This directory contains modular color scheme definitions. Each scheme is defined in a separate `.tcl` file and is automatically loaded at build time via the Makefile.

## File Structure

Each scheme file defines a Tcl dictionary with the scheme name and colors:

```tcl
dict set ::scheme_defs <scheme-name> {
    color_bg       "#rrggbb"
    color_fg       "#rrggbb"
    color_bg_bar   "#rrggbb"
    color_fg_bar   "#rrggbb"
    color_bg_sel   "#rrggbb"
    color_heading  "#rrggbb"
    color_comment  "#rrggbb"
    color_markup   "#rrggbb"
    color_bg_alt       "#rrggbb"
    color_fg_alt       "#rrggbb"
    color_bg_bar_alt   "#rrggbb"
    color_fg_bar_alt   "#rrggbb"
    color_bg_sel_alt   "#rrggbb"
    color_heading_alt  "#rrggbb"
    color_comment_alt  "#rrggbb"
    color_markup_alt   "#rrggbb"
}
```

## Available Schemes

- **default.tcl** — Default neutral dark/light theme
- **solarized.tcl** — Solarized (blue-based, professional)
- **gruvbox.tcl** — Gruvbox (warm, retro-inspired)
- **everforest.tcl** — Everforest (natural green tones)
- **nord.tcl** — Nord (arctic, north-bluish palette)
- **alt01.tcl** — Alt01 (warm, muted colors)

## Adding a New Scheme

1. Create a new file `src/schemes/myscheme.tcl`
2. Define the scheme dictionary with all 16 colors
3. The Makefile will automatically load it on next build

Example:

```tcl
# My Custom Scheme

dict set ::scheme_defs myscheme {
    color_bg       "#1e1e2e"
    color_fg       "#cdd6f4"
    ...
}
```

## Build Integration

The Makefile detects all `*.tcl` files in `src/schemes/` and:
1. Loads them after `src/config.tcl`
2. Initializes `$::cfg_schemes` from `$::scheme_defs`
3. Makes all schemes available in the generated executables

## User Customization

Users can also define custom schemes in their `~/.writhdeck.ini`:

```ini
[schemes]

[myscheme]
color_bg = #1e1e2e
color_fg = #cdd6f4
...
```

Then select with:
```ini
[editor]
scheme = myscheme
```
