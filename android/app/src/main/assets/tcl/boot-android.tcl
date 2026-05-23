# boot-android.tcl — démarrage de l'interpréteur WrithDeck sur Android
# ::ANDROID_FILES_DIR est injecté par nativeInit() avant que ce script soit sourcé

set ::HOME_DIR          $::ANDROID_FILES_DIR
set ::DOCS_DIR_DEFAULT  [file join $::ANDROID_FILES_DIR "documents"]
set ::DOCS_DIR          $::DOCS_DIR_DEFAULT
set ::INI_FILE          [file join $::DOCS_DIR_DEFAULT "writhdeck.ini"]
set ::no_gui            1
set ::cfg_lang          "en"

proc tilde-expand {path} { return $path }

# Source order mirrors the generated writhdeck.tcl order
foreach _mod {state config} {
    set _f [file join $::ANDROID_FILES_DIR "tcl" "${_mod}.tcl"]
    if {[file exists $_f]} {
        source $_f
    } else {
        error "boot-android: module not found: $_f"
    }
}
unset _mod _f

# Crée le dossier documents/ avant ini-load — ini-save en a besoin pour écrire le .ini par défaut
file mkdir $::DOCS_DIR_DEFAULT

# Load user config — ini-load reads $::INI_FILE, creates it with defaults if absent
# keys-init converts cfg_key_* Tk names to TUI equivalents (needed for cfg_tui_*)
ini-load
keys-init

# State loading after all procs and config are in place
state-load

# ── Timer (piloté par tick Kotlin, pas par after) ──────────────────────────────

proc android-timer-start {} {
    if {$::cfg_timer_type eq "stopwatch"} {
        set ::timer_remaining 0
    } else {
        set ::timer_remaining [expr {$::cfg_timer_duration * 60}]
    }
    set ::timer_active 1
    set ::timer_last_tick [clock seconds]
    return "$::timer_active $::timer_remaining"
}

proc android-timer-pause {} {
    set ::timer_active 0
    return "$::timer_active $::timer_remaining"
}

proc android-timer-resume {} {
    set ::timer_active 1
    set ::timer_last_tick [clock seconds]
    return "$::timer_active $::timer_remaining"
}

proc android-timer-reset {} {
    set ::timer_active 0
    set ::timer_last_tick 0
    if {$::cfg_timer_type eq "stopwatch"} {
        set ::timer_remaining 0
    } else {
        set ::timer_remaining [expr {$::cfg_timer_duration * 60}]
    }
    return "$::timer_active $::timer_remaining"
}

# Appelé chaque seconde par Kotlin
proc android-timer-tick {} {
    if {!$::timer_active} { return "$::timer_active $::timer_remaining" }
    if {$::cfg_timer_type eq "stopwatch"} {
        incr ::timer_remaining
    } else {
        incr ::timer_remaining -1
        if {$::timer_remaining <= 0} {
            set ::timer_remaining 0
            set ::timer_active 0
        }
    }
    set ::timer_last_tick [clock seconds]
    return "$::timer_active $::timer_remaining"
}

# État initial pour init du ViewModel
proc android-timer-state {} {
    set rem [expr {
        $::timer_active || $::timer_last_tick != 0
            ? $::timer_remaining
            : ($::cfg_timer_type eq "stopwatch" ? 0 : $::cfg_timer_duration * 60)
    }]
    return "$::timer_active $rem $::timer_last_tick"
}

# ── Occurrences de mots (sur le texte en mémoire) ──────────────────────────────

proc android-word-occurrences {text} {
    set counts [dict create]
    foreach word [regexp -all -inline {\w+} [string tolower $text]] {
        if {[string length $word] > 2} { dict incr counts $word }
    }
    set pairs {}
    dict for {word count} $counts { lappend pairs [list $count $word] }
    set out ""
    foreach pair [lsort -integer -decreasing -index 0 $pairs] {
        append out "[lindex $pair 1]\t[lindex $pair 0]\n"
    }
    return $out
}

# ── Stats journalières ─────────────────────────────────────────────────────────

# Returns stats for filepath as newline-separated "date\twords" lines, newest first
proc android-get-stats {filepath words} {
    if {$filepath ne "" && $words > 0} {
        catch { daily-update $filepath $words }
        catch { state-save }
    }
    set result {}
    foreach entry $::state_daily {
        set parts [split $entry "\t"]
        if {[lindex $parts 0] ne $filepath} continue
        set pairs {}
        for {set i 1} {[expr {$i+1}] < [llength $parts]} {incr i 2} {
            lappend pairs [list [lindex $parts $i] [lindex $parts [expr {$i+1}]]]
        }
        set out ""
        foreach pair [lsort -decreasing -index 0 $pairs] {
            append out "[lindex $pair 0]\t[lindex $pair 1]\n"
        }
        return $out
    }
    return ""
}
