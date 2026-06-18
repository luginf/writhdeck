#!/usr/bin/env tclsh
# One-shot reorganizer: splits each src/i18n/LANG.tcl into two dict blocks.
#   ::i18n      LANG { ... }   keys needed by the TUI/CLI build (common)
#   ::i18n_gui  LANG { ... }   keys used only by gui.tcl / gui-config.tcl
# The GUI-only block is wrapped in markers so the Makefile can strip it from
# TUI-only builds (writhdeck-cli.tcl, writhdeck-jim.tcl, writhdeck-dos.tcl).
#
# A key is "common" if its name appears as a whole word anywhere in the files
# that are compiled into the TUI build; otherwise it is GUI-only.

set buildpaths {
    src/state.tcl src/config.tcl src/common.tcl src/analysis.tcl
    src/tui.tcl src/main-cli.tcl src/boot-cli.tcl
}
set hay ""
foreach f $buildpaths {
    set fh [open $f r]
    append hay [read $fh] "\n"
    close $fh
}

proc is_common {key} {
    global hay
    return [regexp "\\m$key\\M" $hay]
}

set gui_marker_open  "# >>> GUI-ONLY  (stripped from TUI/CLI builds by the Makefile - see CLAUDE.build.md)"
set gui_marker_close "# <<< GUI-ONLY"

set ncommon 0; set ngui 0
foreach f [lsort [glob src/i18n/*.tcl]] {
    set lang [file rootname [file tail $f]]
    set fh [open $f r]
    set lines [split [read $fh] "\n"]
    close $fh

    set common {}
    set gui {}
    foreach line $lines {
        if {[regexp {^\s*([a-zA-Z0-9_]+)\s+".*"\s*$} $line -> key]} {
            if {[is_common $key]} {
                lappend common $line
            } else {
                lappend gui $line
            }
        }
    }
    incr ncommon [llength $common]
    incr ngui [llength $gui]

    set out [open $f w]
    chan configure $out -encoding utf-8
    puts $out "dict set ::i18n $lang \{"
    foreach l $common { puts $out $l }
    puts $out "\}"
    puts $out $::gui_marker_open
    puts $out "dict set ::i18n_gui $lang \{"
    foreach l $gui { puts $out $l }
    puts $out "\}"
    puts $out $::gui_marker_close
    close $out
    puts "[file tail $f]: [llength $common] common + [llength $gui] gui"
}
puts "TOTAL: $ncommon common, $ngui gui (across [llength [glob src/i18n/*.tcl]] files)"
