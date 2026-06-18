# Subfolder navigation for the browser (optional all-or-nothing module).
#
# Included by default in writhdeck.tcl / writhdeck-cli.tcl; excluded by default
# from writhdeck-mini.tcl / writhdeck-jim.tcl (SUBDIRS_NAV build flag, mirroring
# ANALYSIS_TOOLS). Proc-only, no top-level Tk-building code, so it is safe to
# load in TUI-only builds and is NOT wrapped in `if {!$::no_gui}`.
#
# When this module is absent, every call site in gui.tcl / tui.tcl is guarded
# with `[info procs list-subdirs] ne ""` and the browser behaves exactly as
# before (flat, files-only listing). When present, scanning is still gated at
# runtime by the `browser_subdirs` setting (::cfg_browser_subdirs, default on).
#
# ::br_cwd is the current browse directory: "" means the normal multi-section
# root view (Favorites / Recents / document folders); a non-empty path means a
# single-folder navigation view of that directory.

set ::br_cwd ""

# Immediate subdirectories of $dir (tail names), sorted, hidden dirs and the
# backups folder skipped. Opens nothing and reads no file content.
proc list-subdirs {dir} {
    set out {}
    foreach f [glob -nocomplain -directory $dir -tails -type d *] {
        if {[string match .* $f]} continue
        if {$f eq "backups"} continue
        lappend out $f
    }
    return [lsort -dictionary $out]
}

# Is $dir one of the configured root document folders (br-dirs)?
proc br-is-root {dir} {
    set n [file normalize $dir]
    foreach d [br-dirs] { if {[file normalize $d] eq $n} { return 1 } }
    return 0
}
