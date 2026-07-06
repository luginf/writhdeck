#!/usr/bin/env tclsh
# Runtime checks for logical errors and missing definitions
#
# Loads writhdeck.tcl up to (but excluding) the main.tcl entry-point section,
# so no UI loop is started. HOME is redirected to a temp sandbox so the
# checks never touch the developer's real ~/Documents/writhdeck.

set errors 0

# --- sandbox HOME so state/INI/docs dirs are created in a temp dir ------------
set sandbox [file join [expr {[info exists ::env(TMPDIR)] ? $::env(TMPDIR) : "/tmp"}] \
    "writhdeck-test-runtime-[pid]"]
file mkdir $sandbox
set ::env(HOME) $sandbox
catch {unset ::env(COMP_LINE)}
catch {unset ::env(COMP_POINT)}

# Force TUI mode: avoids loading Tk (and hanging on a stale DISPLAY)
set ::argv {--no-gui}
set ::argc 1

# --- load the application without its entry point ------------------------------
if {[catch {
    set fp [open writhdeck.tcl r]
    set content [read $fp]
    close $fp
    # Cut just before the "# main.tcl" section header (start of the
    # dispatch code that would enter tui-main / build the Tk UI).
    set mi [string first "\n# main.tcl\n" $content]
    if {$mi < 0} { error "section header '# main.tcl' not found" }
    set cut [string last "\n# ===" $content $mi]
    if {$cut < 0} { set cut $mi }
    eval [string range $content 0 $cut]
} err]} {
    puts "ERROR: Failed to load writhdeck.tcl: $err"
    file delete -force $sandbox
    exit 1
}

# Required global variables
set required_globals {
    ::version
    ::HOME_DIR
    ::DOCS_DIR_DEFAULT
    ::DOCS_DIR
    ::INI_FILE
    ::FILE_EXT
    ::filename
    ::dirty
    ::cfg_font_family
    ::cfg_font_size
    ::cfg_scheme
    ::cfg_profile
    ::cfg_lang
    ::i18n
}

foreach var $required_globals {
    if {![info exists $var]} {
        puts "ERROR: Missing global variable: $var"
        incr errors
    }
}

# Required procedures (core functions)
set required_procs {
    state-load
    state-save
    ini-load
    ini-save
    tilde-expand
    list-docs
    br-dirs
    do-backup
    toggle-favorite
    get-word-occurrences
    fmt-meta
    build-extra-entries
    apply-inline
    parse-heading
    parse-comment
    parse-list
    heading-level
    markers-update
    status-build
    theme-colors
    tui-main
}

foreach p $required_procs {
    if {![llength [info procs $p]]} {
        puts "ERROR: Missing procedure: $p"
        incr errors
    }
}

# Sandbox HOME must have been picked up
if {$::HOME_DIR ne $sandbox} {
    puts "ERROR: HOME sandbox not honoured: HOME_DIR=$::HOME_DIR"
    incr errors
}

# Check that HOME_DIR is absolute path
if {[file pathtype $::HOME_DIR] ne "absolute"} {
    puts "ERROR: HOME_DIR is not absolute: $::HOME_DIR"
    incr errors
}

# DOCS_DIR_DEFAULT must exist (created at load time by state.tcl)
if {![file isdirectory $::DOCS_DIR_DEFAULT]} {
    puts "ERROR: DOCS_DIR_DEFAULT was not created: $::DOCS_DIR_DEFAULT"
    incr errors
}

# Verify i18n has at least English
if {![dict exists $::i18n en]} {
    puts "ERROR: Missing English translations in i18n"
    incr errors
}

# t proc must fall back to the key name for unknown keys
if {[t __no_such_key__] ne "__no_such_key__"} {
    puts "ERROR: t proc does not fall back to key name"
    incr errors
}

file delete -force $sandbox

# Report results
if {$errors == 0} {
    puts "OK: runtime checks passed"
    exit 0
} else {
    puts "FAIL: found $errors error(s)"
    exit 1
}
