# --- Development mode: auto-load modules if run directly from src/ ---
if {![info exists ::version]} {
    set srcdir [file dirname [info script]]
    foreach m {boot state config common tui} {
        source [file join $srcdir $m.tcl]
    }
    # Load GUI module only if not in TUI mode
    if {!$::no_gui} {
        source [file join $srcdir gui.tcl]
    }
}

# --- start --------------------------------------------------------------------
if {$::no_gui && $::tcl_platform(platform) eq "windows"} {
    # On Windows without Tk, show a helpful message in a console or dialog
    catch {
        package require Tk
        tk_messageBox -title "Writhdeck" \
            -message "Please run writhdeck.tcl with wish.exe, not tclsh.exe.\n\nExample:\n  wish.exe writhdeck.tcl" \
            -icon info
    } err
    if {$err ne ""} {
        puts stderr "writhdeck: please run with wish.exe, not tclsh.exe"
    }
    exit 1
}
if {$::no_gui} {
    tui-main
} else {
    if {$::tcl_platform(platform) eq "windows"} {
        proc bgerror {msg} {
            tk_messageBox -title "Writhdeck Error" -message $msg -icon error -type ok
        }
    }
    # if {[file exists "writhdeck.png"]} {
    #     catch { wm iconphoto . [image create photo -file "writhdeck.png"] }
    # }
    if {$::argc > 0} { show-editor [lindex $::argv 0] } else { show-browser }
    if {$::cfg_key_error ne ""} {
        after 100 [list set-msg "key conflict: $::cfg_key_error"]
    }
}
