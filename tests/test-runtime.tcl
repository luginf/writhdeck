#!/usr/bin/env tclsh
# Runtime checks for logical errors and missing definitions

set errors 0

# Load the full application
if {[catch {
    set fp [open writhdeck.tcl r]
    set content [read $fp]
    close $fp
    eval $content
} err]} {
    puts "ERROR: Failed to load writhdeck.tcl: $err"
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
    ::br_entries
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
    br-refresh
    do-backup
    toggle-favorite
    get-word-occurrences
    fmt-meta
    build-extra-entries
    apply-inline
    parse-heading
    heading-level
    markers-update
    theme-colors
}

foreach proc $required_procs {
    if {![llength [info procs $proc]]} {
        puts "ERROR: Missing procedure: $proc"
        incr errors
    }
}

# Verify INI file location is readable
if {![file readable [file dirname $::INI_FILE]]} {
    puts "WARNING: INI directory not readable: [file dirname $::INI_FILE]"
}

# Verify DOCS_DIR_DEFAULT exists or can be created
if {![file exists $::DOCS_DIR_DEFAULT]} {
    if {[catch {file mkdir $::DOCS_DIR_DEFAULT}]} {
        puts "WARNING: Cannot create DOCS_DIR_DEFAULT: $::DOCS_DIR_DEFAULT"
    }
}

# Check that HOME_DIR is absolute path
if {[file pathtype $::HOME_DIR] ne "absolute"} {
    puts "ERROR: HOME_DIR is not absolute: $::HOME_DIR"
    incr errors
}

# Check that key color variables are defined (if in GUI mode)
if {!$::no_gui} {
    set required_colors {
        ::bg ::fg ::bg_bar ::fg_bar ::bg_sel
    }
    foreach color $required_colors {
        if {![info exists $color]} {
            puts "ERROR: Missing color variable: $color"
            incr errors
        }
    }
}

# Verify i18n has at least English
if {![dict exists $::i18n en]} {
    puts "ERROR: Missing English translations in i18n"
    incr errors
}

# Report results
if {$errors == 0} {
    puts "✓ Runtime checks passed"
    exit 0
} else {
    puts "✗ Found $errors error(s)"
    exit 1
}
