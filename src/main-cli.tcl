# --- Development mode: auto-load modules if run directly from src/ ---
if {![info exists ::version]} {
    set srcdir [file dirname [info script]]
    foreach m {boot-cli state config common tui} {
        source [file join $srcdir $m.tcl]
    }
}

# --- CLI-only entry point (always TUI, never GUI) ---
tui-main
