# compat-dos.tcl - FreeDOS/NANSI.SYS display safety shim
# Included only in writhdeck-dos.tcl builds (make dos). Loaded after
# compat-jim.tcl (DOS uses the JimTcl interpreter).
#
# NANSI.SYS strips the '?'/'=' prefix of CSI private-mode sequences and
# treats the bare number as an SM/RM (set/reset mode) argument, mapping any
# unrecognized value to an int 10h "set video mode" BIOS call. This makes
# several sequences tui.tcl relies on actively destructive:
#   ESC[?5h / ESC[?5l   -> "set video mode 5"  (switches to CGA graphics!)
#   ESC[?25h / ESC[?25l -> "set video mode 25" (undefined, BIOS-dependent;
#                          also issued on every redraw)
#   ESC[?2004h/l        -> param overflows to 212 -> "set video mode 212"
#   ESC[N q             -> the space before 'q' is not a valid command char,
#                          so NANSI prints " q" as literal text on screen
# See writhdeck-dos/NOTES.md for the full analysis.
#
# This shim strips these sequences from anything written to stdout so the
# screen is never corrupted. Side effects:
#   - the console cursor is always visible (no hide/show)
#   - tui-reverse-video (global dark/light toggle) becomes a no-op; dark/
#     light mode must instead be handled via tui_colors fg/bg (see
#     writhdeck-dos/writhdeck.ini.sample)

# --- DOS-friendly paths (override boot-jim.tcl's ~/Documents/writhdeck) ----
# boot-jim.tcl set DOCS_DIR_DEFAULT = $HOME/Documents/writhdeck which has
# names exceeding DOS 8.3 limits.  Redirect everything to a DOCS/ sub-folder
# next to the running script (= the package directory), using short names.
# state.tcl (loaded after this file) re-derives STATE_FILE from DOCS_DIR_DEFAULT
# using the "msdosdjgpp" check added there; INI_FILE must be overridden here.
set ::DOCS_DIR_DEFAULT [file join [file dirname [info script]] DOCS]
set ::DOCS_DIR         $::DOCS_DIR_DEFAULT
set ::INI_FILE         [file join $::DOCS_DIR_DEFAULT WRITHDEC.INI]

# --- exec : disable entirely on DOS ----------------------------------------
# DJGPP's exec() needs C:\TMP for pipe temp files, which don't exist in the
# package.  Every failed attempt costs an expensive DPMI round-trip and
# prints "Warning: file creation failed: …TMP\TCxxxxxx.TMP" to the console.
# All exec calls in writhdeck are wrapped in catch (stty, xclip, ffplay…)
# so replacing exec with an immediate Tcl error is safe and eliminates both
# the warnings and the per-keystroke slowness from tui-size's stty probe.
proc exec {args} { error "exec: disabled on DOS" }

# --- chan configure : strip -blocking (no ndelay on DJGPP stdin) -----------
# compat-jim.tcl already strips -encoding; here we also strip -blocking.
# Under DOS jimsh, fconfigure maps -blocking to "$f ndelay N" which fails
# because the DJGPP console channel object has no ndelay method.
# Result: stdin always stays blocking -- keyboard reads block until a key
# comes, which is the normal DOS console behaviour anyway.
rename chan __chan_dos_base
proc chan {sub args} {
    if {$sub eq "configure"} {
        set ch [lindex $args 0]
        set opts {}
        set i 1
        while {$i < [llength $args]} {
            set opt [lindex $args $i]
            if {$opt eq "-encoding" || $opt eq "-blocking"} {
                incr i 2
            } else {
                lappend opts $opt
                incr i
            }
        }
        if {[llength $opts]} { catch { fconfigure $ch {*}$opts } }
    } else {
        __chan_dos_base $sub {*}$args
    }
}

rename puts __puts_dos

proc _dos_strip_ansi {str} {
    regsub -all {\x1b\[\?(5|25|2004)[hl]} $str "" str
    regsub -all {\x1b\[[0-9]* q} $str "" str
    return $str
}

proc puts {args} {
    set n [llength $args]
    if {$n == 2 && [lindex $args 0] eq "-nonewline"} {
        set str [lindex $args 1]
        if {[string first "\x1b" $str] >= 0} { set str [_dos_strip_ansi $str] }
        return [__puts_dos -nonewline $str]
    }
    if {$n == 3 && [lindex $args 0] eq "-nonewline" && [lindex $args 1] eq "stdout"} {
        set str [lindex $args 2]
        if {[string first "\x1b" $str] >= 0} { set str [_dos_strip_ansi $str] }
        return [__puts_dos -nonewline stdout $str]
    }
    __puts_dos {*}$args
}
