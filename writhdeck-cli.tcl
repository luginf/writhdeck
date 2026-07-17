#!/bin/sh
# sh/Tcl polyglot - backslash continues Tcl comment to next line, hiding shell bootstrap \
_w=$(stty -g 2>/dev/null); trap '[ -n "$_w" ] && stty "$_w" 2>/dev/null' EXIT INT TERM; tclsh "$0" "$@"; exit $?

# # # # # # # # # # # #
#
#     writhdeck.tcl (CLI-only build)
#
#  ~  Tcl/Tk 8.5+ (console/TUI) text editor for writerdecks ~
#
#     Usage: tclsh writhdeck-cli.tcl [filename]
#
#    https://github.com/luginf/writhdeck
#    -----------------------------
#    Copyright (C) 2026 by Luginfo
#
#    BSD Zero Clause License
#
#    Permission to use, copy, modify, and/or distribute this software
#    for any purpose with or without fee is hereby granted.
#
#    THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
#    WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES
#    OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE
#    FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
#    WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION
#    OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
#    OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
#
# # # # # # # # # # # #

set ::version          "v20260716"

# bail out immediately when invoked by bash tab-completion
if {[info exists ::env(COMP_LINE)] || [info exists ::env(COMP_POINT)]} { exit 0 }

if {[lsearch $::argv "--help"] >= 0 || [lsearch $::argv "-h"] >= 0} {
    puts "Usage: writhdeck-cli.tcl \[FILE\]

writhdeck CLI-only (TUI) mode. No GUI/Tk support.

Keyboard shortcuts (defaults - configurable in writhdeck.ini):
  ^S  Save              ^Z  Undo           ^Y  Redo
  ^Q  Close / Esc       ^F  Find           ^R  Find & Replace
  ^H  Help              ^G  Go to line     ^O  Open file
  ^A  Select all        ^K  Toggle sticky selection
  ^C  Copy              ^X  Cut            ^V  Paste
  ^L  Line numbers      ^D  Dark/light toggle
  ^Space  Next space    ^Shift+Space  Prev space"
    exit 0
}

set ::no_gui    1
set ::force_gui 0
foreach _f {--no-gui --tui --ng --cli --gui} { set ::argv [lsearch -all -inline -not $::argv $_f] }
unset _f
set ::argc [llength $::argv]

set ::HOME_DIR [expr {[info exists ::env(HOME)] ? $::env(HOME) : \
    ([info exists ::env(USERPROFILE)] ? $::env(USERPROFILE) : \
    [expr {![catch {file home} _h] ? $_h : [file normalize ~]}])}]

# Tcl 9 no longer expands ~ in file normalize; this proc handles it explicitly.
proc tilde-expand {path} {
    if {[string index $path 0] ne "~"} { return $path }
    if {$path eq "~" || [string index $path 1] eq "/"} {
        return $::HOME_DIR[string range $path 1 end]
    }
    return $path
}

set ::DOCS_DIR_DEFAULT [file join $::HOME_DIR Documents writhdeck]
  # set ::DOCS_DIR_DEFAULT "C:/Temp/writhdeck"       ;# Windows custom
  # set ::DOCS_DIR_DEFAULT "/tmp/writhdeck"         ;# Linux custom
set ::DOCS_DIR         $::DOCS_DIR_DEFAULT
set ::INI_FILE         [file join $::DOCS_DIR_DEFAULT "writhdeck.ini"]
set ::FILE_EXT ".txt"
set ::filename        ""
set ::dirty           0

# ===========================================================================
# state.tcl
# ===========================================================================
set ::msg             ""
set ::ed_msg          ""
set ::msg_after_id    ""
set ::scratchpad      0
set ::file_mtime_known 0
set ::watch_after_id  ""
set ::session_headings {}
set ::gui_cmd_mode    0
set ::tui_cmd_mode    0
set ::tui_cmd_idx     0

file mkdir $::DOCS_DIR_DEFAULT
set ::STATE_FILE [file join $::DOCS_DIR_DEFAULT ".writhdeck.json"]
set ::cursor_cache      {}
set ::favorites_list    {}
set ::recent_list       {}
set ::daily_data        {}
set ::session_file        ""
set ::session_baseline    -1
set ::session_max_today   0
set ::state_cache_valid   0

# --- state persistence (.writhdeck.json) --------------------------------------
# Format: {"cursors":{"path":[cy,cx],...},"favorites":[...],"recent":[...],"daily":["path\tdate\tN",...]}
proc state-parse-array {raw key} {
    set ri [string first "\"$key\"" $raw]
    if {$ri < 0} { return {} }
    set ai [string first "\[" $raw $ri]
    set ae [string first "\]" $raw [expr {$ai + 1}]]
    if {$ai < 0 || $ae < 0} { return {} }
    set sub [string range $raw [expr {$ai + 1}] [expr {$ae - 1}]]
    set result {}
    set re {"((?:[^"\\]|\\.)*)"}
    set start 0
    while {[regexp -start $start -indices $re $sub match item]} {
        set item_text [string range $sub {*}$item]
        lappend result $item_text
        set end [lindex $match 1]
        set start [expr {$end + 1}]
    }
    return $result
}

proc state-load {} {
    set ::cursor_cache   {}
    set ::favorites_list {}
    set ::recent_list    {}
    set ::daily_data     {}
    if {![file exists $::STATE_FILE]} { set ::state_cache_valid 1; return }
    set fh [open $::STATE_FILE r]; chan configure $fh -encoding utf-8
    set raw [read $fh]; close $fh
    set ci [string first "\"cursors\"" $raw]
    if {$ci >= 0} {
        set ob [string first "\{" $raw $ci]
        set cb [string first "\}" $raw [expr {$ob + 1}]]
        if {$ob >= 0 && $cb >= 0} {
            set sub [string range $raw [expr {$ob + 1}] [expr {$cb - 1}]]
            set re {"((?:[^"\\]|\\.)*)"\s*:\s*\[(\d+)\s*,\s*(\d+)\]}
            set start 0
            while {[regexp -start $start $re $sub -> key cy cx]} {
                set idx [string first "\"$key\"" $sub $start]
                set start [expr {$idx + [string length $key] + 2}]
                set key [string map [list {\\} "\\" {\"} "\""] $key]
                dict set ::cursor_cache $key [list [expr {int($cy)}] [expr {int($cx)}]]
            }
        }
    }
    foreach p [state-parse-array $raw "favorites"] {
        lappend ::favorites_list [file normalize [string map [list {\\} "\\" {\"} "\""] $p]]
    }
    foreach p [state-parse-array $raw "recent"] {
        lappend ::recent_list [file normalize [string map [list {\\} "\\" {\"} "\""] $p]]
    }
    set new_cache {}
    dict for {k v} $::cursor_cache { dict set new_cache [file normalize $k] $v }
    set ::cursor_cache $new_cache
    foreach item [state-parse-array $raw "daily"] {
        set item [string map [list {\\} "\\" {\"} "\"" {\t} "\t"] $item]
        set parts [split $item "\t"]
        if {[llength $parts] >= 3} {
            set fp [file normalize [lindex $parts 0]]
            if {![dict exists $::daily_data $fp]} { dict set ::daily_data $fp {} }
            for {set i 1} {$i + 1 < [llength $parts]} {incr i 2} {
                set date [lindex $parts $i]
                set cnt  [lindex $parts [expr {$i + 1}]]
                dict set ::daily_data $fp $date [expr {int($cnt)}]
            }
        }
    }
    set ::state_cache_valid 1
    daily-cleanup
}

proc state-save {} {
    set cp {}
    dict for {k v} $::cursor_cache {
        set ke [string map {\\ \\\\ \" \\\"} $k]
        lappend cp "\"$ke\":\[[lindex $v 0],[lindex $v 1]\]"
    }
    set fp {}
    foreach p $::favorites_list { lappend fp "\"[string map {\\ \\\\ \" \\\"} $p]\"" }
    set rp {}
    foreach p $::recent_list    { lappend rp "\"[string map {\\ \\\\ \" \\\"} $p]\"" }
    set dp {}
    dict for {fpath fdata} $::daily_data {
        set entry [string map {\\ \\\\ \" \\\"} $fpath]
        dict for {date cnt} $fdata {
            append entry "\\t${date}\\t${cnt}"
        }
        lappend dp "\"${entry}\""
    }
    set fh [open $::STATE_FILE w]; chan configure $fh -encoding utf-8
    puts $fh "\{"
    if {[llength $cp]} {
        puts $fh "\"cursors\":\{\n[join $cp ",\n"]\n\},"
    } else {
        puts $fh "\"cursors\":\{\},"
    }
    if {[llength $fp]} {
        puts $fh "\"favorites\":\[\n[join $fp ",\n"]\n\],"
    } else {
        puts $fh "\"favorites\":\[\],"
    }
    if {[llength $rp]} {
        puts $fh "\"recent\":\[\n[join $rp ",\n"]\n\],"
    } else {
        puts $fh "\"recent\":\[\],"
    }
    if {[llength $dp]} {
        puts $fh "\"daily\":\[\n[join $dp ",\n"]\n\]"
    } else {
        puts $fh "\"daily\":\[\]"
    }
    puts $fh "\}"
    close $fh
}

proc cursor-get {filepath} {
    if {!$::cfg_cursor_restore} { return {1 0} }
    set filepath [file normalize $filepath]
    if {!$::state_cache_valid} { state-load }
    if {[dict exists $::cursor_cache $filepath]} {
        lassign [dict get $::cursor_cache $filepath] cy cx
        return [list [expr {$cy + 1}] $cx]
    }
    return {1 0}
}

proc cursor-put {filepath cy cx} {
    if {!$::cfg_cursor_restore} return
    set filepath [file normalize $filepath]
    if {!$::state_cache_valid} { state-load }
    dict set ::cursor_cache $filepath [list [expr {$cy - 1}] $cx]
    state-save
}

# ===========================================================================
# config.tcl
# ===========================================================================

proc recent-push {path} {
    set path [file normalize $path]
    if {!$::state_cache_valid} { state-load }
    set ::recent_list [lsearch -all -inline -not -exact $::recent_list $path]
    set ::recent_list [linsert $::recent_list 0 $path]
    if {[llength $::recent_list] > 5} { set ::recent_list [lrange $::recent_list 0 4] }
    state-save
}

proc recent-remove {path} {
    set path [file normalize $path]
    if {!$::state_cache_valid} { state-load }
    set ::recent_list [lsearch -all -inline -not -exact $::recent_list $path]
    state-save
}

proc recent-rename {old new} {
    set old [file normalize $old]
    set new [file normalize $new]
    if {!$::state_cache_valid} { state-load }
    set changed 0
    set idx [lsearch -exact $::recent_list $old]
    if {$idx >= 0} { set ::recent_list [lreplace $::recent_list $idx $idx $new]; set changed 1 }
    set idx [lsearch -exact $::favorites_list $old]
    if {$idx >= 0} { set ::favorites_list [lreplace $::favorites_list $idx $idx $new]; set changed 1 }
    if {$changed} { state-save }
}

# --- daily writing stats ------------------------------------------------------
proc daily-open {filepath wc} {
    set filepath [file normalize $filepath]
    set ::session_file $filepath
    set today [clock format [clock seconds] -format "%Y-%m-%d"]
    if {!$::state_cache_valid} { state-load }
    set prior 0
    if {[dict exists $::daily_data $filepath] &&
        [dict exists [dict get $::daily_data $filepath] $today]} {
        set prior [dict get [dict get $::daily_data $filepath] $today]
    }
    set ::session_baseline  [expr {$wc - $prior}]
    set ::session_max_today $prior
}

proc daily-today {wc} {
    if {$::session_baseline < 0} { return 0 }
    set current [expr {max(0, $wc - $::session_baseline)}]
    if {$current > $::session_max_today} { set ::session_max_today $current }
    return $::session_max_today
}

proc daily-update {wc} {
    if {$::session_file eq "" || $::session_baseline < 0} return
    set today [clock format [clock seconds] -format "%Y-%m-%d"]
    set added [daily-today $wc]
    if {![dict exists $::daily_data $::session_file]} { dict set ::daily_data $::session_file {} }
    dict set ::daily_data $::session_file $today $added
    state-save
}

proc daily-cleanup {} {
    set today [clock format [clock seconds] -format "%Y-%m-%d"]
    set new_data {}
    dict for {fp fdata} $::daily_data {
        if {$fp in $::favorites_list} {
            dict set new_data $fp $fdata
        } else {
            if {[dict exists $fdata $today]} {
                dict set new_data $fp [dict create $today [dict get $fdata $today]]
            }
        }
    }
    set ::daily_data $new_data
}

proc daily-clear {filepath} {
    set filepath [file normalize $filepath]
    if {[dict exists $::daily_data $filepath]} {
        dict unset ::daily_data $filepath
    }
    state-save
}

# --- schemes (loaded from src/schemes/*.tcl) --------------------------------
set ::scheme_defs  {}

# --- ini ----------------------------------------------------------------------
set ::cfg_scheme   "default"
set ::cfg_schemes  {}
set ::cfg_profile  "default"
set ::cfg_profiles {}
set ::cfg_margin_width        60
set ::cfg_margin_height       40
set ::cfg_split_shrink_margin 1
set ::cfg_watch_file          1
set ::cfg_hemingway_mode      0
set ::cfg_font_size      13
set ::cfg_font_family    "Mono"
set ::cfg_bar_font_family "Mono"
set ::cfg_bg             "#1a1a1a"
set ::cfg_fg             "#e8e8e8"
set ::cfg_bg_bar         "#2a2a2a"
set ::cfg_fg_bar         "#aaaaaa"
set ::cfg_bg_sel         "#3a5a8a"
set ::cfg_docs_dir       ""
set ::cfg_browser_filter "*.txt *.t2t *.md *.ini"
set ::cfg_browser_show_all 0
set ::cfg_browser_subdirs 1
set ::cfg_repetition_scope   100
set ::cfg_repetition_min_len 4
set ::cfg_repetition_hidden  0
set ::cfg_spell_lang ""
set ::cfg_spell_highlight 0
set ::cfg_analysis_ignore_comments 0
set ::cfg_console_margin_cols    6
set ::cfg_console_margin_rows    4
set ::cfg_heading_marker    "="
set ::cfg_markdown_support  1
set ::cfg_color_heading  "#c8a060"
set ::cfg_comment_marker "%"
set ::cfg_color_comment  "#606060"
set ::cfg_bold_marker          "**"
set ::cfg_italic_marker        "//"
set ::cfg_underline_marker     "__"
set ::cfg_strikethrough_marker "--"
set ::cfg_color_markup         "#6aa9d4"
# alternate (light) theme - used when dark_mode = 0
set ::cfg_bg_alt             "#fdf6e3"
set ::cfg_fg_alt             "#657b83"
set ::cfg_bg_bar_alt         "#eee8d5"
set ::cfg_fg_bar_alt         "#93a1a1"
set ::cfg_bg_sel_alt         "#e6ddb9"
set ::cfg_color_heading_alt  "#b58900"
set ::cfg_color_comment_alt  "#aaaaaa"
set ::cfg_color_markup_alt   "#2a7090"
set ::cfg_bg2                "#1a1a1a"
set ::cfg_bg2_alt            "#fdf6e3"
# dark_mode: 0 = light (alt colors), 1 = dark (primary colors)
set ::cfg_dark_mode          1
set ::cfg_key_dark_toggle    "Control-d"
set ::cfg_browser              1
set ::cfg_console_center_alert 1
set ::cfg_line_numbers   0
set ::cfg_cursor_restore 1
set ::cfg_toc_pinned     0
set ::cfg_block_cursor_gui     1
set ::cfg_block_cursor_console 1
set ::cfg_blink_cursor         0
set ::cfg_line_spacing   100
set ::cfg_bar_height     18
set ::cfg_bar_show       1
set ::cfg_lang           "en"
set ::cfg_help_bar       "^S save   ^Q close   F10 workspace   ^H help"
set ::cfg_word_goal      500
# status bar zones - tokens: filename dirty sel ln col words chars goal clock help_bar space
set ::cfg_status_left   "workspace filename dirty sel ln col words chars"
set ::cfg_status_center ""
set ::cfg_status_right  "help_bar clock"
# shortcuts (Tk key names)
set ::cfg_key_save         "Control-s"
set ::cfg_key_save_as      "Control-S"
set ::cfg_key_close        "Control-q"
set ::cfg_key_find         "Control-f"
set ::cfg_key_replace      "Control-r"
set ::cfg_key_help         "Control-h"
set ::cfg_key_goto         "Control-g"
set ::cfg_key_open         "Control-o"
set ::cfg_key_undo         "Control-z"
set ::cfg_key_copy         "Control-c"
set ::cfg_key_cut          "Control-x"
set ::cfg_key_paste        "Control-v"
set ::cfg_key_select_all   "Control-a"
set ::cfg_key_sticky_sel   "Control-k"
set ::cfg_key_toc          "F11"
set ::cfg_key_toc_pinned   "Control-Shift-F11"
set ::cfg_key_line_numbers "Control-l"
set ::cfg_key_redo         "Control-y"
set ::cfg_key_typewriter   "Control-t"
set ::cfg_key_fullscreen   "Alt-Return"
set ::cfg_key_split        "F3"
set ::cfg_key_split_focus  "F4"
set ::cfg_key_workspace    "F10"
set ::cfg_key_timer        "Alt-t"
set ::cfg_key_cmd_mode     "Escape"
set ::cfg_key_error        ""
set ::cfg_timer_duration   25
set ::cfg_timer_sound      1
set ::cfg_timer_alert      1
set ::cfg_chrono_show      1
set ::cfg_timer_type       "countdown"
# TUI colors - enabled = 1 by default
set ::cfg_tui_colors       1
set ::cfg_tui_256colors    0
set ::cfg_tui_col_heading  "red"
set ::cfg_tui_col_comment  "bright_black"
set ::cfg_tui_col_markup   "green"
set ::cfg_tui_col_bar_fg   "black"
set ::cfg_tui_col_bar_bg   "yellow"
set ::cfg_tui_col_sel_bg   ""
set ::timer_active         0
set ::timer_remaining      0
set ::timer_last_tick      0
set ::timer_schedule_id    ""
set ::timer_alert_shown    0
set ::cfg_autosave_enabled  1
set ::cfg_autosave_interval 1
set ::autosave_last_time    0
set ::autosave_schedule_id  ""
set ::fullscreen 0
set ::split_mode 0
# workspace state (WS1 = primary, WS2 = secondary toggled via cfg_key_workspace)
set ::ws_n           1
set ::ws_dual_mode   0
set ::ws1_filename   ""
set ::ws1_scratchpad 0
set ::ws1_dirty      0
set ::ws1_content    ""
set ::ws1_cursor     "1.0"
set ::ws1_file_mtime 0
set ::ws2_filename   ""
set ::ws2_scratchpad 1
set ::ws2_dirty      0
set ::ws2_content    ""
set ::ws2_cursor     "1.0"
set ::ws2_file_mtime 0
set ::split_ws2_mode 0

proc marker-val {v} { expr {$v eq "0" ? "" : $v} }

proc timer-alert {} {
    if {$::timer_alert_shown} return
    set ::timer_alert_shown 1
    if {!$::no_gui} {
        if {$::cfg_timer_sound} { catch { timer-alert-gui } }
    } else {
        if {$::cfg_timer_sound} { do-beep }
        if {$::cfg_timer_alert} { catch { tui-timer-alert } }
    }
}

proc timer-tick {} {
    if {!$::timer_active} return
    if {$::cfg_timer_type eq "countdown" && $::timer_remaining <= 0} return
    set now [clock seconds]
    if {$::timer_last_tick == 0} {
        set ::timer_last_tick $now
        return
    }
    if {$now > $::timer_last_tick} {
        if {$::cfg_timer_type eq "countdown"} {
            incr ::timer_remaining -[expr {$now - $::timer_last_tick}]
            if {$::timer_remaining < 0} { set ::timer_remaining 0 }
            if {$::timer_remaining == 0 && $::cfg_timer_alert} {
                timer-alert
            }
        } else {
            incr ::timer_remaining [expr {$now - $::timer_last_tick}]
        }
        set ::timer_last_tick $now
        if {!$::no_gui} { catch {ed-status} }
    }
}

proc timer-schedule {} {
    if {$::timer_active && $::cfg_chrono_show} {
        set ::timer_schedule_id [after 1000 timer-schedule-tick]
    } else {
        if {$::timer_schedule_id ne ""} {
            catch {after cancel $::timer_schedule_id}
            set ::timer_schedule_id ""
        }
    }
}

proc timer-schedule-tick {} {
    timer-tick
    timer-schedule
}

proc timer-start {} {
    if {$::cfg_timer_type eq "countdown"} {
        set ::timer_remaining [expr {$::cfg_timer_duration * 60}]
    } else {
        set ::timer_remaining 0
    }
    set ::timer_active 1
    set ::timer_alert_shown 0
    set ::timer_last_tick [clock seconds]
    timer-schedule
}

proc timer-pause {} {
    set ::timer_active 0
    if {$::timer_schedule_id ne ""} {
        catch {after cancel $::timer_schedule_id}
        set ::timer_schedule_id ""
    }
}

proc timer-resume {} {
    set ::timer_active 1
    set ::timer_alert_shown 0
    set ::timer_last_tick [clock seconds]
    timer-schedule
}

proc timer-reset {} {
    set ::timer_active 0
    if {$::cfg_timer_type eq "countdown"} {
        set ::timer_remaining [expr {$::cfg_timer_duration * 60}]
    } else {
        set ::timer_remaining 0
    }
    set ::timer_last_tick 0
    if {$::timer_schedule_id ne ""} {
        catch {after cancel $::timer_schedule_id}
        set ::timer_schedule_id ""
    }
    if {!$::no_gui} { catch {ed-status} }
}

proc profile-apply {name} {
    if {![dict exists $::cfg_profiles $name]} return
    set d [dict get $::cfg_profiles $name]
    foreach {key var} {
        margin_width     ::cfg_margin_width
        margin_height    ::cfg_margin_height
        font_size        ::cfg_font_size
        font_family      ::cfg_font_family
        bar_font_family  ::cfg_bar_font_family
        line_spacing     ::cfg_line_spacing
        bar_height       ::cfg_bar_height
        word_goal        ::cfg_word_goal
        lang             ::cfg_lang
        line_numbers     ::cfg_line_numbers
        status_left      ::cfg_status_left
        status_center    ::cfg_status_center
        status_right     ::cfg_status_right
        help_bar         ::cfg_help_bar
    } {
        if {[dict exists $d $key]} { set $var [dict get $d $key] }
    }
    foreach {key var} {
        dark_mode        ::cfg_dark_mode
        block_cursor_gui ::cfg_block_cursor_gui
        blink_cursor     ::cfg_blink_cursor
    } {
        if {[dict exists $d $key]} { set $var [string is true [dict get $d $key]] }
    }
    set ::cfg_profile $name
}

proc scheme-apply {name} {
    if {![dict exists $::cfg_schemes $name]} return
    set d [dict get $::cfg_schemes $name]
    foreach {key var} {
        color_bg          ::cfg_bg
        color_fg          ::cfg_fg
        color_bg_bar      ::cfg_bg_bar
        color_fg_bar      ::cfg_fg_bar
        color_bg_sel      ::cfg_bg_sel
        color_heading     ::cfg_color_heading
        color_comment     ::cfg_color_comment
        color_markup      ::cfg_color_markup
        color_bg_alt      ::cfg_bg_alt
        color_fg_alt      ::cfg_fg_alt
        color_bg_bar_alt  ::cfg_bg_bar_alt
        color_fg_bar_alt  ::cfg_fg_bar_alt
        color_bg_sel_alt  ::cfg_bg_sel_alt
        color_heading_alt ::cfg_color_heading_alt
        color_comment_alt ::cfg_color_comment_alt
        color_markup_alt  ::cfg_color_markup_alt
        color_bg2         ::cfg_bg2
        color_bg2_alt     ::cfg_bg2_alt
    } {
        if {[dict exists $d $key]} { set $var [dict get $d $key] }
    }
    if {![dict exists $d color_bg2]}     { set ::cfg_bg2     $::cfg_bg }
    if {![dict exists $d color_bg2_alt]} { set ::cfg_bg2_alt $::cfg_bg_alt }
}

proc ini-load {} {
    # Repertoire de LANCEMENT (celui d'ou la commande est executee, [pwd] --
    # PAS celui ou reside writhdeck.tcl, [file dirname [info script]]) :
    # si l'un de ces noms courts y existe, il prend le pas sur
    # l'emplacement fixe habituel ($::INI_FILE, deja possiblement
    # redirige par compat-dos.tcl vers WRITHDEC.INI a cote du script).
    # Utile sur un support a noms de fichiers limites (FAT 8.3) ou quand
    # DOCS_DIR_DEFAULT n'est pas accessible/pertinent (ex. disquette de
    # boot). Premier trouve gagne, dans cet ordre.
    foreach _cand {writhdec.ini writhd.ini wrid.ini writhdeck.ini} {
        set _p [file join [pwd] $_cand]
        if {[file exists $_p]} { set ::INI_FILE $_p; break }
    }
    unset _cand _p

    if {![file exists $::INI_FILE]} { ini-save; return }
    set fh [open $::INI_FILE r]
    chan configure $fh -encoding utf-8
    set section     ""
    set cur_scheme  ""
    set cur_profile ""
    set toplevel    {editor behaviour keys}
    while {[gets $fh line] >= 0} {
        set line [string trim $line]
        if {$line eq "" || [string match "#*" $line] || [string match "%*" $line]} continue
        # section header
        if {[regexp {^\[(\w+)\]$} $line -> hdr]} {
            if {$hdr eq "schemes"} {
                set section "schemes"
                set cur_scheme ""
                set cur_profile ""
            } elseif {$hdr eq "profiles"} {
                set section "profiles"
                set cur_profile ""
                set cur_scheme ""
            } elseif {$section eq "schemes" && $hdr ni $toplevel} {
                set cur_scheme $hdr
            } elseif {$section eq "profiles" && $hdr ni $toplevel} {
                set cur_profile $hdr
            } else {
                set section $hdr
                set cur_scheme ""
                set cur_profile ""
            }
            continue
        }
        if {[regexp {^(\w+)\s*=(.*)$} $line -> key val]} {
            set v [regsub {\s+[#%].*$} [string trim $val] {}]
            # inside a named scheme block - store in dict
            if {$cur_scheme ne ""} {
                dict set ::cfg_schemes $cur_scheme $key $v
                continue
            }
            # inside a named profile block - store in dict
            if {$cur_profile ne ""} {
                dict set ::cfg_profiles $cur_profile $key $v
                continue
            }
            switch [string trim $key] {
                scheme           { set ::cfg_scheme          $v }
                profile          { set ::cfg_profile         $v }
                margin_width          { set ::cfg_margin_width        $v }
                margin_height         { set ::cfg_margin_height       $v }
                split_shrink_margin   { set ::cfg_split_shrink_margin [string is true $v] }
                watch_file            { set ::cfg_watch_file          [string is true $v] }
                hemingway_mode        { set ::cfg_hemingway_mode      [string is true $v] }
                font_size        { set ::cfg_font_size      $v }
                font_family      { set ::cfg_font_family    $v }
                bar_font_family  { set ::cfg_bar_font_family $v }
                color_bg         { set ::cfg_bg             $v }
                color_fg         { set ::cfg_fg             $v }
                color_bg_bar     { set ::cfg_bg_bar         $v }
                color_fg_bar     { set ::cfg_fg_bar         $v }
                docs_dir         { set ::cfg_docs_dir       $v }
                console_margin_cols  { set ::cfg_console_margin_cols $v }
                console_margin_rows  { set ::cfg_console_margin_rows $v }
                margin_cols          { set ::cfg_console_margin_cols $v }
                margin_rows          { set ::cfg_console_margin_rows $v }
                color_bg_sel     { set ::cfg_bg_sel         $v }
                heading_marker      { set ::cfg_heading_marker    $v }
                markdown_support   { set ::cfg_markdown_support [string is true $v] }
                markdown_headings  { set ::cfg_markdown_support [string is true $v] }
                color_heading    { set ::cfg_color_heading   $v }
                dim_marker       { set ::cfg_comment_marker  [marker-val $v] }
                comment_marker   { set ::cfg_comment_marker  [marker-val $v] }
                bold_marker          { set ::cfg_bold_marker          [marker-val $v] }
                italic_marker        { set ::cfg_italic_marker        [marker-val $v] }
                underline_marker     { set ::cfg_underline_marker     [marker-val $v] }
                strikethrough_marker { set ::cfg_strikethrough_marker [marker-val $v] }
                color_dim            { set ::cfg_color_comment        $v }
                color_comment        { set ::cfg_color_comment        $v }
                color_markup         { set ::cfg_color_markup         $v }
                color_bg_alt         { set ::cfg_bg_alt            $v }
                color_fg_alt         { set ::cfg_fg_alt            $v }
                color_bg_bar_alt     { set ::cfg_bg_bar_alt        $v }
                color_fg_bar_alt     { set ::cfg_fg_bar_alt        $v }
                color_bg_sel_alt     { set ::cfg_bg_sel_alt        $v }
                color_heading_alt    { set ::cfg_color_heading_alt  $v }
                color_dim_alt        { set ::cfg_color_comment_alt  $v }
                color_comment_alt    { set ::cfg_color_comment_alt  $v }
                color_markup_alt     { set ::cfg_color_markup_alt   $v }
                color_bg2            { set ::cfg_bg2               $v }
                color_bg2_alt        { set ::cfg_bg2_alt           $v }
                word_goal            { set ::cfg_word_goal            $v }
                dark_mode            { set ::cfg_dark_mode [string is true $v] }
                key_dark_toggle      { set ::cfg_key_dark_toggle   $v }
                browser              { set ::cfg_browser              [string is true $v] }
                browser_filter       { set ::cfg_browser_filter       $v }
                browser_show_all     { set ::cfg_browser_show_all     [string is true $v] }
                browser_subdirs      { set ::cfg_browser_subdirs      [string is true $v] }
                repetition_scope     { set ::cfg_repetition_scope     $v }
                repetition_min_len   { set ::cfg_repetition_min_len   $v }
                repetition_hidden    { set ::cfg_repetition_hidden    [string is true $v] }
                spell_lang           { set ::cfg_spell_lang           $v }
                spell_highlight      { set ::cfg_spell_highlight      [string is true $v] }
                analysis_ignore_comments { set ::cfg_analysis_ignore_comments [string is true $v] }
                console_center_alert { set ::cfg_console_center_alert [string is true $v] }
                line_numbers     { set ::cfg_line_numbers   [string is true $v] }
                cursor_restore   { set ::cfg_cursor_restore [string is true $v] }
                toc_pinned       { set ::cfg_toc_pinned    [string is true $v] }
                block_cursor         { set ::cfg_block_cursor_gui     [string is true $v]
                                       set ::cfg_block_cursor_console [string is true $v] }
                block_cursor_gui     { set ::cfg_block_cursor_gui     [string is true $v] }
                block_cursor_console { set ::cfg_block_cursor_console [string is true $v] }
                blink_cursor         { set ::cfg_blink_cursor         [string is true $v] }
                line_spacing     { set ::cfg_line_spacing   $v }
                bar_height       { set ::cfg_bar_height     $v }
                bar              { set ::cfg_bar_show       [string is true $v] }
                lang             { set ::cfg_lang           $v }
                help_bar         { set ::cfg_help_bar       $v }
                status_left      { set ::cfg_status_left    $v }
                status_center    { set ::cfg_status_center  $v }
                status_right     { set ::cfg_status_right   $v }
                key_save         { set ::cfg_key_save         $v }
                key_save_as      { set ::cfg_key_save_as      $v }
                key_close        { set ::cfg_key_close        $v }
                key_find         { set ::cfg_key_find         $v }
                key_replace      { set ::cfg_key_replace      $v }
                key_help         { set ::cfg_key_help         $v }
                key_goto         { set ::cfg_key_goto         $v }
                key_open         { set ::cfg_key_open         $v }
                key_undo         { set ::cfg_key_undo         $v }
                key_copy         { set ::cfg_key_copy         $v }
                key_cut          { set ::cfg_key_cut          $v }
                key_paste        { set ::cfg_key_paste        $v }
                key_select_all   { set ::cfg_key_select_all   $v }
                key_sticky_sel   { set ::cfg_key_sticky_sel   $v }
                key_toc          { set ::cfg_key_toc          $v }
                key_toc_pinned   { set ::cfg_key_toc_pinned   $v }
                key_line_numbers { set ::cfg_key_line_numbers $v }
                key_redo         { set ::cfg_key_redo         $v }
                key_typewriter   { set ::cfg_key_typewriter   $v }
                key_fullscreen   { set ::cfg_key_fullscreen   $v }
                key_split        { set ::cfg_key_split        $v }
                key_split_focus  { set ::cfg_key_split_focus  $v }
                key_workspace    { set ::cfg_key_workspace    $v }
                key_timer        { set ::cfg_key_timer        $v }
                key_cmd_mode     { set ::cfg_key_cmd_mode     $v }
                toc_key          { set ::cfg_key_toc          $v }
                ln_key           { set ::cfg_key_line_numbers $v }
                fullscreen_key   { set ::cfg_key_fullscreen   $v }
                timer_duration   { set ::cfg_timer_duration   $v }
                timer_sound      { set ::cfg_timer_sound      [string is true $v] }
                timer_alert      { set ::cfg_timer_alert      [string is true $v] }
                timer_type       { set ::cfg_timer_type       $v }
                chrono_show      { set ::cfg_chrono_show      [string is true $v] }
                tui_colors       { set ::cfg_tui_colors       [string is true $v] }
                tui_256colors    { set ::cfg_tui_256colors    [string is true $v] }
                tui_col_heading  { set ::cfg_tui_col_heading  $v }
                tui_col_comment  { set ::cfg_tui_col_comment  $v }
                tui_col_markup   { set ::cfg_tui_col_markup   $v }
                tui_col_bar_fg   { set ::cfg_tui_col_bar_fg   $v }
                tui_col_bar_bg   { set ::cfg_tui_col_bar_bg   $v }
                tui_col_sel_bg   { set ::cfg_tui_col_sel_bg   $v }
                autosave_enabled  { set ::cfg_autosave_enabled  [string is true $v] }
                autosave_interval { set ::cfg_autosave_interval $v }
            }
        }
    }
    close $fh
    profile-apply $::cfg_profile
    scheme-apply $::cfg_scheme
}

proc ini-save {} {
    set fh [open $::INI_FILE w]
    chan configure $fh -encoding utf-8
    puts $fh "= WrithDeck configuration ="
    puts $fh "% https://github.com/luginf/writhdeck"
    puts $fh ""
    puts $fh "= editor ="
    puts $fh "\[editor\]"
    puts $fh "profile        = $::cfg_profile"
    puts $fh "scheme         = $::cfg_scheme"
    if {$::cfg_docs_dir ne ""} {
        puts $fh "docs_dir       = $::cfg_docs_dir"
    } else {
        puts $fh "% docs_dir = ~/Documents/writerdeck"
    }
    puts $fh "% (main default document and conf folder: ~/Documents/writhdeck)"
    puts $fh "console_margin_cols = $::cfg_console_margin_cols"
    puts $fh "console_margin_rows = $::cfg_console_margin_rows"
    puts $fh ""
    puts $fh "heading_marker       = $::cfg_heading_marker"
    puts $fh "comment_marker       = $::cfg_comment_marker"
    puts $fh "bold_marker          = $::cfg_bold_marker"
    puts $fh "italic_marker        = $::cfg_italic_marker"
    puts $fh "underline_marker     = $::cfg_underline_marker"
    puts $fh "strikethrough_marker = $::cfg_strikethrough_marker"
    puts $fh ""
    puts $fh "= behaviour ="
    puts $fh "\[behaviour\]"
    puts $fh "browser              = [expr {$::cfg_browser              ? "yes" : "no"}]"
    puts $fh "% browser_filter: space-separated glob patterns for files shown in the browser"
    puts $fh "% (empty = show all files)"
    puts $fh "browser_filter       = $::cfg_browser_filter"
    puts $fh "% browser_show_all: bypass browser_filter and show all files"
    puts $fh "browser_show_all     = [expr {$::cfg_browser_show_all     ? "yes" : "no"}]"
    puts $fh "% browser_subdirs: scan and browse subfolders inside document folders"
    puts $fh "browser_subdirs      = [expr {$::cfg_browser_subdirs      ? "yes" : "no"}]"
    puts $fh "% repetition_scope: word distance (each direction) checked by the repetition tool"
    puts $fh "repetition_scope     = $::cfg_repetition_scope"
    puts $fh "% repetition_min_len: minimum word length for hidden-substring repetition checks"
    puts $fh "repetition_min_len   = $::cfg_repetition_min_len"
    puts $fh "% repetition_hidden: also flag hidden-substring repetitions (e.g. 'tour' in 'alentours')"
    puts $fh "repetition_hidden    = [expr {$::cfg_repetition_hidden    ? "yes" : "no"}]"
    puts $fh "% spell_lang: hunspell dictionary name (e.g. fr_FR); empty = derive from 'lang'"
    puts $fh "spell_lang           = $::cfg_spell_lang"
    puts $fh "% spell_highlight: underline misspelled words (visible lines only) in the editor"
    puts $fh "spell_highlight      = [expr {$::cfg_spell_highlight ? "yes" : "no"}]"
    puts $fh "% analysis_ignore_comments: skip commented lines (cfg_comment_marker) in spellcheck, repetitions, word occurrences"
    puts $fh "analysis_ignore_comments = [expr {$::cfg_analysis_ignore_comments ? "yes" : "no"}]"
    puts $fh "watch_file           = [expr {$::cfg_watch_file           ? "yes" : "no"}]"
    puts $fh "hemingway_mode       = [expr {$::cfg_hemingway_mode       ? "yes" : "no"}]"
    puts $fh "%   markdown_headings is a deprecated alias for markdown_support (kept for now)"
    puts $fh "markdown_headings    = [expr {$::cfg_markdown_support     ? "yes" : "no"}]"
    puts $fh "markdown_support     = [expr {$::cfg_markdown_support     ? "yes" : "no"}]"
    puts $fh "split_shrink_margin  = [expr {$::cfg_split_shrink_margin  ? "yes" : "no"}]"
    puts $fh "console_center_alert = [expr {$::cfg_console_center_alert ? "yes" : "no"}]"
    puts $fh "% bar: show the editor status bar (no = hide it; the browser bar is unaffected; search field and ESC menu still appear, sized by bar_height)"
    puts $fh "bar                  = [expr {$::cfg_bar_show            ? "yes" : "no"}]"
    puts $fh "line_numbers         = [expr {$::cfg_line_numbers         ? "yes" : "no"}]"
    puts $fh "cursor_restore       = [expr {$::cfg_cursor_restore       ? "yes" : "no"}]"
    puts $fh "toc_pinned           = [expr {$::cfg_toc_pinned           ? "yes" : "no"}]"
    puts $fh "block_cursor_gui     = [expr {$::cfg_block_cursor_gui     ? "yes" : "no"}]"
    puts $fh "block_cursor_console = [expr {$::cfg_block_cursor_console ? "yes" : "no"}]"
    puts $fh "blink_cursor         = [expr {$::cfg_blink_cursor         ? "yes" : "no"}]"
    puts $fh "% lang: interface language - en fr de es ko no"
    puts $fh "lang           = $::cfg_lang"
    puts $fh "% help_bar: text shown in the shortcuts bar, empty to hide"
    puts $fh "help_bar       = $::cfg_help_bar"
    puts $fh "% word_goal: target word count shown in status bar with 'goal' token (0 = disabled)"
    puts $fh "word_goal      = $::cfg_word_goal"
    puts $fh "% status bar zones - tokens: filename dirty sel ln col words chars goal clock timer help_bar space"
    puts $fh "status_left    = $::cfg_status_left"
    puts $fh "status_center  = $::cfg_status_center"
    puts $fh "status_right   = $::cfg_status_right"
    puts $fh "dark_mode      = [expr {$::cfg_dark_mode ? "yes" : "no"}]"
    puts $fh "= timer ="
    puts $fh "timer_duration = $::cfg_timer_duration"
    puts $fh "timer_sound    = [expr {$::cfg_timer_sound  ? "yes" : "no"}]"
    puts $fh "timer_alert    = [expr {$::cfg_timer_alert  ? "yes" : "no"}]"
    puts $fh "timer_type     = $::cfg_timer_type"
    puts $fh "chrono_show    = [expr {$::cfg_chrono_show  ? "yes" : "no"}]"
    puts $fh ""
    puts $fh "= misc ="
    puts $fh "\[misc\]"
    puts $fh "autosave_enabled  = [expr {$::cfg_autosave_enabled  ? "yes" : "no"}]"
    puts $fh "autosave_interval = $::cfg_autosave_interval"
    puts $fh ""
    puts $fh "= tui_colors ="
    puts $fh "\[tui_colors\]"
    puts $fh "% TUI color palette"
    puts $fh "% Named colors: black red green yellow blue magenta cyan white"
    puts $fh "%               bright_black bright_red bright_green bright_yellow"
    puts $fh "%               bright_blue bright_magenta bright_cyan bright_white"
    puts $fh "% With tui_256colors = yes: also accepts numeric values 0-255"
    puts $fh "% Set tui_colors = yes to enable"
    puts $fh "tui_colors      = [expr {$::cfg_tui_colors    ? "yes" : "no"}]"
    puts $fh "% tui_256colors: use ANSI 256-color codes (brights distinct, numeric 0-255 accepted)"
    puts $fh "tui_256colors   = [expr {$::cfg_tui_256colors ? "yes" : "no"}]"
    puts $fh "tui_col_heading = $::cfg_tui_col_heading"
    puts $fh "tui_col_comment = $::cfg_tui_col_comment"
    puts $fh "tui_col_markup  = $::cfg_tui_col_markup"
    puts $fh "tui_col_bar_fg  = $::cfg_tui_col_bar_fg"
    puts $fh "tui_col_bar_bg  = $::cfg_tui_col_bar_bg"
    puts $fh "% tui_col_sel_bg: selection background color (empty = reverse video)"
    puts $fh "tui_col_sel_bg  = $::cfg_tui_col_sel_bg"
    puts $fh "% example warm palette for tui_256colors = yes:"
    puts $fh "%   tui_col_heading = 214   % amber  #ffaf00"
    puts $fh "%   tui_col_comment = 136   % dark amber  #af8700"
    puts $fh "%   tui_col_markup  = 172   % orange-brown  #d78700"
    puts $fh "%   tui_col_bar_fg  = 220   % gold  #ffd700"
    puts $fh "%   tui_col_bar_bg  = 94    % dark brown  #875f00"
    puts $fh "%   tui_col_sel_bg  = 52    % dark burgundy  #5f0000"
    puts $fh ""
    puts $fh "= keys ="
    puts $fh "\[keys\]"
    puts $fh "% Use Tk key names: Control-s, Alt-Return, F11, etc."
    puts $fh "key_save         = $::cfg_key_save"
    puts $fh "key_save_as      = $::cfg_key_save_as"
    puts $fh "key_close        = $::cfg_key_close"
    puts $fh "key_find         = $::cfg_key_find"
    puts $fh "key_replace      = $::cfg_key_replace"
    puts $fh "key_help         = $::cfg_key_help"
    puts $fh "key_goto         = $::cfg_key_goto"
    puts $fh "key_open         = $::cfg_key_open"
    puts $fh "key_undo         = $::cfg_key_undo"
    puts $fh "key_copy         = $::cfg_key_copy"
    puts $fh "key_cut          = $::cfg_key_cut"
    puts $fh "key_paste        = $::cfg_key_paste"
    puts $fh "key_select_all   = $::cfg_key_select_all"
    puts $fh "key_sticky_sel   = $::cfg_key_sticky_sel"
    puts $fh "key_toc          = $::cfg_key_toc"
    puts $fh "key_toc_pinned   = $::cfg_key_toc_pinned"
    puts $fh "key_line_numbers = $::cfg_key_line_numbers"
    puts $fh "key_redo         = $::cfg_key_redo"
    puts $fh "key_typewriter   = $::cfg_key_typewriter"
    puts $fh "key_fullscreen   = $::cfg_key_fullscreen"
    puts $fh "key_split        = $::cfg_key_split"
    puts $fh "key_split_focus  = $::cfg_key_split_focus"
    puts $fh "key_workspace    = $::cfg_key_workspace"
    puts $fh "key_timer        = $::cfg_key_timer"
    puts $fh "key_dark_toggle  = $::cfg_key_dark_toggle"
    puts $fh "key_cmd_mode     = $::cfg_key_cmd_mode"
    puts $fh ""
    puts $fh "= profiles ="
    puts $fh "\[profiles\]"
    puts $fh {% Each [name] block defines a profile (display, behaviour and status bar settings).}
    puts $fh {% Select the active profile with:  profile = <name>  in [editor]}
    puts $fh ""

    # Add "roman" example profile if not already defined
    if {![dict exists $::cfg_profiles roman]} {
        puts $fh "== roman =="
        puts $fh "\[roman\]"
        puts $fh "margin_width    = 180"
        puts $fh "margin_height   = 80"
        puts $fh "font_size       = 18"
        puts $fh "font_family     = Noto Serif"
        puts $fh "line_spacing    = 110"
        puts $fh "bar_height      = 20"
        puts $fh "word_goal       = 1000"
        puts $fh ""
    }

    # Write all profiles including "default" from the dictionary
    foreach pname [dict keys $::cfg_profiles] {
        puts $fh "= $pname ="
        puts $fh "\[$pname\]"
        set d [dict get $::cfg_profiles $pname]
        foreach key {margin_width margin_height
                     font_size font_family bar_font_family line_spacing bar_height
                     word_goal dark_mode lang block_cursor_gui blink_cursor line_numbers
                     status_left status_center status_right help_bar} {
            if {[dict exists $d $key]} {
                puts $fh "$key = [dict get $d $key]"
            }
        }
        puts $fh ""
    }

    # Also write defaults from global variables for backwards compatibility
    if {![dict exists $::cfg_profiles default]} {
        puts $fh "== default =="
        puts $fh "\[default\]"
        puts $fh "margin_width    = $::cfg_margin_width"
        puts $fh "margin_height   = $::cfg_margin_height"
        puts $fh "font_size       = $::cfg_font_size"
        puts $fh "font_family     = $::cfg_font_family"
        puts $fh "bar_font_family = $::cfg_bar_font_family"
        puts $fh "line_spacing    = $::cfg_line_spacing"
        puts $fh "bar_height      = $::cfg_bar_height"
        puts $fh "word_goal       = $::cfg_word_goal"
        puts $fh ""
    }
    puts $fh ""
    puts $fh "= schemes ="
    puts $fh "\[schemes\]"
    puts $fh {% Each [name] block defines a color scheme.}
    puts $fh {% Select the active scheme with:  scheme = <name>  in [editor]}
    puts $fh "% colors in #rrggbb format"
    puts $fh ""
    puts $fh "== default =="
    puts $fh "\[default\]"
    puts $fh "% dark mode"
    puts $fh "color_bg       = $::cfg_bg"
    puts $fh "color_fg       = $::cfg_fg"
    puts $fh "color_bg_bar   = $::cfg_bg_bar"
    puts $fh "color_fg_bar   = $::cfg_fg_bar"
    puts $fh "color_bg_sel   = $::cfg_bg_sel"
    puts $fh "color_heading  = $::cfg_color_heading"
    puts $fh "color_comment  = $::cfg_color_comment"
    puts $fh "color_markup   = $::cfg_color_markup"
    puts $fh "% light mode"
    puts $fh "color_bg_alt      = $::cfg_bg_alt"
    puts $fh "color_fg_alt      = $::cfg_fg_alt"
    puts $fh "color_bg_bar_alt  = $::cfg_bg_bar_alt"
    puts $fh "color_fg_bar_alt  = $::cfg_fg_bar_alt"
    puts $fh "color_bg_sel_alt  = $::cfg_bg_sel_alt"
    puts $fh "color_heading_alt = $::cfg_color_heading_alt"
    puts $fh "color_comment_alt = $::cfg_color_comment_alt"
    puts $fh "color_markup_alt  = $::cfg_color_markup_alt"
    puts $fh "% outer margin background (same as color_bg/color_bg_alt by default)"
    puts $fh "% color_bg2       = $::cfg_bg2"
    puts $fh "% color_bg2_alt   = $::cfg_bg2_alt"
    # write any extra schemes stored in memory (user-defined)
    foreach sname [dict keys $::cfg_schemes] {
        if {$sname eq "default"} continue
        puts $fh ""
        puts $fh "== $sname =="
        puts $fh "\[$sname\]"
        set d [dict get $::cfg_schemes $sname]
        foreach key {color_bg color_fg color_bg_bar color_fg_bar color_bg_sel
                     color_heading color_comment color_markup
                     color_bg_alt color_fg_alt color_bg_bar_alt color_fg_bar_alt
                     color_bg_sel_alt color_heading_alt color_comment_alt color_markup_alt
                     color_bg2 color_bg2_alt} {
            if {[dict exists $d $key]} {
                puts $fh "$key = [dict get $d $key]"
            }
        }
    }
    close $fh
}

proc schemes-init {} {
    foreach scheme_name [dict keys $::scheme_defs] {
        set scheme_data [dict get $::scheme_defs $scheme_name]
        dict set ::cfg_schemes $scheme_name $scheme_data
    }
}

# Map Tk key name -> string returned by tui-getch
proc tk-key-to-tui {key} {
    set k [string tolower $key]
    if {[regexp {^control-([a-z])$} $k -> letter]} {
        scan $letter %c code
        return [format %c [expr {$code - 96}]]
    }
    if {$k eq "control-space"} { return "\x00" }
    if {$k eq "escape"}        { return "ESC" }
    if {[regexp {^f(\d+)$} $k -> n]} { return "F$n" }
    return $key
}

# Return a short human-readable label for a Tk key name
proc key-label {key} {
    if {[regexp -nocase {^control-([a-z])$} $key -> l]} { return "^[string toupper $l]" }
    if {[string tolower $key] eq "control-space"}        { return "^SPC" }
    if {[string tolower $key] eq "control-shift-space"}  { return "^+SPC" }
    if {[string tolower $key] eq "escape"}               { return "ESC" }
    if {[regexp -nocase {^f(\d+)$} $key -> n]}          { return "F$n" }
    return $key
}

# Compute TUI equivalents and detect key conflicts
proc keys-init {} {
    set ::cfg_tui_save       [tk-key-to-tui $::cfg_key_save]
    set ::cfg_tui_save_as    [tk-key-to-tui $::cfg_key_save_as]
    set ::cfg_tui_close      [tk-key-to-tui $::cfg_key_close]
    set ::cfg_tui_find       [tk-key-to-tui $::cfg_key_find]
    set ::cfg_tui_replace    [tk-key-to-tui $::cfg_key_replace]
    set ::cfg_tui_help       [tk-key-to-tui $::cfg_key_help]
    set ::cfg_tui_goto       [tk-key-to-tui $::cfg_key_goto]
    set ::cfg_tui_open       [tk-key-to-tui $::cfg_key_open]
    set ::cfg_tui_undo       [tk-key-to-tui $::cfg_key_undo]
    set ::cfg_tui_copy       [tk-key-to-tui $::cfg_key_copy]
    set ::cfg_tui_cut        [tk-key-to-tui $::cfg_key_cut]
    set ::cfg_tui_paste      [tk-key-to-tui $::cfg_key_paste]
    set ::cfg_tui_select_all [tk-key-to-tui $::cfg_key_select_all]
    set ::cfg_tui_sticky_sel [tk-key-to-tui $::cfg_key_sticky_sel]
    set ::cfg_tui_toc          [tk-key-to-tui $::cfg_key_toc]
    set ::cfg_tui_line_nums    [tk-key-to-tui $::cfg_key_line_numbers]
    set ::cfg_tui_redo         [tk-key-to-tui $::cfg_key_redo]
    set ::cfg_tui_typewriter   [tk-key-to-tui $::cfg_key_typewriter]
    set ::cfg_tui_dark_toggle  [tk-key-to-tui $::cfg_key_dark_toggle]
    set ::cfg_tui_split        [tk-key-to-tui $::cfg_key_split]
    set ::cfg_tui_split_focus  [tk-key-to-tui $::cfg_key_split_focus]
    set ::cfg_tui_workspace    [tk-key-to-tui $::cfg_key_workspace]
    set ::cfg_tui_timer        [tk-key-to-tui $::cfg_key_timer]
    set ::cfg_tui_cmd_mode     [tk-key-to-tui $::cfg_key_cmd_mode]
    # labels for UI display
    set ::cfg_lbl_save       [key-label $::cfg_key_save]
    set ::cfg_lbl_close      [key-label $::cfg_key_close]
    set ::cfg_lbl_find       [key-label $::cfg_key_find]
    set ::cfg_lbl_replace    [key-label $::cfg_key_replace]
    set ::cfg_lbl_help       [key-label $::cfg_key_help]
    set ::cfg_lbl_goto       [key-label $::cfg_key_goto]
    set ::cfg_lbl_open       [key-label $::cfg_key_open]
    set ::cfg_lbl_undo       [key-label $::cfg_key_undo]
    set ::cfg_lbl_copy       [key-label $::cfg_key_copy]
    set ::cfg_lbl_paste      [key-label $::cfg_key_paste]
    set ::cfg_lbl_sel_all    [key-label $::cfg_key_select_all]
    set ::cfg_lbl_sticky     [key-label $::cfg_key_sticky_sel]
    set ::cfg_lbl_toc        [key-label $::cfg_key_toc]
    set ::cfg_lbl_line_nums  [key-label $::cfg_key_line_numbers]
    set ::cfg_lbl_redo       [key-label $::cfg_key_redo]
    set ::cfg_lbl_typewriter [key-label $::cfg_key_typewriter]
    set ::cfg_lbl_split      [key-label $::cfg_key_split]
    set ::cfg_lbl_split_focus [key-label $::cfg_key_split_focus]
    set ::cfg_lbl_workspace  [key-label $::cfg_key_workspace]
    set ::cfg_lbl_cmd_mode    [key-label $::cfg_key_cmd_mode]
    # migrate old help_bar default to include workspace shortcut
    if {$::cfg_help_bar eq "^S save   ^Q close   ^H help"} {
        set ::cfg_help_bar "^S save   ^Q close   $::cfg_lbl_workspace workspace   ^H help"
    }
    # conflict detection
    set pairs [list \
        key_save $::cfg_tui_save \
        key_close $::cfg_tui_close  key_find $::cfg_tui_find \
        key_replace $::cfg_tui_replace  key_help $::cfg_tui_help \
        key_goto $::cfg_tui_goto  key_open $::cfg_tui_open \
        key_undo $::cfg_tui_undo  key_copy $::cfg_tui_copy \
        key_cut $::cfg_tui_cut  key_paste $::cfg_tui_paste \
        key_select_all $::cfg_tui_select_all  key_sticky_sel $::cfg_tui_sticky_sel \
        key_toc $::cfg_tui_toc  key_line_numbers $::cfg_tui_line_nums \
        key_redo $::cfg_tui_redo  key_typewriter $::cfg_tui_typewriter]
    set seen [dict create]; set conflicts {}
    foreach {name val} $pairs {
        if {[dict exists $seen $val]} {
            lappend conflicts "$name=[dict get $seen $val]"
        } else { dict set seen $val $name }
    }
    set ::cfg_key_error [join $conflicts "  "]
}

# --- i18n --------------------------------------------------------------------
set ::i18n [dict create]
proc t {key args} {
    set lang [expr {[dict exists $::i18n $::cfg_lang] ? $::cfg_lang : "en"}]
    # Look in the common dict, then the GUI-only dict (absent in TUI/CLI builds),
    # falling back to English for either when a key is missing in $lang.
    if {[dict exists $::i18n $lang $key]} {
        set s [dict get $::i18n $lang $key]
    } elseif {[info exists ::i18n_gui] && [dict exists $::i18n_gui $lang $key]} {
        set s [dict get $::i18n_gui $lang $key]
    } elseif {[dict exists $::i18n en $key]} {
        set s [dict get $::i18n en $key]
    } elseif {[info exists ::i18n_gui] && [dict exists $::i18n_gui en $key]} {
        set s [dict get $::i18n_gui en $key]
    } else {
        return $key
    }
    if {[llength $args]} { return [format $s {*}$args] }
    return $s
}

# --- theme helpers ------------------------------------------------------------
proc theme-colors {} {
    if {$::cfg_dark_mode} {
        return [list $::cfg_bg $::cfg_fg $::cfg_bg_bar $::cfg_fg_bar \
                     $::cfg_bg_sel $::cfg_color_heading $::cfg_color_comment $::cfg_color_markup \
                     $::cfg_bg2]
    } else {
        return [list $::cfg_bg_alt $::cfg_fg_alt $::cfg_bg_bar_alt $::cfg_fg_bar_alt \
                     $::cfg_bg_sel_alt $::cfg_color_heading_alt $::cfg_color_comment_alt $::cfg_color_markup_alt \
                     $::cfg_bg2_alt]
    }
}

proc toggle-dark-mode {} {
    set ::cfg_dark_mode [expr {!$::cfg_dark_mode}]
    if {!$::no_gui} { apply-theme }
}

# --- config -------------------------------------------------------------------
# validate font family (font families is a Tk command - skip in TUI)
if {!$::no_gui && $::cfg_font_family ne "Mono"} {
    if {[lsearch -exact [font families] $::cfg_font_family] < 0} {
        puts stderr "writhdeck: font family '$::cfg_font_family' not found, using Mono"
        set ::cfg_font_family "Mono"
    }
}
if {!$::no_gui && $::cfg_bar_font_family ne "Mono"} {
    if {[lsearch -exact [font families] $::cfg_bar_font_family] < 0} {
        puts stderr "writhdeck: bar font family '$::cfg_bar_font_family' not found, using Mono"
        set ::cfg_bar_font_family "Mono"
    }
}
set ::typewriter_mode 0


# ===========================================================================
# schemes (default alt01)
# ===========================================================================
# Default color scheme - dark and light variants

dict set ::scheme_defs default {
    color_bg       "#1a1a1a"
    color_fg       "#e8e8e8"
    color_bg_bar   "#2a2a2a"
    color_fg_bar   "#aaaaaa"
    color_bg_sel   "#3a5a8a"
    color_heading  "#c8a060"
    color_comment  "#606060"
    color_markup   "#6aa9d4"
    color_bg_alt   "#fdf6e3"
    color_fg_alt   "#657b83"
    color_bg_bar_alt "#eee8d5"
    color_fg_bar_alt "#93a1a1"
    color_bg_sel_alt "#e6ddb9"
    color_heading_alt "#b58900"
    color_comment_alt "#aaaaaa"
    color_markup_alt "#2a7090"
    color_bg2         "#1a1a1a"
    color_bg2_alt     "#fdf6e3"
}
# Alt01 - Dark red/bordeaux color scheme

dict set ::scheme_defs alt01 {
    color_bg       "#1a1214"
    color_fg       "#e8dcc8"
    color_bg_bar   "#241820"
    color_fg_bar   "#9e8878"
    color_bg_sel   "#521828"
    color_heading  "#e63060"
    color_comment  "#6e5858"
    color_markup   "#c24868"
    color_bg_alt   "#fffde9"
    color_fg_alt   "#363c42"
    color_bg_bar_alt "#eee8d5"
    color_fg_bar_alt "#93a1a1"
    color_bg_sel_alt "#f0e7c1"
    color_heading_alt "#c8064a"
    color_comment_alt "#aaaaaa"
    color_markup_alt "#7e1c3e"
    color_bg2         "#150f10"
    color_bg2_alt     "#fffde9"
}

# ===========================================================================
# i18n (en fr)
# ===========================================================================
dict set ::i18n en {
    toc_title          "Table of contents"
    toc_jump_bar       "Enter jump  esc/ctrl+q cancel"
    toc_headings       "%d heading%s"
    br_no_docs         "No documents yet. Press n to create one."
    br_help_tui        "h:%s  n:new  t:scratchpad  f:fav  s:stats  b:backup  d:delete  r:rename  i:info  a:analyse  c:config  w:words  /:filter  %s:sections  q:quit"
    br_backed_up       "backup %s -> %s  (%s)"
    br_favorites       "Favorites"
    br_stats_title     "Writing stats"
    br_stats_no_data   "No writing stats yet for this file."
    br_stats_today     "Today"
    br_stats_total     "Total"
    br_stats_clear     "Clear stats"
    br_stats_clear_confirm "Clear all writing stats for \"%s\"?"
    br_fav_added       "[+] added to favorites: %s"
    br_fav_removed     "[-] removed from favorites: %s"
    br_exists          "'%s' already exists"
    br_deleted         "deleted '%s'"
    br_renamed         "renamed -> '%s'"
    br_delete          "Delete \"%s\"?"
    br_files           "%d file%s"
    br_recent          "Recents"
    ed_saved           "saved"
    ed_readonly        "read-only"
    ed_save_readonly   "\"%s\" is read-only. Save as a new file?"
    ed_save_readonly_quit "read-only - close without saving? (y/c=cancel)"
    ed_watch_reload       "\"%s\" was modified externally. Reload?"
    ed_watch_reload_dirty "\"%s\" was modified externally and you have unsaved changes. Reload?"
    ed_save_before_tui "save before closing? (y/n/c=cancel)"
    help_date_time     "Date & Time"
    help_cur_time      "Current time:  %-12s  Date: %s"
    help_file_info     "File info"
    help_sel_info      "Selection info"
    help_words_chars   "Words: %-8d  Chars: %d"
    help_k_save        "Save"
    help_k_undo        "Undo"
    help_k_redo        "Redo"
    help_k_close       "Close / Esc"
    help_k_sel_all     "Select all"
    help_k_sticky      "Toggle selection"
    help_k_copy        "Copy"
    help_k_find        "Find"
    help_k_cut         "Cut"
    help_k_replace     "Replace"
    help_k_paste       "Paste"
    help_k_goto        "Go to line"
    help_k_lnum        "Line numbers"
    help_k_open        "Open (browser)"
    help_k_typewriter  "Typewriter / focus mode (toggle)"
    help_k_ctrl_arrows "Ctrl+Up/Dn  Paragraph  |  Ctrl+Lt/Rt / Alt+BF  Word"
    help_k_toc         "Table of contents"
    help_k_help        "This help"
    help_k_workspace   "Second workspace (toggle WS1/WS2)"
    br_toc_title       "Browser sections"
    br_toc_bar         "Up/Dn nav  Enter jump  esc cancel"
    br_key_help            "help"
    br_analyse_title       "Structure"
    br_analyse_intro       "(intro)"
    br_analyse_empty       "No content to analyse."
    br_analyse_total       "Total: %d words  -  %d sections"
    br_word_occ_title       "Word Occurrences"
    br_repetitions_title    "Repetitions"
    br_repetitions_empty    "No repetitions found."
    br_repetitions_level1   "Repeated words"
    br_repetitions_level2   "Hidden repetitions"
    br_repetitions_line     "line %d"
    br_repetitions_distance "%d words apart"
    br_repetitions_hidden_off "Hidden-substring check disabled (enable in Settings > Misc)."
    br_spellcheck_title       "Spelling"
    br_spellcheck_checking    "Checking spelling..."
    br_spellcheck_empty       "No spelling errors found."
    br_spellcheck_suggestions "suggestions: %s"
    br_spellcheck_no_suggestions "(no suggestions)"
    br_spellcheck_unavailable "Spell checker unavailable (dictionary '%s' not found)."
    br_synonyms_title       "Synonyms"
    br_synonyms_prompt      "Word:"
    br_synonyms_empty       "No synonyms found."
    br_synonyms_unavailable "Thesaurus unavailable (dictionary '%s' not found)."
    config_tab_timer       "Timer"
    timer_section          "Settings"
    timer_duration         "Duration (min):"
    timer_sound            "Sound at end:"
    timer_alert            "Alert message:"
    timer_type             "Type:"
    chrono_show            "Show in status bar:"
    config_tab_misc        "Misc"
    autosave_section       "Autosave"
    autosave_enabled       "Autosave:"
    autosave_interval      "Interval (min):"
}
dict set ::i18n fr {
    toc_title          "Table des matières"
    toc_jump_bar       "Enter aller  esc/ctrl+q annuler"
    toc_headings       "%d titre%s"
    br_no_docs         "Aucun document. Appuyez sur n pour en créer un."
    br_help_tui        "h:%s  n:nouveau  t:bloc-notes  f:fav  s:stats  b:backup  d:supprimer  r:renommer  i:infos  a:analyse  c:config  w:mots  /:filtre  %s:sections  q:quitter"
    br_backed_up       "sauvegarde %s -> %s  (%s)"
    br_favorites       "Favoris"
    br_stats_title     "Statistiques d'écriture"
    br_stats_no_data   "Aucune statistique d'écriture pour ce fichier."
    br_stats_today     "Aujourd'hui"
    br_stats_total     "Total"
    br_stats_clear     "Effacer les stats"
    br_stats_clear_confirm "Effacer toutes les statistiques de \"%s\" ?"
    br_fav_added       "[+] ajouté aux favoris : %s"
    br_fav_removed     "[-] retiré des favoris : %s"
    br_exists          "'%s' existe déjà"
    br_deleted         "'%s' supprimé"
    br_renamed         "renommé -> '%s'"
    br_delete          "Supprimer \"%s\" ?"
    br_files           "%d fichier%s"
    br_recent          "Récents"
    ed_saved           "enregistré"
    ed_readonly        "lecture-seule"
    ed_save_readonly   "\"%s\" est en lecture seule. Enregistrer sous un nouveau nom ?"
    ed_save_readonly_quit "lecture-seule - fermer sans sauvegarder ? (o/c=annuler)"
    ed_watch_reload       "\"%s\" a été modifié externement. Recharger ?"
    ed_watch_reload_dirty "\"%s\" a été modifié externement et vous avez des modifications non sauvegardées. Recharger ?"
    ed_save_before_tui "enregistrer avant de fermer ? (o/n/c=annuler)"
    help_date_time     "Date & Heure"
    help_cur_time      "Heure actuelle: %-12s  Date : %s"
    help_file_info     "Infos fichier"
    help_sel_info      "Infos sélection"
    help_words_chars   "Mots : %-8d  Caract. : %d"
    help_k_save        "Enregistrer"
    help_k_undo        "Annuler"
    help_k_redo        "Rétablir"
    help_k_close       "Fermer / Esc"
    help_k_sel_all     "Tout sélectionner"
    help_k_sticky      "Activer sélection"
    help_k_copy        "Copier"
    help_k_find        "Chercher"
    help_k_cut         "Couper"
    help_k_replace     "Remplacer"
    help_k_paste       "Coller"
    help_k_goto        "Aller à la ligne"
    help_k_lnum        "Numéros de lignes"
    help_k_open        "Ouvrir (explorateur)"
    help_k_typewriter  "Mode machine à écrire / focus (bascule)"
    help_k_ctrl_arrows "Ctrl+Up/Dn  Paragraphe  |  Ctrl+Lt/Rt / Alt+BF  Mot"
    help_k_toc         "Table des matières"
    help_k_help        "Cette aide"
    help_k_workspace   "Second espace de travail (bascule ES1/ES2)"
    br_toc_title       "Sections du navigateur"
    br_toc_bar         "Up/Dn nav  Enter aller  esc annuler"
    br_key_help            "aide"
    br_analyse_title       "Structure"
    br_analyse_intro       "(début)"
    br_analyse_empty       "Aucun contenu à analyser."
    br_analyse_total       "Total : %d mots  -  %d sections"
    br_word_occ_title       "Occurrences de mots"
    br_repetitions_title    "Répétitions"
    br_repetitions_empty    "Aucune répétition trouvée."
    br_repetitions_level1   "Mots répétés"
    br_repetitions_level2   "Répétitions cachées"
    br_repetitions_line     "ligne %d"
    br_repetitions_distance "%d mots d'écart"
    br_repetitions_hidden_off "Vérification des répétitions cachées désactivée (à activer dans Réglages > Divers)."
    br_spellcheck_title       "Orthographe"
    br_spellcheck_checking    "Vérification orthographique..."
    br_spellcheck_empty       "Aucune erreur orthographique trouvée."
    br_spellcheck_suggestions "suggestions : %s"
    br_spellcheck_no_suggestions "(aucune suggestion)"
    br_spellcheck_unavailable "Correcteur orthographique indisponible (dictionnaire '%s' introuvable)."
    br_synonyms_title       "Synonymes"
    br_synonyms_prompt      "Mot :"
    br_synonyms_empty       "Aucun synonyme trouvé."
    br_synonyms_unavailable "Dictionnaire des synonymes indisponible (dictionnaire '%s' introuvable)."
    config_tab_timer       "Minuterie"
    timer_section          "Parametres"
    timer_duration         "Duree (min) :"
    timer_sound            "Son a la fin :"
    timer_alert            "Message d'alerte :"
    timer_type             "Type :"
    chrono_show            "Afficher dans la barre :"
    config_tab_misc        "Divers"
    autosave_section       "Sauvegarde auto"
    autosave_enabled       "Sauvegarde auto :"
    autosave_interval      "Intervalle (min) :"
}

# ===========================================================================
# common.tcl
# ===========================================================================
# --- initialization (run after schemes and i18n are loaded) -----------
schemes-init
ini-load
keys-init

# Apply docs_dir from config (must be after ini-load)
if {$::cfg_docs_dir ne ""} {
    set ::DOCS_DIR [file normalize [tilde-expand $::cfg_docs_dir]]
    if {$::DOCS_DIR eq $::DOCS_DIR_DEFAULT} { set ::DOCS_DIR $::DOCS_DIR_DEFAULT }
    file mkdir $::DOCS_DIR
}

# Initialize fonts and theme colors (must be after ini-load to use selected scheme/profile)
set font    [list $::cfg_font_family $::cfg_font_size]
set bar_pady [expr {$::cfg_bar_height > 0 \
    ? min(2, max(0, ($::cfg_bar_height - 6) / 2)) : 0}]
set font_sm  [expr {$::cfg_bar_height > 0 \
    ? [list $::cfg_bar_font_family [expr {-max(6, $::cfg_bar_height - 2*$bar_pady)}]] \
    : [list $::cfg_bar_font_family 10]}]
set ::font_sm $font_sm
lassign [theme-colors] bg fg bg_bar fg_bar bg_sel _ _ _ bg2
set fg_dim  "#676767"
# expose as globals for use in procs
set ::bg     $bg
set ::fg     $fg
set ::bg_bar $bg_bar
set ::fg_bar $fg_bar
set ::bg_sel $bg_sel
set ::bg2    $bg2

# --- utils --------------------------------------------------------------------
proc list-docs {dir} {
    set pairs {}
    set patterns [expr {$::cfg_browser_show_all ? {} : [regexp -all -inline {\S+} $::cfg_browser_filter]}]
    foreach f [glob -nocomplain -directory $dir -tails *] {
        set full [file join $dir $f]
        if {[file isfile $full] && ![string match .* $f]} {
            if {[llength $patterns]} {
                set match 0
                foreach pat $patterns {
                    if {[string match -nocase $pat $f]} { set match 1; break }
                }
                if {!$match} continue
            }
            lappend pairs [list [file mtime $full] $f]
        }
    }
    set result {}
    foreach item [lsort -integer -decreasing -index 0 $pairs] {
        lappend result [lindex $item 1]
    }
    return $result
}

# Incremental browser filter ("/" key in the browser): when non-empty, only
# file/favorite/recent entries whose name contains the string are shown
# (case-insensitive substring, no glob). Shared GUI/TUI.
set ::br_type_filter ""
proc br-filter-match {name} {
    if {$::br_type_filter eq ""} { return 1 }
    return [expr {[string first [string tolower $::br_type_filter] \
                                [string tolower $name]] >= 0}]
}

proc br-dirs {} {
    if {$::DOCS_DIR ne $::DOCS_DIR_DEFAULT} {
        return [list $::DOCS_DIR $::DOCS_DIR_DEFAULT]
    }
    return [list $::DOCS_DIR_DEFAULT]
}

set ::cached_heading_re       ""
set ::cached_comment_re       ""
set ::cached_bold_re          ""
set ::cached_italic_re        ""
set ::cached_underline_re     ""
set ::cached_strikethrough_re ""
set ::cached_bold_mlen          0
set ::cached_italic_mlen        0
set ::cached_underline_mlen     0
set ::cached_strikethrough_mlen 0
set ::hl_line_cache {}
set ::hl_last_count 0

proc heading-re {} {
    set m [regsub -all {[\\^$.|?*+()\[\]{}]} $::cfg_heading_marker {\\&}]
    return "^\\s*${m}\\s*(.+?)\\s*${m}\\s*$"
}

proc parse-comment {line} {
    if {$::cached_comment_re eq ""} { return 0 }
    return [regexp -- $::cached_comment_re $line]
}

# A list item line: begins (after optional leading whitespace) with a bullet
# followed by whitespace (e.g. "- item"). "-" is always recognised; "*" only
# when Markdown support is enabled. Highlighted whole-line in the markup
# colour, like bold/italic spans.
proc parse-list {line} {
    if {[regexp {^\s*-\s} $line]} { return 1 }
    if {$::cfg_markdown_support && [regexp {^\s*\*\s} $line]} { return 1 }
    return 0
}

proc inline-re {marker} {
    if {$marker eq ""} { return "" }
    set m [regsub -all {[\\^$.|?*+()\[\]{}]} $marker {\\&}]
    return "${m}.+?${m}"
}

proc apply-inline {ln line tag re mlen {content_only 0}} {
    set s 0
    set llen [string length $line]
    while {[regexp -start $s -indices -- $re $line m]} {
        lassign $m a b
        set pre  [expr {$a > 0       ? [string index $line [expr {$a-1}]] : ""}]
        set post [expr {$b+1 < $llen ? [string index $line [expr {$b+1}]] : ""}]
        if {($pre  eq "" || ![string is alnum $pre]) &&
            ($post eq "" || ![string is alnum $post]) &&
            ![string is space [string index $line [expr {$a + $mlen}]]] &&
            ![string is space [string index $line [expr {$b - $mlen}]]]} {
            if {$content_only} {
                .ed.t tag add $tag "$ln.[expr {$a+$mlen}]" "$ln.[expr {$b-$mlen+1}]"
            } else {
                .ed.t tag add $tag $ln.$a "$ln.[expr {$b+1}]"
            }
            .ed.t tag add marker $ln.$a "$ln.[expr {$a+$mlen}]"
            .ed.t tag add marker "$ln.[expr {$b-$mlen+1}]" "$ln.[expr {$b+1}]"
        }
        set s [expr {$b+1}]
    }
}

proc parse-heading {line} {
    if {[regexp $::cached_heading_re $line -> title]} { return [string trim $title] }
    if {$::cfg_markdown_support && \
            [regexp {^\s*(#{1,6})\s+(.+)$} $line -> _ title]} { return [string trim $title] }
    return ""
}

proc heading-level {line} {
    set m    [regsub -all {[\\^$.|?*+()\[\]{}]} $::cfg_heading_marker {\\&}]
    set mlen [string length $::cfg_heading_marker]
    if {$mlen > 0} {
        set re "^\\s*((?:${m})+)\\s*(.+?)\\s*(?:${m})+\\s*\$"
        if {[regexp $re $line -> markers title]} {
            return [list [string trim $title] [expr {[string length $markers] / $mlen}]]
        }
    }
    if {$::cfg_markdown_support && \
            [regexp {^\s*(#{1,6})\s+(.+)$} $line -> hashes title]} {
        return [list [string trim $title] [string length $hashes]]
    }
    return ""
}

proc markers-update {} {
    set ::cached_heading_re [heading-re]
    if {$::cfg_comment_marker ne ""} {
        set m [regsub -all {[\\^$.|?*+()\[\]{}]} $::cfg_comment_marker {\\&}]
        set ::cached_comment_re "^${m}"
    } else {
        set ::cached_comment_re ""
    }
    set ::cached_bold_re          [inline-re $::cfg_bold_marker]
    set ::cached_italic_re        [inline-re $::cfg_italic_marker]
    set ::cached_underline_re     [inline-re $::cfg_underline_marker]
    set ::cached_strikethrough_re [inline-re $::cfg_strikethrough_marker]
    set ::cached_bold_mlen          [string length $::cfg_bold_marker]
    set ::cached_italic_mlen        [string length $::cfg_italic_marker]
    set ::cached_underline_mlen     [string length $::cfg_underline_marker]
    set ::cached_strikethrough_mlen [string length $::cfg_strikethrough_marker]
    set ::hl_line_cache {}
    set ::hl_last_count 0
}

proc fmt-meta {path} {
    set sz [file size $path]
    set sz_str [expr {$sz < 1024 ? "${sz}B" : "[expr {$sz/1024}]K"}]
    set mt [clock format [file mtime $path] -format "%d %b %H:%M"]
    return "$sz_str\t$mt"
}

proc status-zone-of {tok} {
    if {[lsearch -exact $::cfg_status_left   $tok] >= 0} { return left }
    if {[lsearch -exact $::cfg_status_center $tok] >= 0} { return center }
    if {[lsearch -exact $::cfg_status_right  $tok] >= 0} { return right }
    return ""
}

proc status-build {tokens state} {
    set fn    [dict get $state fn]
    set dirty [dict get $state dirty]
    set sel   [dict get $state sel]
    set ln    [dict get $state ln]
    set total [dict get $state total]
    set col   [dict get $state col]
    set words [dict get $state words]
    set chars [dict get $state chars]
    set clk   [dict get $state clock]
    set timer [dict get $state timer]
    set rdonly [expr {[dict exists $state readonly] ? [dict get $state readonly] : 0}]
    set result ""
    foreach tok $tokens {
        switch -- $tok {
            workspace { if {$::ws_dual_mode} {
                set _wsn [expr {[dict exists $state ws] ? [dict get $state ws] : $::ws_n}]
                append result "\[$_wsn\] "
            } }
            filename {
                append result $fn
                if {$rdonly} { append result " \[[t ed_readonly]\]" }
            }
            dirty    { if {$dirty}      { append result " \[+\]" } }
            sel      { if {$sel}        { append result " \[sel\]" } }
            ln       { append result [format "  Ln %d/%d" $ln $total] }
            col      { append result [format "  Col %-3d" $col] }
            words    { append result "  ${words}w" }
            chars    { append result "  ${chars}c" }
            goal     { if {$::cfg_word_goal > 0} { append result [format "  %d/%d" [daily-today $words] $::cfg_word_goal] } }
            clock    { append result "  $clk" }
            timer    { if {$::cfg_chrono_show} {
                set _m [expr {$timer / 60}]
                set _s [expr {$timer % 60}]
                if {$::timer_active} {
                    append result [format " \[%d'%02d\"]" $_m $_s]
                } else {
                    append result [format "  %d'%02d\"" $_m $_s]
                }
            } }
            space    { append result " " }
            help_bar {}
            default  { append result $tok }
        }
    }
    return $result
}

markers-update

proc build-extra-entries {shown} {
    if {!$::state_cache_valid} { state-load }
    set result {}
    set vfav {}
    foreach p $::favorites_list { if {[file isfile $p]} { lappend vfav $p } }
    if {[llength $vfav]} {
        lappend result [list header "" [t br_favorites]]
        foreach p $vfav { lappend result [list favorite [file dirname $p] [file tail $p]] }
    }
    set vrec {}
    foreach p $::recent_list { if {[file isfile $p]} { lappend vrec $p } }
    if {[llength $vrec]} {
        lappend result [list header "" [t br_recent]]
        foreach p $vrec { lappend result [list recent [file dirname $p] [file tail $p]] }
    }
    return $result
}

proc do-beep {} {
    catch {
        exec sh -c {ffplay -f lavfi -i "sine=frequency=440:duration=0.3" -nodisp -autoexit -loglevel quiet 2>/dev/null; sleep 0.4; ffplay -f lavfi -i "sine=frequency=440:duration=0.3" -nodisp -autoexit -loglevel quiet 2>/dev/null} &
    }
}

proc do-backup {dir name} {
    set bdir [file join $::DOCS_DIR backups]
    file mkdir $bdir
    set ts  [clock format [clock seconds] -format "%Y-%m-%dT%Hh%Mm%S"]
    set dst [file join $bdir "[file rootname $name]_${ts}[file extension $name]"]
    set src [file join $dir $name]
    if {[file type $src] eq "link"} { set src [file normalize $src] }
    file copy -force $src $dst
    return $dst
}

proc do-autosave {ws_n content filepath} {
    if {!$::cfg_autosave_enabled} return
    set dir [file normalize [tilde-expand "~/Documents/writhdeck"]]
    file mkdir $dir
    set fn  [expr {$ws_n == 1 ? "autosave_ws01.txt" : "autosave_ws02.txt"}]
    set dst [file join $dir $fn]
    set ts  [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"]
    if {$filepath eq ""} {
        set header "scratchpad"
    } else {
        set folder [string map [list $::HOME_DIR ~] [file dirname $filepath]]
        set header "$folder/[file tail $filepath]"
    }
    set fh [open $dst w]
    chan configure $fh -encoding utf-8
    puts $fh $header
    puts $fh $ts
    puts $fh ""
    puts $fh "-------------------------"
    puts -nonewline $fh $content
    close $fh
    set ::autosave_last_time [clock seconds]
}

proc scratch-tmpfile {content} {
    set p [file join $::HOME_DIR .writhdeck_scratch_analyse.txt]
    set fd [open $p w]
    chan configure $fd -encoding utf-8
    puts -nonewline $fd $content
    close $fd
    return $p
}

# Stable virtual path used to track daily writing stats for the scratchpad
# (which has no real filename). Also the file the live buffer is snapshotted
# to, so the stats dialog can compute total words/chars off-disk.
proc scratchpad-stats-path {} {
    return [file normalize [file join $::HOME_DIR .writhdeck_scratchpad.txt]]
}

# Open a daily-stats session for the scratchpad. Call when the scratchpad
# is (re)entered, with the buffer's current word count, so the baseline is
# captured before the user starts writing.
proc scratchpad-stats-open {wc} {
    daily-open [scratchpad-stats-path] $wc
}

# Snapshot the scratchpad buffer to its stats file and record today's word
# count, so the stats dialog works without the text ever being saved to a
# real document. Returns the stats path. $wc is the current word count.
# Assumes scratchpad-stats-open was called on scratchpad entry.
proc scratchpad-stats-record {content wc} {
    set p [scratchpad-stats-path]
    catch {
        set fd [open $p w]
        chan configure $fd -encoding utf-8
        puts -nonewline $fd $content
        close $fd
    }
    if {$::session_file ne $p} { scratchpad-stats-open $wc }
    daily-update $wc
    return $p
}

proc toggle-favorite {path} {
    set path [file normalize $path]
    if {!$::state_cache_valid} { state-load }
    set idx [lsearch -exact $::favorites_list $path]
    if {$idx >= 0} {
        set ::favorites_list [lreplace $::favorites_list $idx $idx]
    } else {
        lappend ::favorites_list $path
    }
    state-save
}

# ===========================================================================
# analysis.tcl
# ===========================================================================
# ===========================================================================
# Analysis tools: structure outline, word-occurrence search, repetition
# detection. Optional module -- see ANALYSIS_TOOLS (and the per-target
# MINI_ANALYSIS_TOOLS / JIM_ANALYSIS_TOOLS overrides) in the Makefile.
# ===========================================================================

# --- shared helpers (used by both GUI and TUI) ----------------------------

proc analysis-strip-comments {content} {
    if {!$::cfg_analysis_ignore_comments || $::cached_comment_re eq ""} {
        return $content
    }
    set lines {}
    foreach line [split $content "\n"] {
        if {[regexp -- $::cached_comment_re $line]} {
            lappend lines ""
        } else {
            lappend lines $line
        }
    }
    return [join $lines "\n"]
}

proc analyse-data {fpath} {
    # Returns {total nsec sdata} where sdata is a list of {indent level title words pct}.
    # Returns {} if the file does not exist.
    if {![file exists $fpath]} { return {} }
    set sections [analyse-structure $fpath]
    set total 0
    foreach sec $sections { incr total [lindex $sec 2] }
    set result {}
    foreach sec $sections {
        lassign $sec title level words
        if {$words == 0 && $title eq ""} continue
        set pct [expr {$total > 0 ? round($words * 100.0 / $total) : 0}]
        set indent [string repeat "  " [expr {max(0, $level - 1)}]]
        lappend result [list $indent $level $title $words $pct]
    }
    return [list $total [llength $result] $result]
}

proc analyse-structure {fpath} {
    if {![file exists $fpath]} { return {} }
    set fd [open $fpath r]
    chan configure $fd -encoding utf-8
    set content [read $fd]
    close $fd

    set sections {}
    set cur_title ""
    set cur_level 0
    set cur_words 0

    foreach line [split $content \n] {
        set hl [heading-level $line]
        if {$hl ne ""} {
            lappend sections [list $cur_title $cur_level $cur_words]
            lassign $hl title level
            set cur_title $title
            set cur_level $level
            set cur_words 0
        } else {
            incr cur_words [llength [regexp -all -inline {\S+} $line]]
        }
    }
    lappend sections [list $cur_title $cur_level $cur_words]
    return $sections
}

proc _cmp_word_count {counts a b} {
    set cmp [expr {[dict get $counts $b] - [dict get $counts $a]}]
    if {$cmp != 0} {return $cmp}
    return [string compare $a $b]
}

# Merges singular/plural pairs ("chemise" + "chemises") into one entry
# "chemise(s)" with the combined count, so they appear as a single occurrence.
proc merge-singular-plural {counts} {
    set skip [dict create]
    foreach word [dict keys $counts] {
        if {[string index $word end] eq "s"} {
            set singular [string range $word 0 end-1]
            if {[dict exists $counts $singular]} {
                dict set skip $word 1
                dict set skip $singular 1
            }
        }
    }
    set merged [dict create]
    foreach word [dict keys $counts] {
        if {[string index $word end] eq "s"} {
            set singular [string range $word 0 end-1]
            if {[dict exists $counts $singular]} {
                dict set merged "${singular}(s)" [expr {[dict get $counts $word] + [dict get $counts $singular]}]
                continue
            }
        }
        if {![dict exists $skip $word]} {
            dict set merged $word [dict get $counts $word]
        }
    }
    return $merged
}

proc get-word-occurrences {fpath} {
    set counts [dict create]
    if {[catch {
        set fh [open $fpath r]; chan configure $fh -encoding utf-8
        set content [read $fh]
        close $fh
        set content [analysis-strip-comments $content]
        foreach word [regexp -all -inline {\w+} [string tolower $content]] {
            if {[string length $word] > 2} {
                dict incr counts $word
            }
        }
    }]} {
        return [list]
    }
    set counts [merge-singular-plural $counts]
    set result {}
    foreach word [lsort -command [list _cmp_word_count $counts] [dict keys $counts]] {
        lappend result [list $word [dict get $counts $word]]
    }
    return $result
}

# Common short words excluded from repetition detection to reduce noise.
# Falls back to the English list for languages without their own entry.
set ::repetition_stopwords [dict create \
    en {about above after again against all also although always among and another any anyone anything are around because been before being between both but cannot could did does doing down during each either else enough even ever every for from further had has have having here how however into its itself just like more most much must never not now off once only onto other our ours out over own same several should since some such than that the their theirs them then there these they this those through thus too toward under until upon very was well were what when where which while who whom whose why will with within without would your yours} \
    fr {alors après aussi autre autres avant avec bien car cela celle celles celui ces cette ceux chaque chez comme dans depuis des donc dont déjà elle elles encore entre est été étaient était être faire fait ici ils les lequel leur leurs lorsque là même non notre nos nous où oui par parce pas peu plus pour pourquoi quand que quel quelle quelles quels quelque quelques qui quoi sans ses seulement son sont sous suis sur toute toutes tous tout très trop une vers voici voilà votre vos vous} \
]

proc repetition-stopwords {} {
    if {[dict exists $::repetition_stopwords $::cfg_lang]} {
        return [dict get $::repetition_stopwords $::cfg_lang]
    }
    return [dict get $::repetition_stopwords en]
}

proc repetition-lemma {word} {
    if {[string length $word] > 3} {
        set last [string index $word end]
        if {$last eq "s" || $last eq "x"} {
            return [string range $word 0 end-1]
        }
    }
    return $word
}

# Two-tier repetition scan: level 1 = same word/lemma repeated within
# ::cfg_repetition_scope words; level 2 (optional, ::cfg_repetition_hidden) =
# one word hidden as a substring of another (e.g. "tour" in "alentours").
# Returns {level1 level2}, each a list of {word1 line1 word2 line2 distance}.
proc find-repetitions {fpath} {
    set scope   $::cfg_repetition_scope
    set min_len $::cfg_repetition_min_len
    set stop    [repetition-stopwords]

    if {[catch {
        set fh [open $fpath r]; chan configure $fh -encoding utf-8
        set content [read $fh]
        close $fh
    }]} {
        return [list {} {}]
    }
    set content [analysis-strip-comments $content]

    set occurrences {}
    set index 0
    set line_no 1
    foreach line [split $content "\n"] {
        foreach word [regexp -all -inline {\w+} [string tolower $line]] {
            if {[string length $word] > 2 && [lsearch -exact $stop $word] < 0} {
                lappend occurrences [list $word [repetition-lemma $word] $line_no $index]
            }
            incr index
        }
        incr line_no
    }

    set by_lemma [dict create]
    foreach occ $occurrences {
        lassign $occ word lemma line idx
        dict lappend by_lemma $lemma $occ
    }
    set level1 {}
    foreach lemma [dict keys $by_lemma] {
        set occs [dict get $by_lemma $lemma]
        for {set i 1} {$i < [llength $occs]} {incr i} {
            lassign [lindex $occs [expr {$i-1}]] word1 lemma1 line1 idx1
            lassign [lindex $occs $i]              word2 lemma2 line2 idx2
            set gap [expr {$idx2 - $idx1}]
            if {$gap <= $scope} {
                lappend level1 [list $word1 $line1 $word2 $line2 $gap]
            }
        }
    }
    set level1 [lsort -integer -index 1 $level1]

    set level2 {}
    if {$::cfg_repetition_hidden} {
        set long_occs {}
        foreach occ $occurrences {
            lassign $occ word lemma line idx
            if {[string length $word] >= $min_len} {
                lappend long_occs $occ
            }
        }
        set n [llength $long_occs]
        for {set i 0} {$i < $n} {incr i} {
            lassign [lindex $long_occs $i] wordA lemmaA lineA idxA
            for {set j [expr {$i+1}]} {$j < $n} {incr j} {
                lassign [lindex $long_occs $j] wordB lemmaB lineB idxB
                set gap [expr {$idxB - $idxA}]
                if {$gap > $scope} break
                if {$lemmaA eq $lemmaB} continue
                if {[string first $wordA $wordB] >= 0 || [string first $wordB $wordA] >= 0} {
                    lappend level2 [list $wordA $lineA $wordB $lineB $gap]
                }
            }
        }
        set level2 [lsort -integer -index 1 $level2]
    }

    return [list $level1 $level2]
}

# --- spellcheck --------------------------------------------------------------
# On-demand spellcheck via a persistent "hunspell -a" pipe. Computed lazily,
# only when the user opens the Spelling tool from Structure Analysis.

# Maps a WrithDeck UI language code to a hunspell dictionary name.
proc spell-dict-for-lang {lang} {
    switch -- $lang {
        en { return "en_US" }
        fr { return "fr_FR" }
        de { return "de_DE" }
        es { return "es_ES" }
        no { return "nb_NO" }
        ko { return "" }
        default { return "en_US" }
    }
}

# Returns the hunspell dictionary name to use: ::cfg_spell_lang if set
# (raw hunspell dict name, e.g. "fr_BE"), else derived from ::cfg_lang.
proc spell-dict-resolve {} {
    if {$::cfg_spell_lang ne ""} { return $::cfg_spell_lang }
    return [spell-dict-for-lang $::cfg_lang]
}

# Lazily opens (or reuses) a persistent "hunspell -a -d $dict" pipe. Returns
# "" if hunspell or the dictionary is unavailable. Reopens if the cached pipe
# was for a different dictionary or has died.
proc spell-pipe-get {dict} {
    if {$dict eq ""} { return "" }
    if {[info exists ::spell_pipe] && $::spell_pipe ne ""} {
        if {$::spell_pipe_dict eq $dict && ![eof $::spell_pipe]} {
            return $::spell_pipe
        }
        catch { close $::spell_pipe }
        unset ::spell_pipe
    }
    if {[catch {
        set pipe [open "|hunspell -a -d $dict" r+]
        chan configure $pipe -encoding utf-8 -buffering line
        gets $pipe
        if {[eof $pipe]} { error "hunspell unavailable" }
    }]} {
        catch { close $pipe }
        return ""
    }
    set ::spell_pipe $pipe
    set ::spell_pipe_dict $dict
    return $pipe
}

# Sends one word to the hunspell pipe and reads its reply. hunspell -a
# replies to each word with one result line followed by a blank line.
# Returns {1 {}} if correct, {0 {sugg1 sugg2 ...}} if not (suggestions may be
# empty). On pipe failure, closes/unsets ::spell_pipe and re-raises so the
# caller can abort the scan gracefully.
proc spell-check-word {pipe word} {
    if {[catch {
        puts $pipe $word
        flush $pipe
        set result [gets $pipe]
        if {[eof $pipe]} { error "hunspell pipe closed" }
        gets $pipe
    } err]} {
        catch { close $pipe }
        catch { unset ::spell_pipe }
        error $err
    }
    switch -- [string index $result 0] {
        "*" - "+" - "-" { return [list 1 {}] }
        "&" {
            set colon [string first ":" $result]
            if {$colon < 0} { return [list 0 {}] }
            set sugg {}
            foreach s [split [string range $result [expr {$colon+1}] end] ","] {
                set s [string trim $s]
                if {$s ne ""} { lappend sugg $s }
            }
            return [list 0 $sugg]
        }
        default { return [list 0 {}] }
    }
}

# Removes markup markers built from word characters (only cfg_underline_marker
# qualifies; the others are non-word and naturally excluded by the word regex
# used in spell-check-document).
proc spell-strip-markup {content} {
    if {$::cfg_underline_marker ne ""} {
        set content [string map [list $::cfg_underline_marker " "] $content]
    }
    return $content
}

# Scans $fpath for misspelled words. Returns a list of {word line suggestions}
# for every occurrence of every misspelled word, in line order. Returns {} if
# the document is clean or the spell checker is unavailable.
proc spell-check-document {fpath} {
    set pipe [spell-pipe-get [spell-dict-resolve]]
    if {$pipe eq ""} { return {} }

    if {[catch {
        set fh [open $fpath r]; chan configure $fh -encoding utf-8
        set content [read $fh]
        close $fh
    }]} {
        return {}
    }
    set content [analysis-strip-comments $content]
    set content [spell-strip-markup $content]

    set cache [dict create]
    set results {}
    set line_no 1
    foreach line [split $content "\n"] {
        foreach word [regexp -all -inline {[[:alpha:]]+(?:['-][[:alpha:]]+)*} $line] {
            if {![dict exists $cache $word]} {
                if {[catch {spell-check-word $pipe $word} res]} { return $results }
                dict set cache $word $res
            }
            lassign [dict get $cache $word] ok sugg
            if {!$ok} { lappend results [list $word $line_no $sugg] }
        }
        incr line_no
    }
    return $results
}

# --- synonyms (mythes thesaurus) --------------------------------------------
# On-demand synonym lookup via the Mythes thesaurus data files used by
# LibreOffice (Debian/Ubuntu packages: mythes-fr, mythes-en-us, mythes-de,
# mythes-es, mythes-no...). No CLI binary exists for mythes (unlike hunspell),
# so the .dat/.idx files are read and parsed directly in Tcl. Dictionary
# naming matches hunspell's exactly (e.g. "fr_FR"), so spell-dict-resolve is
# reused as-is.

# Directories searched for th_<dict>_v2.dat / .idx, in order.
proc thes-candidate-dirs {} {
    return {/usr/share/mythes /usr/share/hunspell /usr/local/share/mythes /opt/homebrew/share/mythes}
}

# Returns {dat idx} paths for $dict, or {} if not installed.
proc thes-files-resolve {dict} {
    if {$dict eq ""} { return {} }
    foreach dir [thes-candidate-dirs] {
        set dat [file join $dir "th_${dict}_v2.dat"]
        set idx [file join $dir "th_${dict}_v2.idx"]
        if {[file readable $dat] && [file readable $idx]} { return [list $dat $idx] }
    }
    return {}
}

# True if a thesaurus is available for the resolved spell-check language.
proc thes-available {} {
    return [expr {[thes-files-resolve [spell-dict-resolve]] ne {}}]
}

# Lazily loads and caches the full word|offset index as a list of raw lines
# (the .idx file is already sorted in plain Tcl string order, verified
# against the Debian mythes-fr/-en-us/-de/-es/-no packages, which makes a
# binary search over the cached lines both correct and fast without needing
# to hold a parsed dict of ~200k entries in memory).
proc thes-idx-load {idxpath} {
    if {[info exists ::thes_idx_cache($idxpath)]} { return $::thes_idx_cache($idxpath) }
    set lines {}
    catch {
        set fh [open $idxpath r]; chan configure $fh -encoding utf-8
        gets $fh; gets $fh
        while {[gets $fh line] >= 0} {
            if {$line ne ""} { lappend lines $line }
        }
        close $fh
    }
    set ::thes_idx_cache($idxpath) $lines
    return $lines
}

# Binary search for $word in the cached idx lines. Returns the byte offset
# into the matching .dat file as a string, or "" if not found.
proc thes-idx-find {lines word} {
    set lo 0
    set hi [expr {[llength $lines] - 1}]
    while {$lo <= $hi} {
        set mid [expr {($lo + $hi) / 2}]
        set line [lindex $lines $mid]
        set bar [string first "|" $line]
        set cmp [string compare $word [string range $line 0 [expr {$bar - 1}]]]
        if {$cmp == 0} { return [string range $line [expr {$bar + 1}] end] }
        if {$cmp < 0} { set hi [expr {$mid - 1}] } else { set lo [expr {$mid + 1}] }
    }
    return ""
}

# Reads one entry at $offset in $datpath. Returns a list of {category
# {syn1 syn2 ...}} pairs (one per sense), or {} on read failure.
proc thes-dat-entry {datpath offset} {
    set entries {}
    catch {
        set fh [open $datpath r]; chan configure $fh -encoding utf-8
        seek $fh $offset
        gets $fh header
        set n [string range $header [expr {[string first "|" $header] + 1}] end]
        for {set i 0} {$i < $n} {incr i} {
            if {[gets $fh l] < 0} break
            set parts [split $l "|"]
            lappend entries [list [string trim [lindex $parts 0] "()"] [lrange $parts 1 end]]
        }
        close $fh
    }
    return $entries
}

# Looks up synonyms for $word. Returns a list of {category {syn1 syn2 ...}}
# pairs (possibly {} if the word isn't in the thesaurus); caller must check
# thes-available first to distinguish "no thesaurus" from "no synonyms".
# Falls back to a lowercase match (thesaurus entries are lowercase, e.g. a
# capitalised word at the start of a sentence would otherwise miss).
proc thes-lookup {word} {
    lassign [thes-files-resolve [spell-dict-resolve]] dat idx
    if {$dat eq ""} { return {} }
    set lines [thes-idx-load $idx]
    set off [thes-idx-find $lines $word]
    if {$off eq "" && $word ne [string tolower $word]} {
        set off [thes-idx-find $lines [string tolower $word]]
    }
    if {$off eq ""} { return {} }
    return [thes-dat-entry $dat $off]
}

# Returns the word touching column $cx (0-based) in $line, using the same
# word pattern as spell-check-document, or "" if none. Shared by the TUI
# editor's word-under-cursor synonym lookup.
proc tui-word-at {line cx} {
    foreach m [regexp -all -inline -indices {[[:alpha:]]+(?:['-][[:alpha:]]+)*} $line] {
        lassign $m s e
        if {($cx >= $s && $cx <= $e) || ($cx - 1 >= $s && $cx - 1 <= $e)} {
            return [string range $line $s $e]
        }
    }
    return ""
}

# --- GUI dialogs -----------------------------------------------------------

proc br-analyse-shortcut {} {
    set e [br-selected]
    if {[llength $e]} {
        set fpath [file join [lindex $e 1] [lindex $e 2]]
        analyse-dialog $fpath
    }
}

proc analyse-dialog {fpath} {
    set data [analyse-data $fpath]
    if {$data eq {}} { info-dialog "File not found: $fpath"; return }
    lassign $data total nsec sdata

    set w .adlg
    catch {destroy $w}
    toplevel $w
    wm title $w [t br_analyse_title]
    wm geometry $w 520x420
    wm transient $w .

    label $w.hdr -text "[file tail $fpath]" -font [list [lindex $::font 0] [lindex $::font 1] bold] \
        -bg $::bg_bar -fg $::fg_bar -anchor w -padx 10 -pady 5

    frame $w.f -bg $::bg
    text $w.f.t -font $::font_sm -bg $::bg -fg $::fg -bd 0 -highlightthickness 0 \
        -yscrollcommand [list $w.f.sb set] -wrap none -width 66 -height 22 \
        -selectbackground $::bg_sel -selectforeground $::fg -cursor arrow -padx 10 -pady 6
    scrollbar $w.f.sb -orient vertical -command [list $w.f.t yview]

    $w.f.t tag configure heading_tag -foreground $::cfg_color_heading
    $w.f.t tag configure bar_tag     -foreground $::cfg_color_heading
    $w.f.t tag configure dim_tag     -foreground $::fg_bar

    $w.f.t configure -state normal
    if {$total == 0} {
        $w.f.t insert end "\n  [t br_analyse_empty]\n" dim_tag
    } else {
        set max_bar 28
        foreach row $sdata {
            lassign $row indent level title words pct
            set bar [string repeat "|" [expr {max(1, round($pct * $max_bar / 100.0))}]]
            set lbl [expr {$title eq "" ? [t br_analyse_intro] : $title}]
            set lvl_str [expr {$level > 0 ? "H$level " : "    "}]
            $w.f.t insert end "\n${indent}${lvl_str}" dim_tag
            $w.f.t insert end "${lbl}\n" heading_tag
            $w.f.t insert end "${indent}    ${bar} " bar_tag
            $w.f.t insert end "${words}w (${pct}%)\n" dim_tag
        }
        $w.f.t insert end "\n  [t br_analyse_total $total $nsec]\n" dim_tag
    }
    $w.f.t configure -state disabled

    pack $w.f.sb -side right -fill y
    pack $w.f.t  -side left  -fill both -expand 1

    frame $w.btns
    button $w.btns.rep   -text [t br_repetitions_title] -font $::font_sm -command [list repetitions-dialog $fpath]
    button $w.btns.occ   -text [t br_word_occ_title] -font $::font_sm -command [list word-occurrences-dialog $fpath]
    button $w.btns.spell -text [t br_spellcheck_title] -font $::font_sm -command [list spellcheck-dialog $fpath]
    button $w.btns.syn   -text [t br_synonyms_title] -font $::font_sm -command synonyms-prompt
    button $w.btns.ok    -text "OK" -font $::font_sm -command [list destroy $w]
    pack $w.btns.ok    -side right -padx 8 -pady 6
    pack $w.btns.rep   -side right -padx 4 -pady 6
    pack $w.btns.occ   -side right -padx 4 -pady 6
    pack $w.btns.spell -side right -padx 4 -pady 6
    pack $w.btns.syn   -side right -padx 4 -pady 6

    pack $w.hdr  -fill x
    pack $w.btns -side bottom -fill x
    pack $w.f    -fill both -expand 1 -padx 2 -pady 2

    bind $w <Return> [list destroy $w]
    bind $w <Escape> [list destroy $w]
    update
    grab $w
    focus $w.btns.ok
    tkwait window $w
}

proc repetitions-dialog {fpath} {
    if {![file exists $fpath]} return
    lassign [find-repetitions $fpath] level1 level2

    set w .rpdlg
    catch {destroy $w}
    toplevel $w
    wm title $w [t br_repetitions_title]
    wm geometry $w 520x420
    wm transient $w .

    label $w.hdr -text "[file tail $fpath]" -font [list [lindex $::font 0] [lindex $::font 1] bold] \
        -bg $::bg_bar -fg $::fg_bar -anchor w -padx 10 -pady 5

    frame $w.f -bg $::bg
    text $w.f.t -font $::font_sm -bg $::bg -fg $::fg -bd 0 -highlightthickness 0 \
        -yscrollcommand [list $w.f.sb set] -wrap none -width 66 -height 22 \
        -selectbackground $::bg_sel -selectforeground $::fg -cursor arrow -padx 10 -pady 6
    scrollbar $w.f.sb -orient vertical -command [list $w.f.t yview]

    $w.f.t tag configure heading_tag -foreground $::cfg_color_heading
    $w.f.t tag configure dim_tag     -foreground $::fg_bar

    set _rn 0
    $w.f.t configure -state normal
    if {[llength $level1] == 0} {
        $w.f.t insert end "\n  [t br_repetitions_empty]\n" dim_tag
    } else {
        $w.f.t insert end "\n  [t br_repetitions_level1]\n" heading_tag
        foreach row $level1 {
            lassign $row word1 line1 word2 line2 gap
            set _tag "rephit$_rn"; incr _rn
            $w.f.t insert end "  \"$word1\" ([t br_repetitions_line $line1])  ->  \"$word2\" ([t br_repetitions_line $line2])   [t br_repetitions_distance $gap]\n" [list dim_tag $_tag]
            $w.f.t tag bind $_tag <Button-1> "[list repetitions-jump $fpath $line1 $word1 $line2 $word2]; break"
            $w.f.t tag bind $_tag <Enter> [list $w.f.t configure -cursor hand2]
            $w.f.t tag bind $_tag <Leave> [list $w.f.t configure -cursor arrow]
        }
    }
    if {$::cfg_repetition_hidden} {
        if {[llength $level2] > 0} {
            $w.f.t insert end "\n  [t br_repetitions_level2]\n" heading_tag
            foreach row $level2 {
                lassign $row word1 line1 word2 line2 gap
                set _tag "rephit$_rn"; incr _rn
                $w.f.t insert end "  \"$word1\" ([t br_repetitions_line $line1])  ->  \"$word2\" ([t br_repetitions_line $line2])   [t br_repetitions_distance $gap]\n" [list dim_tag $_tag]
                $w.f.t tag bind $_tag <Button-1> "[list repetitions-jump $fpath $line1 $word1 $line2 $word2]; break"
                $w.f.t tag bind $_tag <Enter> [list $w.f.t configure -cursor hand2]
                $w.f.t tag bind $_tag <Leave> [list $w.f.t configure -cursor arrow]
            }
        }
    } else {
        $w.f.t insert end "\n  [t br_repetitions_hidden_off]\n" dim_tag
    }
    $w.f.t configure -state disabled

    pack $w.f.sb -side right -fill y
    pack $w.f.t  -side left  -fill both -expand 1

    button $w.ok -text "OK" -font $::font_sm -command [list destroy $w]

    pack $w.hdr -fill x
    pack $w.ok  -side bottom -anchor e -padx 8 -pady 6
    pack $w.f   -fill both -expand 1 -padx 2 -pady 2

    bind $w <Return> [list destroy $w]
    bind $w <Escape> [list destroy $w]
    bind $w <Destroy> [list repetitions-clear-highlight]
    update
    if {![winfo exists $w]} return
    catch {grab $w}
    focus $w.ok
    tkwait window $w
}

# Removes the repetition highlight from the editor (called when the
# Repetitions dialog closes).
proc repetitions-clear-highlight {} {
    catch { [primary-ed] tag remove repfound 1.0 end }
}

# Selects $word on $line in $t (if found) using the repfound highlight tag.
proc repetitions-highlight-word {t line word} {
    set last [lindex [split [$t index end] .] 0]
    if {$line < 1 || $line >= $last} return
    set pos [$t search -nocase -- $word "${line}.0" "${line}.end"]
    if {$pos ne ""} {
        $t tag add repfound $pos "$pos + [string length $word] chars"
    }
}

# Jumps to the first occurrence of a repetition in the editor, highlighting
# both repeated words, and makes the editor editable so the repetition can be
# fixed right away. Closes the Structure dialog (it would otherwise keep a
# grab blocking the editor) but leaves the Repetitions dialog open so the
# user can click through several rows without reopening it.
proc repetitions-jump {fpath line1 word1 line2 word2} {
    catch {destroy .adlg}
    catch {grab release .rpdlg}

    if {[file normalize $fpath] ne [file normalize $::filename] || ![winfo ismapped .ed]} {
        show-editor $fpath
    }

    set t [primary-ed]
    $t tag remove repfound 1.0 end
    $t tag configure repfound -background "#5a3a00" -foreground "#ffdd88"
    repetitions-highlight-word $t $line1 $word1
    repetitions-highlight-word $t $line2 $word2

    $t mark set insert "${line1}.0"
    $t see insert
    focus -force $t

    # The "a" cmd-mode keypress that opened the Structure dialog is still
    # waiting (nested tkwait through .adlg/.rpdlg) and only resets
    # gui_cmd_mode once .rpdlg closes; reset it now so the editor is
    # immediately editable.
    set ::gui_cmd_mode 0
    ed-status

    # Text's built-in <1> class binding (tk::TextButton1) runs after our tag
    # binding and unconditionally calls "focus" on .rpdlg.f.t, stealing focus
    # back; re-claim it once this event has fully finished processing.
    after idle [list focus -force $t]
}

proc spellcheck-dialog {fpath} {
    if {![file exists $fpath]} return

    set dict [spell-dict-resolve]
    set pipe [spell-pipe-get $dict]
    if {$pipe eq ""} {
        info-dialog [format [t br_spellcheck_unavailable] $dict]
        return
    }

    set w .spdlg
    catch {destroy $w}
    toplevel $w
    wm title $w [t br_spellcheck_title]
    wm geometry $w 520x420
    wm transient $w .

    label $w.hdr -text "[file tail $fpath]" -font [list [lindex $::font 0] [lindex $::font 1] bold] \
        -bg $::bg_bar -fg $::fg_bar -anchor w -padx 10 -pady 5
    pack $w.hdr -fill x

    label $w.wait -text "[t br_spellcheck_checking]" -bg $::bg -fg $::fg
    pack $w.wait -fill both -expand 1
    update

    set results [spell-check-document $fpath]
    destroy $w.wait

    frame $w.f -bg $::bg
    text $w.f.t -font $::font_sm -bg $::bg -fg $::fg -bd 0 -highlightthickness 0 \
        -yscrollcommand [list $w.f.sb set] -wrap none -width 66 -height 22 \
        -selectbackground $::bg_sel -selectforeground $::fg -cursor arrow -padx 10 -pady 6
    scrollbar $w.f.sb -orient vertical -command [list $w.f.t yview]

    $w.f.t tag configure dim_tag -foreground $::fg_bar

    set _rn 0
    $w.f.t configure -state normal
    if {[llength $results] == 0} {
        $w.f.t insert end "\n  [t br_spellcheck_empty]\n" dim_tag
    } else {
        $w.f.t insert end "\n" dim_tag
        foreach row $results {
            lassign $row word line sugg
            set _tag "rephit$_rn"; incr _rn
            if {[llength $sugg]} {
                set sugg_txt [t br_spellcheck_suggestions [join $sugg ", "]]
            } else {
                set sugg_txt [t br_spellcheck_no_suggestions]
            }
            $w.f.t insert end "  \"$word\" ([t br_repetitions_line $line])   $sugg_txt\n" [list dim_tag $_tag]
            $w.f.t tag bind $_tag <Button-1> "[list spellcheck-jump $fpath $line $word]; break"
            $w.f.t tag bind $_tag <Enter> [list $w.f.t configure -cursor hand2]
            $w.f.t tag bind $_tag <Leave> [list $w.f.t configure -cursor arrow]
        }
    }
    $w.f.t configure -state disabled

    pack $w.f.sb -side right -fill y
    pack $w.f.t  -side left  -fill both -expand 1

    button $w.ok -text "OK" -font $::font_sm -command [list destroy $w]

    pack $w.ok  -side bottom -anchor e -padx 8 -pady 6
    pack $w.f   -fill both -expand 1 -padx 2 -pady 2

    bind $w <Return> [list destroy $w]
    bind $w <Escape> [list destroy $w]
    bind $w <Destroy> [list repetitions-clear-highlight]
    update
    grab $w
    focus $w.ok
    tkwait window $w
}

# Single-word sibling of repetitions-jump: jumps to and highlights one
# misspelled word, leaving the Spelling dialog open for further clicks.
proc spellcheck-jump {fpath line word} {
    catch {destroy .adlg}
    catch {grab release .spdlg}

    if {[file normalize $fpath] ne [file normalize $::filename] || ![winfo ismapped .ed]} {
        show-editor $fpath
    }

    set t [primary-ed]
    $t tag remove repfound 1.0 end
    $t tag configure repfound -background "#5a3a00" -foreground "#ffdd88"
    repetitions-highlight-word $t $line $word

    $t mark set insert "${line}.0"
    $t see insert
    focus -force $t

    set ::gui_cmd_mode 0
    ed-status

    after idle [list focus -force $t]
}

# Displays synonyms for $word. Clicking a listed synonym re-runs this same
# dialog for that word (browsing the thesaurus), so the click handler is
# deferred with "after idle" to avoid destroying the window mid-callback.
proc synonyms-dialog {word} {
    if {![thes-available]} {
        info-dialog [format [t br_synonyms_unavailable] [spell-dict-resolve]]
        return
    }
    set entries [thes-lookup $word]

    set w .syndlg
    catch {destroy $w}
    toplevel $w
    wm title $w [t br_synonyms_title]
    wm geometry $w 420x380
    wm transient $w .

    label $w.hdr -text $word -font [list [lindex $::font 0] [lindex $::font 1] bold] \
        -bg $::bg_bar -fg $::fg_bar -anchor w -padx 10 -pady 5

    frame $w.f -bg $::bg
    text $w.f.t -font $::font_sm -bg $::bg -fg $::fg -bd 0 -highlightthickness 0 \
        -yscrollcommand [list $w.f.sb set] -wrap word -width 50 -height 20 \
        -selectbackground $::bg_sel -selectforeground $::fg -cursor arrow -padx 10 -pady 6
    scrollbar $w.f.sb -orient vertical -command [list $w.f.t yview]

    $w.f.t tag configure heading_tag -foreground $::cfg_color_heading
    $w.f.t tag configure dim_tag     -foreground $::fg_bar

    set _rn 0
    $w.f.t configure -state normal
    if {[llength $entries] == 0} {
        $w.f.t insert end "\n  [t br_synonyms_empty]\n" dim_tag
    } else {
        foreach entry $entries {
            lassign $entry cat syns
            $w.f.t insert end "\n  ($cat)\n" heading_tag
            foreach syn $syns {
                set _tag "synhit$_rn"; incr _rn
                $w.f.t insert end "    $syn\n" [list dim_tag $_tag]
                $w.f.t tag bind $_tag <Button-1> [list after idle [list synonyms-dialog $syn]]
                $w.f.t tag bind $_tag <Enter> [list $w.f.t configure -cursor hand2]
                $w.f.t tag bind $_tag <Leave> [list $w.f.t configure -cursor arrow]
            }
        }
    }
    $w.f.t configure -state disabled

    pack $w.f.sb -side right -fill y
    pack $w.f.t  -side left  -fill both -expand 1

    button $w.ok -text "OK" -font $::font_sm -command [list destroy $w]

    pack $w.hdr -fill x
    pack $w.ok  -side bottom -anchor e -padx 8 -pady 6
    pack $w.f   -fill both -expand 1 -padx 2 -pady 2

    bind $w <Return> [list destroy $w]
    bind $w <Escape> [list destroy $w]
    update
    if {![winfo exists $w]} return
    catch {grab $w}
    focus $w.ok
    tkwait window $w
}

# Prompts for a word (typed manually, e.g. from the Structure Analysis
# dialog) and opens synonyms-dialog for it.
proc synonyms-prompt {} {
    set word [string trim [input-dialog [t br_synonyms_title] [t br_synonyms_prompt]]]
    if {$word ne ""} { synonyms-dialog $word }
}

proc word-occurrences-dialog {fpath} {
    if {![file exists $fpath]} return

    set w .wodlg
    catch {destroy $w}
    toplevel $w
    wm title $w "Word Occurrences"
    wm geometry $w 400x500
    wm transient $w .

    set word_data [get-word-occurrences $fpath]
    if {[llength $word_data] == 0} {
        info-dialog "No words to display"
        return
    }

    catch {
        frame $w.f
        listbox $w.f.lb -font [list [lindex $::font 0] 9] -yscrollcommand [list $w.f.sb set] -width 50 -height 20
        scrollbar $w.f.sb -orient vertical -command [list $w.f.lb yview]

        foreach pair $word_data {
            lassign $pair word count
            $w.f.lb insert end [format "%-30s %6d" $word $count]
        }

        pack $w.f.sb -side right -fill y
        pack $w.f.lb -side left -fill both -expand 1
        pack $w.f -fill both -expand 1 -padx 8 -pady 8

        frame $w.btns
        button $w.btns.ok -text "Close" -font $::font_sm -command [list destroy $w]
        pack $w.btns.ok -padx 8 -pady 6
        pack $w.btns -fill x
    }

    update
    grab $w
    focus $w.f.lb
}

# --- TUI dialogs -----------------------------------------------------------

proc tui-word-occurrences {fpath rows cols} {
    if {![file exists $fpath]} return

    set word_data [get-word-occurrences $fpath]
    if {[llength $word_data] == 0} {
        tui-info-dialog [t br_stats_no_data] $rows $cols
        return
    }

    catch {
        set all_lines [list [list "  Word Occurrences" 1] [list "" 0] \
            [list [format "  %-30s %s" "Word" "Count"] 1]]
        foreach pair $word_data {
            lassign $pair word count
            lappend all_lines [list [format "  %-30s %6d" $word $count] 0]
        }

        set _usable [expr {$rows-4}]
        set _total [llength $all_lines]
        set _scroll 0
        set _w [expr {min(50, $cols-4)}]
        set _left [expr {max(0,($cols-$_w)/2)}]
        set _top  [expr {max(0,($rows-$_usable)/2)}]

        puts -nonewline "\033\[2J\033\[H"; flush stdout

        while 1 {
            set _max_scroll [expr {max(0, $_total - $_usable)}]
            if {$_scroll > $_max_scroll} { set _scroll $_max_scroll }
            if {$_scroll < 0} { set _scroll 0 }

            puts -nonewline "\033\[H"
            for {set _i 0} {$_i < $_usable} {incr _i} {
                set _idx [expr {$_scroll + $_i}]
                if {$_idx < $_total} {
                    tui-move [expr {$_top+$_i}] $_left
                    lassign [lindex $all_lines $_idx] _txt _inv
                    if {$_inv} { tui-attr reverse }
                    puts -nonewline "[string range $_txt 0 [expr {$_w-1}]]\033\[K"
                    if {$_inv} { tui-attr off }
                } else {
                    tui-move [expr {$_top+$_i}] $_left
                    puts -nonewline "\033\[K"
                }
            }
            tui-bar [expr {$rows-1}] "  UP/DOWN scroll  q close" "" $cols
            flush stdout

            set _k ""; while {$_k eq ""} { set _k [tui-getch] }
            switch -- $_k {
                q { break }
                UP - k { incr _scroll -1 }
                DOWN - j { incr _scroll 1 }
                HOME { set _scroll 0 }
                END { set _scroll [expr {max(0, $_total - $_usable)}] }
                default {
                    if {$_k eq $::cfg_tui_help} { break }
                }
            }
        }
    }
}

proc tui-analyse-dialog {fpath rows cols} {
    set data [analyse-data $fpath]
    if {$data eq {}} return
    lassign $data total nsec sdata
    set ::tui_rep_jump ""

    set all_lines {}
    lappend all_lines [list "  [t br_analyse_title] -- [file tail $fpath]" 1]
    lappend all_lines [list "" 0]

    if {$total == 0} {
        lappend all_lines [list "  [t br_analyse_empty]" 0]
    } else {
        set max_bar 25
        foreach row $sdata {
            lassign $row indent level title words pct
            set bar [string repeat "|" [expr {max(1, round($pct * $max_bar / 100.0))}]]
            set lbl [expr {$title eq "" ? [t br_analyse_intro] : $title}]
            set lvl_str [expr {$level > 0 ? "H$level" : "   "}]
            lappend all_lines [list "${indent}  ${lvl_str} ${lbl}" 1]
            lappend all_lines [list "${indent}      ${bar} ${words}w (${pct}%)" 0]
            lappend all_lines [list "" 0]
        }
        lappend all_lines [list "  [t br_analyse_total $total $nsec]" 0]
    }

    set _usable [expr {$rows - 4}]
    set _total  [llength $all_lines]
    set _scroll 0

    puts -nonewline "\033\[2J\033\[H"; flush stdout

    while 1 {
        set _max_scroll [expr {max(0, $_total - $_usable)}]
        if {$_scroll > $_max_scroll} { set _scroll $_max_scroll }
        if {$_scroll < 0}           { set _scroll 0 }

        puts -nonewline "\033\[H"
        for {set _i 0} {$_i < $_usable} {incr _i} {
            set _idx [expr {$_scroll + $_i}]
            if {$_idx < $_total} {
                tui-move $_i 0
                lassign [lindex $all_lines $_idx] _txt _inv
                if {$_inv} { tui-attr reverse }
                puts -nonewline "[string range $_txt 0 [expr {$cols - 1}]]\033\[K"
                if {$_inv} { tui-attr off }
            } else {
                tui-move $_i 0
                puts -nonewline "\033\[K"
            }
        }
        tui-bar [expr {$rows - 1}] "  UP/DOWN scroll  r:repetitions  w:words  o:spelling  y:synonyms  q close" "" $cols
        flush stdout

        set _k ""; while {$_k eq ""} { set _k [tui-getch] }
        switch -- $_k {
            q       { break }
            r       { tui-repetitions-dialog $fpath $rows $cols
                      if {$::tui_rep_jump ne ""} { break } }
            w       { tui-word-occurrences $fpath $rows $cols
                      puts -nonewline "\033\[2J\033\[H"; flush stdout }
            o       { tui-spellcheck-dialog $fpath $rows $cols
                      if {$::tui_rep_jump ne ""} { break }
                      puts -nonewline "\033\[2J\033\[H"; flush stdout }
            y       { set _word [string trim [tui-prompt [t br_synonyms_prompt] $rows $cols]]
                      puts -nonewline "\033\[2J\033\[H"; flush stdout
                      if {$_word ne ""} {
                          tui-synonyms-dialog $_word $rows $cols
                          puts -nonewline "\033\[2J\033\[H"; flush stdout
                      } }
            UP - k  { incr _scroll -1 }
            DOWN - j { incr _scroll 1 }
            HOME    { set _scroll 0 }
            END     { set _scroll [expr {max(0, $_total - $_usable)}] }
            default { if {$_k eq $::cfg_tui_help} { break } }
        }
    }
}

proc tui-repetitions-dialog {fpath rows cols} {
    lassign [find-repetitions $fpath] level1 level2

    # Each entry: {text inv jumpline} - jumpline is the target line number
    # for ENTER on this row, or "" for headings/non-selectable rows.
    set all_lines {}
    lappend all_lines [list "  [t br_repetitions_title] -- [file tail $fpath]" 1 ""]
    lappend all_lines [list "" 0 ""]

    if {[llength $level1] == 0} {
        lappend all_lines [list "  [t br_repetitions_empty]" 0 ""]
    } else {
        lappend all_lines [list "  [t br_repetitions_level1]" 1 ""]
        foreach row $level1 {
            lassign $row word1 line1 word2 line2 gap
            lappend all_lines [list "  \"$word1\" ([t br_repetitions_line $line1])  ->  \"$word2\" ([t br_repetitions_line $line2])   [t br_repetitions_distance $gap]" 0 $line1]
        }
    }

    if {$::cfg_repetition_hidden} {
        if {[llength $level2] > 0} {
            lappend all_lines [list "" 0 ""]
            lappend all_lines [list "  [t br_repetitions_level2]" 1 ""]
            foreach row $level2 {
                lassign $row word1 line1 word2 line2 gap
                lappend all_lines [list "  \"$word1\" ([t br_repetitions_line $line1])  ->  \"$word2\" ([t br_repetitions_line $line2])   [t br_repetitions_distance $gap]" 0 $line1]
            }
        }
    } else {
        lappend all_lines [list "" 0 ""]
        lappend all_lines [list "  [t br_repetitions_hidden_off]" 0 ""]
    }

    set _usable [expr {$rows - 4}]
    set _total  [llength $all_lines]
    set _scroll 0

    # first selectable (jumpable) row, if any
    set _cur -1
    for {set _i 0} {$_i < $_total} {incr _i} {
        if {[lindex [lindex $all_lines $_i] 2] ne ""} { set _cur $_i; break }
    }

    puts -nonewline "\033\[2J\033\[H"; flush stdout

    while 1 {
        if {$_cur >= 0} {
            if {$_cur < $_scroll}             { set _scroll $_cur }
            if {$_cur >= $_scroll + $_usable} { set _scroll [expr {$_cur - $_usable + 1}] }
        }
        set _max_scroll [expr {max(0, $_total - $_usable)}]
        if {$_scroll > $_max_scroll} { set _scroll $_max_scroll }
        if {$_scroll < 0}            { set _scroll 0 }

        puts -nonewline "\033\[H"
        for {set _i 0} {$_i < $_usable} {incr _i} {
            set _idx [expr {$_scroll + $_i}]
            if {$_idx < $_total} {
                tui-move $_i 0
                lassign [lindex $all_lines $_idx] _txt _inv _jl
                if {$_idx == $_cur} { tui-attr sel } elseif {$_inv} { tui-attr reverse }
                puts -nonewline "[string range $_txt 0 [expr {$cols - 1}]]\033\[K"
                if {$_idx == $_cur || $_inv} { tui-attr off }
            } else {
                tui-move $_i 0
                puts -nonewline "\033\[K"
            }
        }
        if {$_cur >= 0} {
            tui-bar [expr {$rows - 1}] "  UP/DOWN select  ENTER jump  q close" "" $cols
        } else {
            tui-bar [expr {$rows - 1}] "  UP/DOWN scroll  q close" "" $cols
        }
        flush stdout

        set _k ""; while {$_k eq ""} { set _k [tui-getch] }
        switch -- $_k {
            q { break }
            ENTER {
                if {$_cur >= 0} {
                    set ::tui_rep_jump [lindex [lindex $all_lines $_cur] 2]
                    break
                }
            }
            UP - k {
                if {$_cur >= 0} {
                    for {set _i [expr {$_cur - 1}]} {$_i >= 0} {incr _i -1} {
                        if {[lindex [lindex $all_lines $_i] 2] ne ""} { set _cur $_i; break }
                    }
                } else { incr _scroll -1 }
            }
            DOWN - j {
                if {$_cur >= 0} {
                    for {set _i [expr {$_cur + 1}]} {$_i < $_total} {incr _i} {
                        if {[lindex [lindex $all_lines $_i] 2] ne ""} { set _cur $_i; break }
                    }
                } else { incr _scroll 1 }
            }
            HOME {
                if {$_cur >= 0} {
                    for {set _i 0} {$_i < $_total} {incr _i} {
                        if {[lindex [lindex $all_lines $_i] 2] ne ""} { set _cur $_i; break }
                    }
                } else { set _scroll 0 }
            }
            END {
                if {$_cur >= 0} {
                    for {set _i [expr {$_total - 1}]} {$_i >= 0} {incr _i -1} {
                        if {[lindex [lindex $all_lines $_i] 2] ne ""} { set _cur $_i; break }
                    }
                } else { set _scroll [expr {max(0, $_total - $_usable)}] }
            }
            default { if {$_k eq $::cfg_tui_help} { break } }
        }
    }
}

proc tui-spellcheck-dialog {fpath rows cols} {
    set dict [spell-dict-resolve]
    set pipe [spell-pipe-get $dict]
    if {$pipe eq ""} {
        tui-info-dialog [format [t br_spellcheck_unavailable] $dict] $rows $cols
        return
    }

    set _msg "  [t br_spellcheck_checking]  "
    puts -nonewline "\033\[2J\033\[H"
    tui-move [expr {$rows/2}] [expr {max(0, ($cols - [string length $_msg])/2)}]
    tui-attr reverse
    puts -nonewline $_msg
    tui-attr off
    flush stdout

    set results [spell-check-document $fpath]

    # Each entry: {text inv jumpline} - jumpline is the target line number
    # for ENTER on this row, or "" for headings/non-selectable rows.
    set all_lines {}
    lappend all_lines [list "  [t br_spellcheck_title] -- [file tail $fpath]" 1 ""]
    lappend all_lines [list "" 0 ""]

    if {[llength $results] == 0} {
        lappend all_lines [list "  [t br_spellcheck_empty]" 0 ""]
    } else {
        foreach row $results {
            lassign $row word line sugg
            if {[llength $sugg]} {
                set sugg_txt [t br_spellcheck_suggestions [join $sugg ", "]]
            } else {
                set sugg_txt [t br_spellcheck_no_suggestions]
            }
            lappend all_lines [list "  \"$word\" ([t br_repetitions_line $line])   $sugg_txt" 0 $line]
        }
    }

    set _usable [expr {$rows - 4}]
    set _total  [llength $all_lines]
    set _scroll 0

    # first selectable (jumpable) row, if any
    set _cur -1
    for {set _i 0} {$_i < $_total} {incr _i} {
        if {[lindex [lindex $all_lines $_i] 2] ne ""} { set _cur $_i; break }
    }

    puts -nonewline "\033\[2J\033\[H"; flush stdout

    while 1 {
        if {$_cur >= 0} {
            if {$_cur < $_scroll}             { set _scroll $_cur }
            if {$_cur >= $_scroll + $_usable} { set _scroll [expr {$_cur - $_usable + 1}] }
        }
        set _max_scroll [expr {max(0, $_total - $_usable)}]
        if {$_scroll > $_max_scroll} { set _scroll $_max_scroll }
        if {$_scroll < 0}            { set _scroll 0 }

        puts -nonewline "\033\[H"
        for {set _i 0} {$_i < $_usable} {incr _i} {
            set _idx [expr {$_scroll + $_i}]
            if {$_idx < $_total} {
                tui-move $_i 0
                lassign [lindex $all_lines $_idx] _txt _inv _jl
                if {$_idx == $_cur} { tui-attr sel } elseif {$_inv} { tui-attr reverse }
                puts -nonewline "[string range $_txt 0 [expr {$cols - 1}]]\033\[K"
                if {$_idx == $_cur || $_inv} { tui-attr off }
            } else {
                tui-move $_i 0
                puts -nonewline "\033\[K"
            }
        }
        if {$_cur >= 0} {
            tui-bar [expr {$rows - 1}] "  UP/DOWN select  ENTER jump  q close" "" $cols
        } else {
            tui-bar [expr {$rows - 1}] "  UP/DOWN scroll  q close" "" $cols
        }
        flush stdout

        set _k ""; while {$_k eq ""} { set _k [tui-getch] }
        switch -- $_k {
            q { break }
            ENTER {
                if {$_cur >= 0} {
                    set ::tui_rep_jump [lindex [lindex $all_lines $_cur] 2]
                    break
                }
            }
            UP - k {
                if {$_cur >= 0} {
                    for {set _i [expr {$_cur - 1}]} {$_i >= 0} {incr _i -1} {
                        if {[lindex [lindex $all_lines $_i] 2] ne ""} { set _cur $_i; break }
                    }
                } else { incr _scroll -1 }
            }
            DOWN - j {
                if {$_cur >= 0} {
                    for {set _i [expr {$_cur + 1}]} {$_i < $_total} {incr _i} {
                        if {[lindex [lindex $all_lines $_i] 2] ne ""} { set _cur $_i; break }
                    }
                } else { incr _scroll 1 }
            }
            HOME {
                if {$_cur >= 0} {
                    for {set _i 0} {$_i < $_total} {incr _i} {
                        if {[lindex [lindex $all_lines $_i] 2] ne ""} { set _cur $_i; break }
                    }
                } else { set _scroll 0 }
            }
            END {
                if {$_cur >= 0} {
                    for {set _i [expr {$_total - 1}]} {$_i >= 0} {incr _i -1} {
                        if {[lindex [lindex $all_lines $_i] 2] ne ""} { set _cur $_i; break }
                    }
                } else { set _scroll [expr {max(0, $_total - $_usable)}] }
            }
            default { if {$_k eq $::cfg_tui_help} { break } }
        }
    }
}

# TUI counterpart of synonyms-dialog. ENTER on a listed synonym re-invokes
# this proc for that word (browsing the thesaurus), mirroring the GUI's
# click-through; the recursive call returns to this level on "q".
proc tui-synonyms-dialog {word rows cols} {
    if {![thes-available]} {
        tui-info-dialog [format [t br_synonyms_unavailable] [spell-dict-resolve]] $rows $cols
        return
    }
    set entries [thes-lookup $word]

    # Each entry: {text inv jumpword} - jumpword is the synonym to look up
    # next on ENTER, or "" for headings/non-selectable rows.
    set all_lines {}
    lappend all_lines [list "  [t br_synonyms_title] -- $word" 1 ""]
    lappend all_lines [list "" 0 ""]

    if {[llength $entries] == 0} {
        lappend all_lines [list "  [t br_synonyms_empty]" 0 ""]
    } else {
        foreach entry $entries {
            lassign $entry cat syns
            lappend all_lines [list "  ($cat)" 1 ""]
            foreach syn $syns {
                lappend all_lines [list "    $syn" 0 $syn]
            }
            lappend all_lines [list "" 0 ""]
        }
    }

    set _usable [expr {$rows - 4}]
    set _total  [llength $all_lines]
    set _scroll 0

    set _cur -1
    for {set _i 0} {$_i < $_total} {incr _i} {
        if {[lindex [lindex $all_lines $_i] 2] ne ""} { set _cur $_i; break }
    }

    puts -nonewline "\033\[2J\033\[H"; flush stdout

    while 1 {
        if {$_cur >= 0} {
            if {$_cur < $_scroll}             { set _scroll $_cur }
            if {$_cur >= $_scroll + $_usable} { set _scroll [expr {$_cur - $_usable + 1}] }
        }
        set _max_scroll [expr {max(0, $_total - $_usable)}]
        if {$_scroll > $_max_scroll} { set _scroll $_max_scroll }
        if {$_scroll < 0}            { set _scroll 0 }

        puts -nonewline "\033\[H"
        for {set _i 0} {$_i < $_usable} {incr _i} {
            set _idx [expr {$_scroll + $_i}]
            if {$_idx < $_total} {
                tui-move $_i 0
                lassign [lindex $all_lines $_idx] _txt _inv _jw
                if {$_idx == $_cur} { tui-attr sel } elseif {$_inv} { tui-attr reverse }
                puts -nonewline "[string range $_txt 0 [expr {$cols - 1}]]\033\[K"
                if {$_idx == $_cur || $_inv} { tui-attr off }
            } else {
                tui-move $_i 0
                puts -nonewline "\033\[K"
            }
        }
        if {$_cur >= 0} {
            tui-bar [expr {$rows - 1}] "  UP/DOWN select  ENTER look up  q close" "" $cols
        } else {
            tui-bar [expr {$rows - 1}] "  UP/DOWN scroll  q close" "" $cols
        }
        flush stdout

        set _k ""; while {$_k eq ""} { set _k [tui-getch] }
        switch -- $_k {
            q { break }
            ENTER {
                if {$_cur >= 0} {
                    tui-synonyms-dialog [lindex [lindex $all_lines $_cur] 2] $rows $cols
                    puts -nonewline "\033\[2J\033\[H"; flush stdout
                }
            }
            UP - k {
                if {$_cur >= 0} {
                    for {set _i [expr {$_cur - 1}]} {$_i >= 0} {incr _i -1} {
                        if {[lindex [lindex $all_lines $_i] 2] ne ""} { set _cur $_i; break }
                    }
                } else { incr _scroll -1 }
            }
            DOWN - j {
                if {$_cur >= 0} {
                    for {set _i [expr {$_cur + 1}]} {$_i < $_total} {incr _i} {
                        if {[lindex [lindex $all_lines $_i] 2] ne ""} { set _cur $_i; break }
                    }
                } else { incr _scroll 1 }
            }
            HOME {
                if {$_cur >= 0} {
                    for {set _i 0} {$_i < $_total} {incr _i} {
                        if {[lindex [lindex $all_lines $_i] 2] ne ""} { set _cur $_i; break }
                    }
                } else { set _scroll 0 }
            }
            END {
                if {$_cur >= 0} {
                    for {set _i [expr {$_total - 1}]} {$_i >= 0} {incr _i -1} {
                        if {[lindex [lindex $all_lines $_i] 2] ne ""} { set _cur $_i; break }
                    }
                } else { set _scroll [expr {max(0, $_total - $_usable)}] }
            }
            default { if {$_k eq $::cfg_tui_help} { break } }
        }
    }
}

# ===========================================================================
# subdirs.tcl
# ===========================================================================
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

# ===========================================================================
# tui.tcl
# ===========================================================================

# --- TUI mode -----------------------------------------------------------------

set ::tui_stty ""

proc tui-reverse-video {on} {
    puts -nonewline [expr {$on ? "\033\[?5h" : "\033\[?5l"}]
    flush stdout
}

proc tui-init {} {
    catch { set ::tui_stty [exec stty -g <@stdin] }
    catch { exec stty raw -echo <@stdin }
    chan configure stdin  -blocking 1 -translation binary -buffering none
    chan configure stdout -encoding utf-8 -buffering full
    puts -nonewline "\033\[?25l\033\[2J\033\[?2004h"
    set _cq [expr {$::cfg_block_cursor_console \
        ? ($::cfg_blink_cursor ? 1 : 2) \
        : ($::cfg_blink_cursor ? 5 : 6)}]
    puts -nonewline "\033\[${_cq} q"
    unset _cq
    tui-reverse-video [expr {!$::cfg_dark_mode}]
}

proc tui-cleanup {} {
    puts -nonewline "\033\[0 q\033\[?5l\033\[?2004l\033\[?25h\033\[2J\033\[H"
    flush stdout
    if {$::tui_stty ne ""} { catch {exec stty $::tui_stty <@stdin}
    } else                 { catch {exec stty sane <@stdin} }
}

set ::tui_size_cache {24 80}
set ::tui_size_n     14

proc tui-size {} {
    if {[incr ::tui_size_n] >= 15} {
        set ::tui_size_n 0
        if {![catch {scan [exec stty size <@stdin] "%d %d" r c}]} {
            set ::tui_size_cache [list $r $c]
        }
    }
    return $::tui_size_cache
}

proc tui-move {row col} { puts -nonewline "\033\[[expr {$row+1}];[expr {$col+1}]H" }

# Returns ANSI color escape for a named or numeric color.
# name: color name (black..white, bright_*) or numeric 0-255 (in 256-color mode).
# is_bg: 1 for background, 0 for foreground.  Returns "" for unknown/empty.
# In 16-color mode: fg=30-37/90-97, bg=40-47/100-107.
# In 256-color mode (cfg_tui_256colors): fg=38;5;N, bg=48;5;N — brights always distinct.
proc tui-ansi-color {name is_bg} {
    switch [string tolower [string map {- _ " " _} $name]] {
        black          { set n 0 }
        red            { set n 1 }
        green          { set n 2 }
        yellow         { set n 3 }
        blue           { set n 4 }
        magenta        { set n 5 }
        cyan           { set n 6 }
        white          { set n 7 }
        bright_black - gray - grey { set n 8 }
        bright_red     { set n 9 }
        bright_green   { set n 10 }
        bright_yellow  { set n 11 }
        bright_blue    { set n 12 }
        bright_magenta { set n 13 }
        bright_cyan    { set n 14 }
        bright_white   { set n 15 }
        default {
            if {$::cfg_tui_256colors && [string is integer -strict $name] \
                    && $name >= 0 && $name <= 255} {
                set n $name
            } else { return "" }
        }
    }
    if {$::cfg_tui_256colors} {
        return "\033\[[expr {$is_bg ? 48 : 38}];5;${n}m"
    }
    set base [expr {$is_bg ? 40 : 30}]
    if {$n < 8} { return "\033\[[expr {$base + $n}]m" }
    return "\033\[[expr {$base + 60 + $n - 8}]m"
}

proc tui-attr {a} {
    switch $a {
        bold     { puts -nonewline "\033\[1m" }
        heading  {
            if {$::cfg_tui_colors && $::cfg_tui_col_heading ne ""} {
                set _c [tui-ansi-color $::cfg_tui_col_heading 0]
                puts -nonewline "\033\[1m${_c}"
            } else {
                puts -nonewline "\033\[1m"
            }
        }
        dim-text {
            if {$::cfg_tui_colors && $::cfg_tui_col_comment ne ""} {
                set _c [tui-ansi-color $::cfg_tui_col_comment 0]
                if {$_c ne ""} { puts -nonewline $_c } else { puts -nonewline "\033\[2m" }
            } else {
                puts -nonewline "\033\[2m"
            }
        }
        markup-line {
            if {$::cfg_tui_colors && $::cfg_tui_col_markup ne ""} {
                set _c [tui-ansi-color $::cfg_tui_col_markup 0]
                if {$_c ne ""} { puts -nonewline $_c }
            }
        }
        dim      { puts -nonewline "\033\[2m" }
        underline { puts -nonewline "\033\[4m" }
        reverse  { puts -nonewline "\033\[7m" }
        sel {
            if {$::cfg_tui_colors && $::cfg_tui_col_sel_bg ne ""} {
                set _c [tui-ansi-color $::cfg_tui_col_sel_bg 1]
                if {$_c ne ""} { puts -nonewline "\033\[0m${_c}"; return }
            }
            # In light mode (DECSCNM active), code 7 double-inverts back to normal appearance.
            # Add underline (code 4) as a mode-independent visible indicator.
            puts -nonewline [expr {$::cfg_dark_mode ? "\033\[7m" : "\033\[7;4m"}]
        }
        off      { puts -nonewline "\033\[0m" }
    }
}

proc tui-parse-inline-spans {line} {
    set spans {}
    set llen [string length $line]
    foreach {tag re mlen marker} [list \
            bold          $::cached_bold_re          $::cached_bold_mlen          $::cfg_bold_marker \
            italic        $::cached_italic_re        $::cached_italic_mlen        $::cfg_italic_marker \
            underline     $::cached_underline_re     $::cached_underline_mlen     $::cfg_underline_marker \
            strikethrough $::cached_strikethrough_re $::cached_strikethrough_mlen $::cfg_strikethrough_marker] {
        if {$re eq "" || [string first $marker $line] < 0} continue
        set s 0
        while {[regexp -start $s -indices -- $re $line m]} {
            lassign $m a b
            set pre  [expr {$a > 0       ? [string index $line [expr {$a-1}]] : ""}]
            set post [expr {$b+1 < $llen ? [string index $line [expr {$b+1}]] : ""}]
            if {($pre eq "" || ![string is alnum $pre]) &&
                ($post eq "" || ![string is alnum $post]) &&
                ![string is space [string index $line [expr {$a+$mlen}]]] &&
                ![string is space [string index $line [expr {$b-$mlen}]]]} {
                lappend spans [list $a          [expr {$a+$mlen-1}]  marker]
                lappend spans [list [expr {$a+$mlen}] [expr {$b-$mlen}] $tag]
                lappend spans [list [expr {$b-$mlen+1}] $b            marker]
            }
            set s [expr {$b+1}]
        }
    }
    return $spans
}

proc tui-inline-esc {style in_sel} {
    set codes {}
    set color_esc ""
    set sel_esc   ""
    switch $style {
        bold          { lappend codes 1 }
        italic        { lappend codes 3 }
        underline     { lappend codes 4 }
        strikethrough -
        marker        { lappend codes 2 }
    }
    if {$::cfg_tui_colors && $::cfg_tui_col_markup ne "" && $style ne ""} {
        set color_esc [tui-ansi-color $::cfg_tui_col_markup 0]
    }
    if {$in_sel} {
        if {$::cfg_tui_colors && $::cfg_tui_col_sel_bg ne ""} {
            set sel_esc [tui-ansi-color $::cfg_tui_col_sel_bg 1]
        } else {
            lappend codes 7
            if {!$::cfg_dark_mode} { lappend codes 4 }
        }
    }
    if {$codes eq {} && $color_esc eq "" && $sel_esc eq ""} { return "" }
    set esc [expr {$codes ne {} ? "\033\[[join $codes {;}]m" : ""}]
    return "${esc}${color_esc}${sel_esc}"
}

proc tui-render-inline-seg {seg scol spans sf st} {
    set slen [string length $seg]
    set char_style [lrepeat $slen ""]
    foreach sp $spans {
        lassign $sp sa sb stype
        for {set k [expr {max(0, $sa-$scol)}]} {$k <= [expr {min($slen-1, $sb-$scol)}]} {incr k} {
            if {[lindex $char_style $k] eq ""} { lset char_style $k $stype }
        }
    }
    set result ""
    set prev_esc ""
    for {set k 0} {$k < $slen} {incr k} {
        set in_sel [expr {$sf >= 0 && $k >= $sf && $k < $st}]
        set esc [tui-inline-esc [lindex $char_style $k] $in_sel]
        if {$esc ne $prev_esc} {
            if {$prev_esc ne ""} { append result "\033\[0m" }
            if {$esc ne ""} { append result $esc }
            set prev_esc $esc
        }
        append result [string index $seg $k]
    }
    if {$prev_esc ne ""} { append result "\033\[0m" }
    puts -nonewline $result
}

proc tui-fill {row text cols} {
    tui-move $row 0
    set text [string range $text 0 [expr {$cols-1}]]
    puts -nonewline "${text}[string repeat { } [expr {$cols - [string length $text]}]]"
}

proc tui-bar {row left right cols {center ""}} {
    if {$::cfg_tui_colors && ($::cfg_tui_col_bar_bg ne "" || $::cfg_tui_col_bar_fg ne "")} {
        puts -nonewline "\033\[0m"
        puts -nonewline [tui-ansi-color $::cfg_tui_col_bar_bg 1]
        puts -nonewline [tui-ansi-color $::cfg_tui_col_bar_fg 0]
    } else {
        tui-attr reverse
    }
    set llen [string length $left]
    set rlen [string length $right]
    set clen [string length $center]
    if {$clen > 0} {
        set cstart [expr {($cols - $clen) / 2}]
        set gap1   [expr {max(0, $cstart - $llen)}]
        set gap2   [expr {max(0, $cols - $llen - $gap1 - $clen - $rlen)}]
        set txt "${left}[string repeat { } $gap1]${center}[string repeat { } $gap2]${right}"
    } else {
        set gap [expr {max(0, $cols - $llen - $rlen)}]
        set txt "${left}[string repeat { } $gap]${right}"
    }
    tui-fill $row $txt $cols
    tui-attr off
}

proc tui-help {row text cols {zone left}} {
    tui-attr dim
    switch $zone {
        right  {
            set pad [expr {max(0, $cols - [string length $text] - 1)}]
            tui-fill $row "[string repeat { } $pad]$text " $cols
        }
        center {
            set pad [expr {max(0, ($cols - [string length $text]) / 2)}]
            tui-fill $row "[string repeat { } $pad]$text" $cols
        }
        default { tui-fill $row " $text" $cols }
    }
    tui-attr off
}

proc tui-help-dialog {rows cols wc cc {sel_wc -1} {sel_cc -1}} {
    set lbl_save   $::cfg_lbl_save;   set lbl_close  $::cfg_lbl_close
    set lbl_undo   $::cfg_lbl_undo;   set lbl_selall $::cfg_lbl_sel_all
    set lbl_sticky $::cfg_lbl_sticky; set lbl_copy   $::cfg_lbl_copy
    set lbl_find   $::cfg_lbl_find;   set lbl_cut    [key-label $::cfg_key_cut]
    set lbl_repl   $::cfg_lbl_replace; set lbl_paste $::cfg_lbl_paste
    set lbl_goto   $::cfg_lbl_goto;   set lbl_lnum   $::cfg_lbl_line_nums
    set lbl_open   $::cfg_lbl_open;   set lbl_toc    $::cfg_lbl_toc
    set lbl_help   $::cfg_lbl_help
    set lbl_redo   $::cfg_lbl_redo;   set lbl_tw     $::cfg_lbl_typewriter
    set _ts [clock seconds]
    set _e ""
    # two-column line: key(10) + action(19) | key(10) + action
    set f2 "  %-10s %-19s%-10s %s"
    # Each entry: {text inv} - inv=1 renders in reverse video
    set lines [list \
        [list "  WrithDeck" 1] \
        [list "  $::version" 0] \
        [list "" 0] \
        [list "  [t help_date_time]" 1] \
        [list [format "  [t help_cur_time]" \
            [clock format $_ts -format "%H:%M:%S"] \
            [clock format $_ts -format "%Y-%m-%d"]] 0] \
        [list "" 0] \
    ]
    if {$sel_wc >= 0} {
        lappend lines [list "  [t help_sel_info]" 1]
        lappend lines [list [format "  [t help_words_chars]" $sel_wc $sel_cc] 0]
        lappend lines [list "" 0]
    }
    set hm $::cfg_heading_marker
    set fb "  %-14s %s"
    if {$wc > 0} {
        set _today_wc [daily-today $wc]
        set _goal_str [expr {$::cfg_word_goal > 0 ? " / $::cfg_word_goal" : ""}]
        lappend lines \
            [list "  [t help_file_info]" 1] \
            [list [format "  [t help_words_chars]" $wc $cc] 0] \
            [list "  [t br_stats_today]: +${_today_wc}${_goal_str}" 0] \
            [list "" 0]
    }
    lappend lines \
        [list "  EDITOR" 1] \
        [list "" 0] \
        [list [format $f2 $lbl_save   [t help_k_save]    $lbl_undo   [t help_k_undo]]    0] \
        [list [format $f2 $_e         $_e                $lbl_redo   [t help_k_redo]]    0] \
        [list [format $f2 $lbl_close  [t help_k_close]   $lbl_selall [t help_k_sel_all]] 0] \
        [list [format $f2 $lbl_sticky [t help_k_sticky]  $lbl_copy   [t help_k_copy]]   0] \
        [list [format $f2 $lbl_find   [t help_k_find]    $lbl_cut    [t help_k_cut]]    0] \
        [list [format $f2 $lbl_repl   [t help_k_replace] $lbl_paste  [t help_k_paste]]  0] \
        [list [format $f2 $lbl_goto   [t help_k_goto]    $lbl_lnum   [t help_k_lnum]]   0] \
        [list [format $f2 $lbl_open   [t help_k_open]    $lbl_tw     [t help_k_typewriter]] 0] \
        [list "" 0] \
        [list [format "  %-16s %s" [t help_k_ctrl_arrows] ""] 0] \
        [list [format "  %-16s %s" $lbl_toc  [t help_k_toc]]  0] \
        [list [format "  %-16s %s" $::cfg_lbl_workspace [t help_k_workspace]] 0] \
        [list [format "  %-16s %s" $lbl_help [t help_k_help]] 0] \
        [list "" 0] \
        [list "  BROWSER" 1] \
        [list "" 0] \
        [list [format $fb "Enter"          "Open file"]                0] \
        [list [format $fb "n"              "New file"]                 0] \
        [list [format $fb "t"              "Scratchpad"]               0] \
        [list [format $fb "f"              "Toggle favorite"]          0] \
        [list [format $fb "b"              "Backup (backups/ folder)"] 0] \
        [list [format $fb "i"              "Show full path"]           0] \
        [list [format $fb "d"              "Delete"]                   0] \
        [list [format $fb "r"              "Rename"]                   0] \
        [list [format $fb $lbl_toc         "Browser sections"]         0] \
        [list [format $fb $lbl_open        "Open any file"]            0] \
        [list [format $fb "h / $lbl_help"  "Help"]                     0] \
        [list [format $fb "q / Ctrl+Q"     "Quit"]                     0] \
        [list "" 0]
    set h [llength $lines]
    set w 60
    set left   [expr {max(0, ($cols - $w) / 2)}]
    set usable [expr {$rows - 2}]
    set scroll 0

    puts -nonewline "\033\[2J\033\[H"; flush stdout

    while 1 {
        set max_scroll [expr {max(0, $h - $usable)}]
        puts -nonewline "\033\[H"
        for {set i 0} {$i < $usable} {incr i} {
            set li [expr {$scroll + $i}]
            set row_y [expr {$i + 1}]
            if {$li < $h} {
                tui-move $row_y $left
                lassign [lindex $lines $li] txt inv
                if {$inv} { tui-attr reverse }
                puts -nonewline "[string range $txt 0 [expr {$w-1}]]\033\[K"
                if {$inv} { tui-attr off }
            } else {
                tui-move $row_y 0; puts -nonewline "\033\[K"
            }
        }
        set hint [expr {$max_scroll > 0 ? "  Up/Dn scroll   q / Ctrl+H  close" : "  q / Ctrl+H  close"}]
        tui-bar [expr {$rows-1}] $hint "" $cols
        flush stdout
        set key [tui-getch]
        if {$key eq "q" || $key eq $::cfg_tui_help} break
        if {$key eq "UP"   && $scroll > 0}            { incr scroll -1 }
        if {$key eq "DOWN" && $scroll < $max_scroll}  { incr scroll  1 }
    }
}

proc tui-getch {{timeout -1}} {
    set _block 0
    if {$timeout < 0} {
        if {$::timer_active && $::cfg_chrono_show} {
            set timeout 50
        } else {
            set _block 1
            set timeout 0
        }
    }
    chan configure stdin -blocking 0
    set raw [read stdin 1]
    chan configure stdin -blocking 1
    if {$raw eq ""} {
        if {$timeout > 0} {
            after $timeout
            chan configure stdin -blocking 0
            set raw [read stdin 1]
            chan configure stdin -blocking 1
        } elseif {$_block} {
            set raw [read stdin 1]
        }
        if {$raw eq ""} { return "" }
    }
    scan $raw %c b
    if {$b == 27} {
        # Read escape sequence byte by byte
        set seq ""
        chan configure stdin -blocking 0; set ch [read stdin 1]; chan configure stdin -blocking 1
        if {$ch eq ""} { return ESC }
        append seq $ch
        switch -- $ch {
            O {
                # SS3 sequence (xterm F1-F4): read one more byte
                chan configure stdin -blocking 0; set ch2 [read stdin 1]; chan configure stdin -blocking 1
                if {$ch2 ne ""} { append seq $ch2 }
            }
            {[} {
                # CSI sequence: read until letter or ~
                while {[string length $seq] < 20} {
                    chan configure stdin -blocking 0; set ch [read stdin 1]; chan configure stdin -blocking 1
                    if {$ch eq ""} break
                    append seq $ch
                    if {[regexp {[A-Za-z~]} $ch]} break
                }
            }
        }
        # bracketed paste: \x1b[200~ ... pasted text ... \x1b[201~
        if {[string range $seq 0 4] eq "\[200~"} {
            set pasted [string range $seq 5 end]
            while 1 {
                set ch [read stdin 1]
                if {$ch eq ""} break
                append pasted $ch
                if {[string match "*\x1b\[201~" $pasted]} {
                    set pasted [string range $pasted 0 end-6]
                    break
                }
            }
            return "PASTE:$pasted"
        }
        switch -exact -- "\x1b$seq" {
            "\x1b\[A"     { return UP    }  "\x1b\[B"     { return DOWN  }
            "\x1b\[C"     { return RIGHT }  "\x1b\[D"     { return LEFT  }
            "\x1b\[H"     { return HOME  }  "\x1b\[F"     { return END   }
            "\x1b\[1~"    { return HOME  }  "\x1b\[4~"    { return END   }
            "\x1b\[3~"    { return DC    }  "\x1b\[5~"    { return PPAGE }
            "\x1b\[6~"    { return NPAGE }
            "\x1b\[11~"   { return F1    }  "\x1b\[12~"   { return F2    }
            "\x1b\[13~"   { return F3    }  "\x1b\[14~"   { return F4    }
            "\x1b\[15~"   { return F5    }  "\x1b\[17~"   { return F6    }
            "\x1b\[18~"   { return F7    }  "\x1b\[19~"   { return F8    }
            "\x1b\[20~"   { return F9    }  "\x1b\[21~"   { return F10   }
            "\x1b\[23~"   { return F11   }  "\x1b\[24~"   { return F12   }
            "\x1bOA"      { return UP    }  "\x1bOB"      { return DOWN  }
            "\x1bOC"      { return RIGHT }  "\x1bOD"      { return LEFT  }
            "\x1bOH"      { return HOME  }  "\x1bOF"      { return END   }
            "\x1bOP"      { return F1    }  "\x1bOQ"      { return F2    }
            "\x1bOR"      { return F3    }  "\x1bOS"      { return F4    }
            "\x1b\[\[A"   { return F1    }  "\x1b\[\[B"   { return F2    }
            "\x1b\[\[C"   { return F3    }  "\x1b\[\[D"   { return F4    }
            "\x1b\[\[E"   { return F5    }
            "\x1b\[1;2A"  { return SHIFT-UP    }
            "\x1b\[1;2B"  { return SHIFT-DOWN  }
            "\x1b\[1;2C"  { return SHIFT-RIGHT }
            "\x1b\[1;2D"  { return SHIFT-LEFT  }
            "\x1b\[a"     { return SHIFT-UP    }
            "\x1b\[b"     { return SHIFT-DOWN  }
            "\x1b\[c"     { return SHIFT-RIGHT }
            "\x1b\[d"     { return SHIFT-LEFT  }
            "\x1b\[1;5A"  { return CTRL-UP    }
            "\x1b\[1;5B"  { return CTRL-DOWN  }
            "\x1b\[1;5C"  { return CTRL-RIGHT }
            "\x1b\[1;5D"  { return CTRL-LEFT  }
            "\x1b\[5A"    { return CTRL-UP    }
            "\x1b\[5B"    { return CTRL-DOWN  }
            "\x1b\[5C"    { return CTRL-RIGHT }
            "\x1b\[5D"    { return CTRL-LEFT  }
            "\x1b\[1;3A"  { return CTRL-UP    }
            "\x1b\[1;3B"  { return CTRL-DOWN  }
            "\x1b\[1;3C"  { return CTRL-RIGHT }
            "\x1b\[1;3D"  { return CTRL-LEFT  }
            "\x1bb"       { return CTRL-LEFT  }
            "\x1bf"       { return CTRL-RIGHT }
            "\x1bt"       { return ALT-t }
            "\x1bT"       { return ALT-T }
        }
        return ESC
    }
    # UTF-8 multi-byte
    if {$b >= 0xC0 && $b < 0xE0} {
        return [encoding convertfrom utf-8 "${raw}[read stdin 1]"]
    } elseif {$b >= 0xE0 && $b < 0xF0} {
        return [encoding convertfrom utf-8 "${raw}[read stdin 2]"]
    } elseif {$b >= 0xF0} {
        return [encoding convertfrom utf-8 "${raw}[read stdin 3]"]
    }
    if {$b == 127} { return BACKSPACE }
    if {$b == 13  || $b == 10} { return ENTER }
    if {$b == 9}               { return TAB }
    return [format %c $b]
}

# -- Word wrap -----------------------------------------------------------------

proc tui-wrap-line {line width} {
    set len [string length $line]
    if {$width <= 0} { return [list [list 0 $len]] }
    if {$len == 0}   { return [list [list 0 0]] }
    set segs {}; set pos 0
    while {$pos < $len} {
        if {$len - $pos <= $width} { lappend segs [list $pos $len]; break }
        set ce [expr {$pos + $width}]
        set sub [string range $line $pos [expr {$ce-1}]]
        set lsp -1
        for {set i [expr {[string length $sub]-1}]} {$i >= 0} {incr i -1} {
            if {[string index $sub $i] eq " "} { set lsp $i; break }
        }
        if {$lsp > 0} {
            set ba [expr {$pos+$lsp}]; lappend segs [list $pos $ba]; set pos [expr {$ba+1}]
        } else { lappend segs [list $pos $ce]; set pos $ce }
    }
    return $segs
}

proc tui-build-layout {lines width cacheVar} {
    upvar 1 $cacheVar cache
    set vrows {}; set ish {}; set isd {}
    set new_cache [lrepeat [llength $lines] ""]
    set li 0
    foreach line $lines {
        set entry [lindex $cache $li]
        if {$entry ne "" && [lindex $entry 4] == $width && [lindex $entry 0] eq $line} {
            set segs  [lindex $entry 1]
            set is_h  [lindex $entry 2]
            set is_d  [lindex $entry 3]
            set spans [lindex $entry 5]          ;# may be empty on first pass
            lset new_cache $li [list $line $segs $is_h $is_d $width $spans]
        } else {
            set segs [tui-wrap-line $line $width]
            set is_h [expr {[parse-heading $line] ne ""}]
            set is_d [parse-comment $line]
            lset new_cache $li [list $line $segs $is_h $is_d $width {}]  ;# spans lazy
        }
        set lnum [expr {$li + 1}]
        foreach seg $segs {
            lappend vrows [list $lnum [lindex $seg 0] [lindex $seg 1]]
        }
        lappend ish $is_h
        lappend isd $is_d
        incr li
    }
    set cache $new_cache
    return [list $vrows $ish $isd]
}

proc tui-patch-vrows {dl} {
    upvar 1 lines lines vrows vrows ish_cache ish_cache isd_cache isd_cache \
            layout_cache layout_cache tw tw dirty_line dirty_line
    set idx [expr {$dl - 1}]
    set line [lindex $lines $idx]
    set old_entry [lindex $layout_cache $idx]
    if {$old_entry eq "" || [lindex $old_entry 4] != $tw} { return 0 }
    if {[lindex $old_entry 0] eq $line} { set dirty_line -1; return 1 }
    set old_nrows [llength [lindex $old_entry 1]]
    set new_segs  [tui-wrap-line $line $tw]
    set is_h      [expr {[parse-heading $line] ne ""}]
    set is_d      [parse-comment $line]
    set spans     [tui-parse-inline-spans $line]
    # binary search for first vrow belonging to line dl
    set n [llength $vrows]; set lo 0; set hi [expr {$n-1}]; set vs -1
    while {$lo <= $hi} {
        set mid [expr {($lo+$hi)/2}]
        if {[lindex [lindex $vrows $mid] 0] < $dl} { set lo [expr {$mid+1}] } \
        else { set vs $mid; set hi [expr {$mid-1}] }
    }
    if {$vs < 0} { return 0 }
    set new_entries {}
    foreach seg $new_segs { lappend new_entries [list $dl [lindex $seg 0] [lindex $seg 1]] }
    set vrows [lreplace $vrows $vs [expr {$vs+$old_nrows-1}] {*}$new_entries]
    lset layout_cache $idx [list $line $new_segs $is_h $is_d $tw $spans]
    lset ish_cache $idx $is_h
    lset isd_cache $idx $is_d
    set dirty_line -1
    return 1
}

proc tui-l2v {vrows cy cx} {
    set n [llength $vrows]
    if {$n == 0} { return {0 0} }
    # binary search: find first vrow with li >= cy
    set lo 0; set hi [expr {$n - 1}]
    while {$lo < $hi} {
        set mid [expr {($lo + $hi) / 2}]
        if {[lindex [lindex $vrows $mid] 0] < $cy} { set lo [expr {$mid + 1}] } \
        else { set hi $mid }
    }
    for {set vi $lo} {$vi < $n} {incr vi} {
        lassign [lindex $vrows $vi] li scol ecol
        if {$li > $cy} break
        if {$li == $cy && $scol <= $cx && $cx <= $ecol} {
            set nx [expr {$vi+1}]
            if {$cx == $ecol && $ecol > $scol && $nx < $n \
                    && [lindex [lindex $vrows $nx] 0] == $li \
                    && [lindex [lindex $vrows $nx] 1] <= $cx} continue
            return [list $vi [expr {$cx - $scol}]]
        }
    }
    lassign [lindex $vrows [expr {$n-1}]] li scol ecol
    return [list [expr {$n-1}] [expr {max(0, min($cx-$scol, $ecol-$scol))}]]
}

proc tui-v2l {vrows vi scx} {
    set n [llength $vrows]
    if {$n == 0} { return {1 0} }
    set vi [expr {max(0, min($vi, $n-1))}]
    lassign [lindex $vrows $vi] li scol ecol
    return [list $li [expr {$scol + max(0, min($scx, $ecol-$scol))}]]
}

# -- TUI helpers ---------------------------------------------------------------

proc tui-prompt {label rows cols} {
    set buf ""
    set ::tui_escaped 0
    # On DOS cooked mode, the triggering key (e.g. 'n') was sent with a
    # trailing CR+LF that still sits in stdin.  Skip all leading ENTERs until
    # the first real keystroke so the prompt doesn't close immediately.
    # ESC still cancels at any point.
    set skip_leading_enters 0
    while 1 {
        set d " $label$buf"
        tui-bar [expr {$rows-1}] $d "" $cols
        puts -nonewline "\033\[?25h"; tui-move [expr {$rows-1}] [string length $d]; flush stdout
        set k [tui-getch]; puts -nonewline "\033\[?25l"
        if {$skip_leading_enters} {
            if {$k eq "ENTER"} { continue }
            set skip_leading_enters 0
        }
        switch -- $k {
            ESC       { set ::tui_escaped 1; return "" }
            ENTER     { return $buf }
            BACKSPACE { set buf [string range $buf 0 end-1] }
            default   { if {[string length $k] == 1 || [string length $k] > 1} { append buf $k } }
        }
    }
}

proc tui-confirm {msg rows cols} {
    if {$::cfg_console_center_alert} {
        set line "  $msg (y/n)  "
        set w [string length $line]
        set row [expr {$rows / 2}]
        set lcol [expr {max(0, ($cols - $w) / 2)}]
        foreach r [list [expr {$row-1}] $row [expr {$row+1}]] {
            tui-move $r 0; puts -nonewline "\033\[2K"
        }
        tui-move $row $lcol
        tui-attr reverse; puts -nonewline $line; tui-attr off
    } else {
        tui-bar [expr {$rows-1}] " $msg (y/n)" "" $cols
    }
    flush stdout
    while 1 {
        set k [tui-getch]
        if {$k in {y Y}} { return 1 }
        if {$k in {n N ESC}} { return 0 }
    }
}

proc tui-yesnocancel {msg rows cols} {
    if {$::cfg_console_center_alert} {
        set line "  $msg  "
        set w [string length $line]
        set row [expr {$rows / 2}]
        set lcol [expr {max(0, ($cols - $w) / 2)}]
        foreach r [list [expr {$row-1}] $row [expr {$row+1}]] {
            tui-move $r 0; puts -nonewline "\033\[2K"
        }
        tui-move $row $lcol
        tui-attr reverse; puts -nonewline $line; tui-attr off
    } else {
        tui-bar [expr {$rows-1}] " $msg" "" $cols
    }
    flush stdout
    while 1 {
        set k [tui-getch]
        if {$k in {y Y o O}} { return yes }
        if {$k in {n N}}     { return no }
        if {$k in {c C ESC}} { return cancel }
    }
}

proc tui-active-dir {entries cfi} {
    set i [expr {$cfi >= 0 ? $cfi : 0}]
    while {$i >= 0} {
        lassign [lindex $entries $i] type dir
        if {$type eq "header"} { return [expr {$dir ne "" ? $dir : $::DOCS_DIR_DEFAULT}] }
        incr i -1
    }
    return $::DOCS_DIR_DEFAULT
}

# -- Clipboard ----------------------------------------------------------------

set ::tui_clipboard ""

proc tui-copy {text} {
    set ::tui_clipboard $text
    foreach cmd {
        {xclip -selection clipboard}
        {xsel --clipboard --input}
        {wl-copy}
    } {
        if {![catch { set fh [open "| $cmd" w]; puts -nonewline $fh $text; close $fh }]} return
    }
}

proc tui-paste {} {
    foreach cmd {
        {xclip -selection clipboard -o}
        {xsel --clipboard --output}
        {wl-paste --no-newline}
    } {
        if {![catch {set r [exec {*}$cmd]}]} { return $r }
    }
    return $::tui_clipboard
}

# -- Selection helpers ---------------------------------------------------------

proc tui-sel-range {anchor cy cx} {
    if {$anchor eq ""} { return {} }
    lassign $anchor aly alx
    if {$aly < $cy || ($aly == $cy && $alx <= $cx)} {
        return [list $aly $alx $cy $cx]
    }
    return [list $cy $cx $aly $alx]
}

proc tui-sel-text {lines anchor cy cx} {
    set r [tui-sel-range $anchor $cy $cx]
    if {$r eq {}} { return "" }
    lassign $r sly scx ely ecx
    set out {}
    for {set li $sly} {$li <= $ely} {incr li} {
        set l [lindex $lines [expr {$li-1}]]
        if {$li == $sly && $li == $ely} {
            lappend out [string range $l $scx [expr {$ecx-1}]]
        } elseif {$li == $sly} {
            lappend out [string range $l $scx end]
        } elseif {$li == $ely} {
            lappend out [string range $l 0 [expr {$ecx-1}]]
        } else {
            lappend out $l
        }
    }
    return [join $out "\n"]
}

proc tui-sel-delete {lines anchor cy cx} {
    set r [tui-sel-range $anchor $cy $cx]
    if {$r eq {}} { return [list $lines $cy $cx] }
    lassign $r sly scx ely ecx
    set pre  [string range [lindex $lines [expr {$sly-1}]] 0 [expr {$scx-1}]]
    set post [string range [lindex $lines [expr {$ely-1}]] $ecx end]
    set new  [lreplace $lines [expr {$sly-1}] [expr {$ely-1}] "${pre}${post}"]
    return [list $new $sly $scx]
}

# -- TUI Browser ---------------------------------------------------------------

proc tui-push-undo {} {
    upvar 1 undo_stack undo_stack redo_stack redo_stack lines lines cy cy cx cx
    lappend undo_stack [list $lines $cy $cx]
    if {[llength $undo_stack] > 100} { set undo_stack [lrange $undo_stack end-99 end] }
    set redo_stack {}
}

proc tui-mark-dirty {} {
    upvar 1 dirty dirty wc_dirty wc_dirty wrap_dirty wrap_dirty dirty_line dirty_line
    set dirty 1; set wc_dirty 1; set wrap_dirty 1; set dirty_line -1
}

proc tui-mark-line-dirty {} {
    upvar 1 dirty dirty wc_dirty wc_dirty wrap_dirty wrap_dirty dirty_line dirty_line \
            cy cy wc_cached wc_cached cc_cached cc_cached layout_cache layout_cache lines lines
    set dirty 1
    if {!$wrap_dirty} { set dirty_line $cy }
    if {!$wc_dirty} {
        set idx [expr {$cy - 1}]
        set old_entry [lindex $layout_cache $idx]
        if {$old_entry ne ""} {
            set old_line [lindex $old_entry 0]
            set new_line [lindex $lines $idx]
            incr wc_cached [expr {[llength [regexp -all -inline {\S+} $new_line]] \
                                 - [llength [regexp -all -inline {\S+} $old_line]]}]
            incr cc_cached [expr {[string length $new_line] - [string length $old_line]}]
        } else { set wc_dirty 1 }
    }
}

proc tui-compute-wc {} {
    upvar 1 lines lines wc_cached wc_cached cc_cached cc_cached wc_dirty wc_dirty
    set wc_cached 0; set cc_cached 0
    foreach l $lines {
        incr wc_cached [llength [regexp -all -inline {\S+} $l]]
        incr cc_cached [string length $l]
    }
    set wc_dirty 0
}

proc tui-browser {} {
    set sel 0; set scroll 0; set msg ""
    set cwd ""
    set fmode 0    ;# incremental filter typing mode ("/" key)
    set prev_rows -1; set prev_cols -1
    while 1 {
        set ::tui_size_n 14
        lassign [tui-size] rows cols
        if {$rows != $prev_rows || $cols != $prev_cols} {
            set prev_rows $rows; set prev_cols $cols
        }
        # build entries
        set _subnav [expr {[info procs list-subdirs] ne "" && $::cfg_browser_subdirs}]
        set entries {}; set fcount 0
        set shown {}
        if {$_subnav && $cwd ne ""} {
            lappend entries [list header $cwd ""]
            lappend entries [list updir [file dirname $cwd] ".."]
            foreach d [list-subdirs $cwd] { lappend entries [list dir $cwd $d] }
            foreach f [list-docs $cwd] {
                if {![br-filter-match $f]} continue
                lappend entries [list file $cwd $f]
                incr fcount
            }
        } else {
            foreach dir [br-dirs] {
                foreach f [list-docs $dir] { lappend shown [file join $dir $f] }
            }
            foreach e [build-extra-entries $shown] {
                if {[lindex $e 0] in {favorite recent} && ![br-filter-match [lindex $e 2]]} continue
                lappend entries $e
            }
            foreach dir [br-dirs] {
                lappend entries [list header $dir ""]
                if {$_subnav} {
                    foreach d [list-subdirs $dir] { lappend entries [list dir $dir $d] }
                }
                foreach f [list-docs $dir] {
                    if {![br-filter-match $f]} continue
                    lappend entries [list file $dir $f]
                    incr fcount
                }
            }
        }
        set fidx {}
        for {set i 0} {$i < [llength $entries]} {incr i} {
            if {[lindex [lindex $entries $i] 0] in {file recent favorite dir updir}} { lappend fidx $i }
        }
        set nf [llength $fidx]
        if {$nf > 0} { set sel [expr {max(0, min($sel, $nf-1))}] }

        tui-attr bold; tui-fill 0 " Writhdeck" $cols; tui-attr off
        set usable [expr {$rows - 3}]

        if {$nf == 0} {
            set m [t br_no_docs]
            tui-move [expr {$rows/2}] [expr {max(0, ($cols-[string length $m])/2)}]
            puts -nonewline $m
        } else {
            set sel_ei [lindex $fidx $sel]
            if {$sel_ei < $scroll}             { set scroll $sel_ei }
            if {$sel_ei >= $scroll + $usable}  { set scroll [expr {$sel_ei - $usable + 1}] }
            if {$scroll < 0} { set scroll 0 }
            set row 1; set ei 0
            foreach entry $entries {
                if {$ei < $scroll} { incr ei; continue }
                if {$row >= $rows-2} break
                lassign $entry type dir name
                if {$type eq "header"} {
                    set lbl [expr {$name ne "" ? $name : [string map [list $::HOME_DIR ~] $dir]}]
                    tui-attr dim; tui-fill $row " $lbl" $cols; tui-attr off
                } elseif {$type in {dir updir}} {
                    set fi [lsearch $fidx $ei]; set issel [expr {$fi == $sel}]
                    set disp [expr {$type eq "updir" ? ".." : "$name/"}]
                    set pfx  [expr {$issel ? " \u00bb " : "   "}]
                    if {$issel} { tui-attr reverse }
                    tui-fill $row [string range "${pfx}${disp}" 0 [expr {$cols-1}]] $cols
                    if {$issel} { tui-attr off }
                } else {
                    set fi [lsearch $fidx $ei]; set issel [expr {$fi == $sel}]
                    set fp [file join $dir $name]
                    set sz [file size $fp]
                    set ss [expr {$sz < 1024 ? "${sz}B" : "[expr {$sz/1024}]K"}]
                    set mt [clock format [file mtime $fp] -format "%b %d %H:%M"]
                    set meta [format "%6s  %s" $ss $mt]
                    set maxn [expr {$cols - 3 - [string length $meta] - 1}]
                    set dn   [string range $name 0 [expr {max(0,$maxn-1)}]]
                    set gap  [string repeat " " [expr {max(0,$cols-3-[string length $dn]-[string length $meta])}]]
                    set pfx  [expr {$issel ? " \u00bb " : "   "}]
                    if {$issel} { tui-attr reverse }
                    tui-fill $row [string range "${pfx}${dn}${gap}${meta}" 0 [expr {$cols-1}]] $cols
                    if {$issel} { tui-attr off }
                }
                incr row; incr ei
            }
            while {$row < $rows-2} { tui-move $row 0; puts -nonewline "\033\[K"; incr row }
        }
        set plu [expr {$fcount != 1 ? "s" : ""}]
        if {$::cfg_help_bar ne ""} { tui-help [expr {$rows-2}] [format [t br_help_tui] [t br_key_help] $::cfg_lbl_toc] $cols }
        set clk [expr {[status-zone-of clock] ne "" ? "  [clock format [clock seconds] -format {%H:%M}]" : ""}]
        set _barpath [expr {$_subnav && $cwd ne "" ? $cwd : $::DOCS_DIR_DEFAULT}]
        if {$fmode || $::br_type_filter ne ""} {
            set _fl " /$::br_type_filter"
            if {$fmode} { append _fl "_" }
            tui-bar [expr {$rows-1}] $_fl " [t br_files $fcount $plu]${clk} " $cols
            set msg ""
        } elseif {$msg ne ""} { tui-bar [expr {$rows-1}] " $msg" "${clk} " $cols; set msg ""
        } else { tui-bar [expr {$rows-1}] " [string map [list $::HOME_DIR ~] $_barpath]" \
                         " [t br_files $fcount $plu]${clk} " $cols }
        flush stdout

        set key [tui-getch]
        # incremental filter typing mode: printable keys edit ::br_type_filter,
        # ENTER keeps the filter and returns to normal keys, ESC or a second
        # "/" clears it ("/" is never needed as a filter character);
        # UP/DOWN/HOME/END fall through so the selection can move while typing
        if {$fmode} {
            if {$key eq "ESC" || $key eq "/"} { set ::br_type_filter ""; set fmode 0; set sel 0; continue }
            if {$key eq "ENTER"} { set fmode 0; continue }
            if {$key eq "BACKSPACE"} {
                if {$::br_type_filter eq ""} { set fmode 0 } else {
                    set ::br_type_filter [string range $::br_type_filter 0 end-1]
                }
                set sel 0; continue
            }
            if {[string length $key] == 1 && $key >= " "} {
                append ::br_type_filter $key
                set sel 0; continue
            }
        } elseif {$key eq "/"} {
            if {$::br_type_filter ne ""} {
                set ::br_type_filter ""; set sel 0
            } else {
                set fmode 1
            }
            continue
        } elseif {$key eq "ESC" && $::br_type_filter ne ""} {
            set ::br_type_filter ""; set sel 0; continue
        }
        set cfi [expr {$nf > 0 ? [lindex $fidx $sel] : -1}]
        set ctype [expr {$cfi >= 0 ? [lindex [lindex $entries $cfi] 0] : ""}]
        switch -- $key {
            q - "\x11" {
                lassign [tui-size] rows cols
                if {[tui-ws-check-inactive-dirty $rows $cols]} { return "" }
            }
            UP - k  { if {$sel > 0} { incr sel -1 } }
            DOWN - j { if {$sel < $nf-1} { incr sel 1 } }
            HOME    { set sel 0 }
            END     { set sel [expr {max(0,$nf-1)}] }
            BACKSPACE - LEFT {
                if {$_subnav && $cwd ne ""} {
                    set _p [file dirname $cwd]
                    set cwd [expr {[br-is-root $_p] ? "" : $_p}]
                    set sel 0; set scroll 0
                }
            }
            ENTER {
                if {$cfi >= 0} {
                    lassign [lindex $entries $cfi] _t dir name
                    if {$_t eq "dir"} {
                        set cwd [file normalize [file join $dir $name]]; set sel 0; set scroll 0
                    } elseif {$_t eq "updir"} {
                        set _p [file dirname $cwd]
                        set cwd [expr {[br-is-root $_p] ? "" : $_p}]; set sel 0; set scroll 0
                    } else {
                        return [file join $dir $name]
                    }
                }
            }
            n {
                set dir [tui-active-dir $entries $cfi]
                set name [string trim [tui-prompt "new file: " $rows $cols]]
                if {$name ne ""} {
                    if {[file extension $name] eq ""} { append name $::FILE_EXT }
                    set fp [file join $dir $name]
                    if {[file exists $fp]} { set msg [t br_exists $name]
                    } else { close [open $fp w]; return $fp }
                }
            }
            t { return "__scratchpad__" }
            h {
                tui-help-dialog $rows $cols 0 0
            }
            i {
                if {$cfi >= 0 && $ctype in {file recent favorite}} {
                    lassign [lindex $entries $cfi] _ dir name
                    tui-info-dialog [file join $dir $name] $rows $cols
                }
            }
            f {
                if {$cfi >= 0 && $ctype in {file recent favorite}} {
                    lassign [lindex $entries $cfi] _ dir name
                    set _path [file join $dir $name]
                    set _was_fav [expr {$_path in $::favorites_list}]
                    toggle-favorite $_path
                    set msg [t [expr {$_was_fav ? "br_fav_removed" : "br_fav_added"}] $name]
                }
            }
            s {
                if {$cfi >= 0 && $ctype in {file recent favorite}} {
                    lassign [lindex $entries $cfi] _ dir name
                    set _path [file join $dir $name]
                    set _r [tui-stats-dialog $_path $rows $cols]
                    if {$_r ne ""} { set msg $_r }
                }
            }
            b {
                if {$cfi >= 0 && $ctype in {file recent favorite}} {
                    lassign [lindex $entries $cfi] _ dir name
                    set dst [do-backup $dir $name]
                    set msg [t br_backed_up $name [string map [list $::HOME_DIR ~] [file dirname $dst]] [file tail $dst]]
                }
            }
            d {
                if {$cfi >= 0 && $ctype in {file recent favorite}} {
                    lassign [lindex $entries $cfi] _ dir name
                    if {[tui-confirm [t br_delete $name] $rows $cols]} {
                        set full [file join $dir $name]
                        file delete $full
                        recent-remove $full
                        set msg [t br_deleted $name]; if {$sel > 0} { incr sel -1 }
                    }
                }
            }
            r {
                if {$cfi >= 0 && $ctype in {file recent favorite}} {
                    lassign [lindex $entries $cfi] _ dir name
                    set new [string trim [tui-prompt "rename '$name' to: " $rows $cols]]
                    if {$new ne ""} {
                        if {[file extension $new] eq ""} { append new $::FILE_EXT }
                        set np [file join $dir $new]
                        if {[file exists $np]} { set msg [t br_exists $new]
                        } else {
                            set old_path [file join $dir $name]
                            file rename $old_path $np
                            recent-rename $old_path $np
                            set msg [t br_renamed $new]
                        }
                    }
                }
            }
            w {
                if {$cfi >= 0 && [info procs tui-word-occurrences] ne ""} {
                    lassign [lindex $entries $cfi] _ dir name
                    set _path [file join $dir $name]
                    if {[file isfile $_path]} {
                        tui-word-occurrences $_path $rows $cols
                    }
                }
            }
            a {
                if {$cfi >= 0 && [info procs tui-analyse-dialog] ne ""} {
                    lassign [lindex $entries $cfi] _ dir name
                    set _path [file join $dir $name]
                    if {[file isfile $_path]} {
                        tui-analyse-dialog $_path $rows $cols
                        if {$::tui_rep_jump ne ""} {
                            cursor-put $_path $::tui_rep_jump 0
                            return $_path
                        }
                    }
                }
            }
            c {
                tui-config-dialog $rows $cols
            }
        }
        if {$key eq $::cfg_tui_help && $key ne "h"} {
            tui-help-dialog $rows $cols 0 0
        }
        if {$key eq $::cfg_tui_toc} {
            set _secs {}
            for {set _i 0} {$_i < [llength $entries]} {incr _i} {
                lassign [lindex $entries $_i] _t _d _n
                if {$_t eq "header"} {
                    set _lbl [expr {$_n ne "" ? $_n : [string map [list $::HOME_DIR ~] $_d]}]
                    lappend _secs [list $_i $_lbl]
                }
            }
            if {[llength $_secs] > 0} {
                set _ns [llength $_secs]; set _sel 0; set _scroll 0
                set _usable [expr {$rows-3}]
                while 1 {
                    if {$_sel < $_scroll}             { set _scroll $_sel }
                    if {$_sel >= $_scroll + $_usable} { set _scroll [expr {$_sel - $_usable + 1}] }
                    tui-attr bold; tui-fill 0 " [t br_toc_title]" $cols; tui-attr off
                    for {set _i 0} {$_i < $_usable} {incr _i} {
                        set _idx [expr {$_scroll+$_i}]
                        if {$_idx >= $_ns} {
                            tui-move [expr {$_i+1}] 0; puts -nonewline "\033\[K"
                            continue
                        }
                        set _line [format "  %s" [lindex [lindex $_secs $_idx] 1]]
                        if {$_idx == $_sel} { tui-attr reverse }
                        tui-fill [expr {$_i+1}] [string range $_line 0 [expr {$cols-1}]] $cols
                        if {$_idx == $_sel} { tui-attr off }
                    }
                    tui-help [expr {$rows-2}] [t br_toc_bar] $cols
                    tui-bar  [expr {$rows-1}] "" "" $cols
                    flush stdout
                    set _key [tui-getch]
                    switch -- $_key {
                        ESC - "\x11" - q { break }
                        UP - k   { if {$_sel > 0}      { incr _sel -1 } }
                        DOWN - j { if {$_sel < $_ns-1} { incr _sel  1 } }
                        HOME     { set _sel 0 }
                        END      { set _sel [expr {$_ns-1}] }
                        ENTER {
                            set _hi [lindex [lindex $_secs $_sel] 0]
                            for {set _j 0} {$_j < [llength $fidx]} {incr _j} {
                                if {[lindex $fidx $_j] > $_hi} { set sel $_j; break }
                            }
                            break
                        }
                    }
                }
                puts -nonewline "\033\[2J"
            }
        }
        if {$key eq $::cfg_tui_open} {
            set _dir [expr {$cfi >= 0 ? [lindex [lindex $entries $cfi] 1] : $::DOCS_DIR_DEFAULT}]
            set _lbl [string map [list $::HOME_DIR ~] $_dir]
            set _in  [string trim [tui-prompt "open \[${_lbl}/\]: " $rows $cols]]
            if {$_in ne "" && !$::tui_escaped} {
                set _fp [expr {[file pathtype $_in] eq "absolute" ? $_in : [file join $_dir $_in]}]
                if {[file isfile $_fp]} { return $_fp } else { set msg "not found: $_in" }
            }
        }
    }
}

# -- TUI TOC -------------------------------------------------------------------

proc tui-toc {lines rows cols {cy 1} {filepath ""}} {
    set headings {}; set ln 1
    foreach line $lines {
        set hl [heading-level $line]
        if {$hl ne ""} {
            lassign $hl t level
            lappend headings [list $ln $t $level]
        }
        incr ln
    }
    if {![llength $headings]} { return {} }
    set sel 0
    if {$filepath ne "" && [dict exists $::session_headings $filepath]} {
        set sel [dict get $::session_headings $filepath]
        if {$sel >= [llength $headings]} { set sel 0 }
    } else {
        set idx 0
        foreach h $headings {
            if {[lindex $h 0] <= $cy} { set sel $idx }
            incr idx
        }
    }
    set scroll 0
    while 1 {
        set usable [expr {$rows-3}]
        if {$sel < $scroll}            { set scroll $sel }
        if {$sel >= $scroll + $usable} { set scroll [expr {$sel - $usable + 1}] }
        tui-attr bold; tui-fill 0 " [t toc_title]" $cols; tui-attr off
        for {set i 0} {$i < $usable} {incr i} {
            set idx [expr {$scroll+$i}]
            if {$idx >= [llength $headings]} {
                tui-move [expr {$i+1}] 0; puts -nonewline "\033\[K"
                continue
            }
            lassign [lindex $headings $idx] ln title level
            set indent [string repeat "- " [expr {$level - 1}]]
            set line [format "  %4d   %s%s" $ln $indent $title]
            if {$idx == $sel} { tui-attr reverse }
            tui-fill [expr {$i+1}] [string range $line 0 [expr {$cols-1}]] $cols
            if {$idx == $sel} { tui-attr off }
        }
        set nh [llength $headings]; set plu [expr {$nh != 1 ? "s" : ""}]
        tui-help [expr {$rows-2}] [t toc_jump_bar] $cols
        tui-bar  [expr {$rows-1}] " [t toc_headings $nh $plu]" "" $cols
        flush stdout
        switch -- [tui-getch] {
            ESC - "\x11" { return {} }
            UP - k   { if {$sel > 0} { incr sel -1 } }
            DOWN - j { if {$sel < $nh-1} { incr sel 1 } }
            HOME     { set sel 0 }
            END      { set sel [expr {$nh-1}] }
            ENTER    { if {$filepath ne ""} { dict set ::session_headings $filepath $sel }
                       return [lindex $headings $sel] }
        }
    }
}

proc tui-save-file {filepath lines} {
    set fh [open $filepath w]; chan configure $fh -encoding utf-8
    puts -nonewline $fh "[join $lines \n]\n"; close $fh
}

# -- TUI Editor ----------------------------------------------------------------

proc tui-cmd-menu {} {
    set m {{t timer} {p pause} {b browser} {q quit} {s stats}}
    if {[info procs tui-analyse-dialog] ne ""} { lappend m {w words} {a analyse} }
    if {[info procs tui-synonyms-dialog] ne ""} { lappend m {y synonyms} }
    return $m
}

proc tui-cmd-message {idx} {
    set parts {}
    set i 0
    foreach item [tui-cmd-menu] {
        lassign $item k label
        set txt "$k:$label"
        if {$i == $idx} { set txt "\[$txt\]" }
        lappend parts $txt
        incr i
    }
    return "$::cfg_lbl_cmd_mode: exit mode  [join $parts {  }]"
}

proc tui-scratchpad-save {rows cols linesVar filepathVar dirtyVar} {
    upvar 1 $linesVar lines $filepathVar filepath $dirtyVar dirty
    lassign [tui-size] rows cols
    set name [string trim [tui-prompt "save as: " $rows $cols]]
    if {$name eq ""} return
    if {[file extension $name] eq ""} { append name $::FILE_EXT }
    set fp [file join $::DOCS_DIR_DEFAULT $name]
    if {[file exists $fp]} {
        if {![tui-confirm "\"$name\" exists. Overwrite?" $rows $cols]} return
    }
    set filepath $fp
    tui-save-file $filepath $lines
    set dirty 0
}

proc tui-editor {filepath {init_state {}}} {
    # -- load ------------------------------------------------------------------
    set lines {}
    if {[dict size $init_state] > 0} {
        set lines [dict get $init_state lines]
        set cy    [dict get $init_state cy]
        set cx    [dict get $init_state cx]
        set dirty [dict get $init_state dirty]
    } else {
        if {$filepath ne "" && [file exists $filepath] && [file size $filepath] > 0} {
            set fh [open $filepath r]; chan configure $fh -encoding utf-8
            set content [read $fh]; close $fh
            foreach line [split $content "\n"] { lappend lines $line }
            if {[llength $lines] > 1 && [lindex $lines end] eq ""} {
                set lines [lrange $lines 0 end-1]
            }
        }
        if {[llength $lines] == 0} { set lines [list ""] }
        if {$filepath ne ""} {
            recent-push $filepath
            set _wc [llength [regexp -all -inline {\S+} [join $lines "\n"]]]
            daily-open $filepath $_wc
        } else {
            scratchpad-stats-open [llength [regexp -all -inline {\S+} [join $lines "\n"]]]
        }
        set dirty 0
    }
    set readonly [expr {$filepath ne "" && [file exists $filepath] && ![file writable $filepath]}]

    # -- cursor restore --------------------------------------------------------
    if {[dict size $init_state] == 0} {
    if {$filepath eq ""} { set cy 1; set cx 0 } else { lassign [cursor-get $filepath] cy cx }
    if {[dict exists $::session_headings $filepath]} {
        set hidx [dict get $::session_headings $filepath]
        set hi 0; set ln 1
        foreach tline $lines {
            if {[parse-heading $tline] ne ""} {
                if {$hi == $hidx} { set cy $ln; set cx 0; break }
                incr hi
            }
            incr ln
        }
    }
    }
    set cy [expr {max(1, min($cy, [llength $lines]))}]
    set cx [expr {max(0, min($cx, [string length [lindex $lines [expr {$cy-1}]]]))}]

    set scroll_y 0
    set toc_jumped 0
    if {[dict size $init_state] == 0} { set dirty 0 }
    set message ""; set msg_time 0; set sticky -1
    set undo_stack {}
    set redo_stack {}
    set file_mtime_known [expr {$filepath ne "" && [file exists $filepath] \
        ? [file mtime $filepath] : 0}]
    set sel_anchor ""
    set sel_sticky  0
    if {![info exists ::tui_search]}  { set ::tui_search  "" }
    if {![info exists ::tui_replace]} { set ::tui_replace "" }

    # push-undo: call before any destructive edit
    set wc_dirty 1; set wrap_dirty 1; set wc_cached 0; set cc_cached 0
    set vrows {}; set prev_tw -1
    set ish_cache {}; set isd_cache {}
    set layout_cache {}
    set prev_rows -1; set prev_cols -1
    set dirty_line -1
    set ::autosave_last_time [clock seconds]
    set split 0; set split_ws2_mode 0; set split_focus 1
    set split_r_lines [list ""]; set split_r_cy 1; set split_r_cx 0
    set split_r_scroll 0; set split_r_dirty 0; set split_r_fp ""
    set split_r_vrows {}; set split_r_ish {}; set split_r_isd {}
    set split_r_layout {}; set split_r_prev_tw -1; set split_r_wrap_dirty 1
    set _skip_draw 0
    set _last_bar_l ""; set _last_bar_c ""; set _last_bar_r ""

    while 1 {
        set ::tui_size_n 14
        lassign [tui-size] rows cols
        if {$rows != $prev_rows || $cols != $prev_cols} {
            set prev_rows $rows; set prev_cols $cols
            set wrap_dirty 1
        }

        # -- autosave ----------------------------------------------------------
        if {$::cfg_autosave_enabled} {
            set _now [clock seconds]
            set _ivl [expr {$::cfg_autosave_interval < 1 ? 1 : $::cfg_autosave_interval}]
            if {$_now - $::autosave_last_time >= $_ivl * 60} {
                do-autosave $::ws_n [join $lines "\n"] $filepath
            }
        }

        # -- layout ------------------------------------------------------------
        set _hm   [expr {$::typewriter_mode && $::cfg_hemingway_mode ? 2 : 1}]
        set roff  [expr {$::cfg_console_margin_rows * $_hm}]
        set marg  [expr {$::cfg_console_margin_cols * $_hm}]
        set ln_w  [expr {$::cfg_line_numbers ? [string length [llength $lines]] + 2 : 0}]
        set coff  [expr {$marg + $ln_w}]
        set tw    [expr {max(1, $cols - $coff - $marg - 1)}]   ;# -1 for scroll indicator
        set _hm_bar [expr {$::typewriter_mode && $::cfg_hemingway_mode}]
        set th    [expr {max(1, $rows - ($::typewriter_mode && $::cfg_hemingway_mode ? 0 : 2) - 2*$roff)}]
        if {$split} {
            set half  [expr {($cols - 1) / 2}]
            set tw    [expr {max(1, $half - $coff - $marg)}]
            set rcoff [expr {$half + 1 + $marg}]
            set tw_r  [expr {max(1, $cols - $rcoff - $marg)}]
        }

        set cy [expr {max(1, min($cy, [llength $lines]))}]
        set cx [expr {max(0, min($cx, [string length [lindex $lines [expr {$cy-1}]]]))}]

        set _need_draw [expr {$wrap_dirty || $tw != $prev_tw || $dirty_line > 0}]
        if {$wrap_dirty || $tw != $prev_tw} {
            lassign [tui-build-layout $lines $tw layout_cache] vrows ish_cache isd_cache
            set prev_tw $tw; set wrap_dirty 0; set dirty_line -1
            if {$split && !$split_ws2_mode} { set split_r_wrap_dirty 1 }
        } elseif {$dirty_line > 0} {
            if {![tui-patch-vrows $dirty_line]} {
                lassign [tui-build-layout $lines $tw layout_cache] vrows ish_cache isd_cache
                set dirty_line -1
                if {$split && !$split_ws2_mode} { set split_r_wrap_dirty 1 }
            } elseif {$split && !$split_ws2_mode} {
                set split_r_wrap_dirty 1
            }
        }
        if {$split && ($split_r_wrap_dirty || $tw_r != $split_r_prev_tw)} {
            set _rsrc [expr {$split_ws2_mode ? $split_r_lines : $lines}]
            lassign [tui-build-layout $_rsrc $tw_r split_r_layout] \
                split_r_vrows split_r_ish split_r_isd
            set split_r_prev_tw $tw_r; set split_r_wrap_dirty 0
        }
        lassign [tui-l2v $vrows $cy $cx] vi scx
        if {$vi < [llength $vrows]} {
            lassign [lindex $vrows $vi] _vi_li _vi_scol _vi_ecol
            set vis_scx [string length [string map [list "\t" "    "] \
                [string range [lindex $lines [expr {$cy-1}]] $_vi_scol [expr {$cx-1}]]]]
        } else { set vis_scx $scx }
        set split_r_vi 0; set split_r_scx 0; set vis_split_r_scx 0
        if {$split} {
            lassign [tui-l2v $split_r_vrows $split_r_cy $split_r_cx] split_r_vi split_r_scx
            if {$split_r_vi < [llength $split_r_vrows]} {
                lassign [lindex $split_r_vrows $split_r_vi] _sri_li _sri_scol _sri_ecol
                set _rsrc_fc [expr {$split_ws2_mode ? $split_r_lines : $lines}]
                set vis_split_r_scx [string length [string map [list "\t" "    "] \
                    [string range [lindex $_rsrc_fc [expr {$split_r_cy-1}]] $_sri_scol [expr {$split_r_cx-1}]]]]
            } else { set vis_split_r_scx $split_r_scx }
        }

        set _cth [expr {$split ? $th - 1 : $th}]
        if {$toc_jumped} { set scroll_y $vi; set toc_jumped 0 } elseif {$::typewriter_mode} {
            set scroll_y [expr {$vi - $_cth/2}]
        } else {
            if {$vi < $scroll_y}          { set scroll_y $vi }
            if {$vi >= $scroll_y + $_cth} { set scroll_y [expr {$vi - $_cth + 1}] }
        }
        set scroll_y [expr {max(0, min($scroll_y, max(0, [llength $vrows] - $_cth)))}]
        if {$split} {
            set _rv [lindex [tui-l2v $split_r_vrows $split_r_cy $split_r_cx] 0]
            if {$_rv < $split_r_scroll}              { set split_r_scroll $_rv }
            if {$_rv >= $split_r_scroll + $_cth}     { set split_r_scroll [expr {$_rv - $_cth + 1}] }
            set split_r_scroll [expr {max(0, min($split_r_scroll, max(0, [llength $split_r_vrows] - $_cth)))}]
        }

        # -- draw (skipped on timer/autosave ticks when content unchanged) -----
        set _do_draw [expr {$_need_draw || !$_skip_draw}]; set _skip_draw 0
        if {$_do_draw} {
        puts -nonewline "\033\[?25l"
        set sel_r [tui-sel-range $sel_anchor $cy $cx]
        if {$sel_r ne {}} { lassign $sel_r _sly _scx_s _ely _ecx_s }

        # typewriter focus: paragraph boundaries (source line numbers)
        if {$::typewriter_mode} {
            set _para_s $cy; set _para_e $cy
            set _nl [llength $lines]
            while {$_para_s > 1 && [string trim [lindex $lines [expr {$_para_s-2}]]] ne ""} { incr _para_s -1 }
            while {$_para_e < $_nl && [string trim [lindex $lines $_para_e]] ne ""} { incr _para_e }
        }

        if {$split} {
            set _l_fn [expr {$filepath eq "" ? "scratchpad" : [file tail $filepath]}]
            tui-move $roff 0
            tui-attr reverse
            puts -nonewline [format "%-*s" $half " \[$::ws_n\] $_l_fn"]
            tui-attr off
        }
        for {set i [expr {$split ? 1 : 0}]} {$i < $th} {incr i} {
            set vi2 [expr {$scroll_y + $i - ($split ? 1 : 0)}]
            set srow [expr {$i + $roff}]
            tui-move $srow 0
            if {$vi2 >= [llength $vrows]} {
                puts -nonewline [string repeat { } [expr {$split ? $half : $cols}]]
                continue
            }
            lassign [lindex $vrows $vi2] li scol ecol
            set _rl [lindex $lines [expr {$li-1}]]
            set seg [string map [list "\t" "    "] [string range $_rl $scol [expr {$ecol-1}]]]
            set ish [lindex $ish_cache [expr {$li-1}]]
            set isd [lindex $isd_cache [expr {$li-1}]]
            set isl [expr {!$ish && !$isd && [parse-list $_rl]}]
            set seg_len [string length $seg]

            # left margin + line number - written inline from col 0 (no tui-move within line)
            if {$ln_w > 0 && $scol == 0} {
                tui-attr dim
                puts -nonewline "[string repeat { } $marg][format "%[expr {$ln_w-1}]d " $li]"
                tui-attr off
            } else {
                puts -nonewline [string repeat { } $coff]
            }

            # text (with selection highlight) - cursor now at col $coff
            # sf/st are expanded-column offsets within seg (tabs already expanded to 4 spaces)
            set sf -1; set st -1
            if {$sel_r ne {}} {
                # Helper: raw col c → expanded col within seg (from scol)
                set _xc_s [expr {$_scx_s <= $scol ? 0 : [string length [string map [list "\t" "    "] [string range $_rl $scol [expr {$_scx_s-1}]]]]}]
                set _xc_e [expr {$_ecx_s <= $scol ? 0 : [string length [string map [list "\t" "    "] [string range $_rl $scol [expr {$_ecx_s-1}]]]]}]
                if      {$li > $_sly && $li < $_ely}   { set sf 0;    set st $seg_len } \
                elseif  {$li == $_sly && $li == $_ely} { set sf $_xc_s; set st [expr {min($seg_len,$_xc_e)}] } \
                elseif  {$li == $_sly}                 { set sf $_xc_s; set st $seg_len } \
                elseif  {$li == $_ely}                 { set sf 0;    set st [expr {min($seg_len,$_xc_e)}] }
                if {$sf >= 0 && $sf >= $st} { set sf -1 }
            }
            set _tw_dim [expr {$::typewriter_mode && ($li < $_para_s || $li > $_para_e)}]
            if {$_tw_dim} {
                tui-attr dim
                if {$sf >= 0} {
                    puts -nonewline [string range $seg 0 [expr {$sf-1}]]
                    tui-attr sel; puts -nonewline [string range $seg $sf [expr {$st-1}]]; tui-attr off
                    tui-attr dim; puts -nonewline [string range $seg $st end]
                } else {
                    puts -nonewline $seg
                }
                tui-attr off
            } elseif {$ish || $isd || $isl} {
                set _a [expr {$ish ? "heading" : ($isd ? "dim-text" : "markup-line")}]
                if {$sf >= 0} {
                    if {$sf > 0} { tui-attr $_a; puts -nonewline [string range $seg 0 [expr {$sf-1}]]; tui-attr off }
                    tui-attr sel; puts -nonewline [string range $seg $sf [expr {$st-1}]]; tui-attr off
                    if {$st < $seg_len} { tui-attr $_a; puts -nonewline [string range $seg $st end]; tui-attr off }
                } else {
                    tui-attr $_a; puts -nonewline $seg; tui-attr off
                }
            } else {
                set _lc_entry [lindex $layout_cache [expr {$li-1}]]
                set _spans [lindex $_lc_entry 5]
                if {$_spans eq {}} {
                    set _spans [tui-parse-inline-spans $_rl]
                    lset layout_cache [expr {$li-1}] [lreplace $_lc_entry 5 5 $_spans]
                }
                tui-render-inline-seg $seg $scol $_spans $sf $st
            }
            # right padding - fill to end of line with spaces (no \033[K)
            tui-attr off
            puts -nonewline [string repeat { } [expr {$tw - $seg_len + $marg + ($split ? 0 : 1)}]]
        }

        # -- scroll indicator --------------------------------------------------
        set nvrows [llength $vrows]
        if {!$split && $nvrows > $th} {
            set bar_h [expr {max(1, int(double($th) * $th / $nvrows))}]
            set bar_p [expr {int(double($scroll_y) * ($th - $bar_h) / ($nvrows - $th))}]
            for {set i 0} {$i < $th} {incr i} {
                tui-move [expr {$i + $roff}] [expr {$cols - 1}]
                if {$i >= $bar_p && $i < $bar_p + $bar_h} {
                    puts -nonewline "\u2590"
                } else {
                    tui-attr dim; puts -nonewline "\u2502"; tui-attr off
                }
            }
        }
        if {$split} {
            # divider
            for {set i 0} {$i < $th} {incr i} {
                tui-move [expr {$i + $roff}] $half
                tui-attr dim; puts -nonewline "|"; tui-attr off
            }
            # right pane
            set _r_fn [expr {$split_r_fp eq "" ? "scratchpad" : [file tail $split_r_fp]}]
            set _r_ws [expr {$::ws_n == 1 ? 2 : 1}]
            tui-move $roff $rcoff
            tui-attr reverse
            puts -nonewline [string range " \[$_r_ws\] $_r_fn" 0 [expr {$tw_r - 1}]]
            tui-attr off; puts -nonewline "\033\[K"
            set _rsrc_lines [expr {$split_ws2_mode ? $split_r_lines : $lines}]
            for {set i 1} {$i < $th} {incr i} {
                set row_y [expr {$i + $roff}]
                set vr [expr {$split_r_scroll + $i - 1}]
                tui-move $row_y $rcoff
                if {$vr < [llength $split_r_vrows]} {
                    lassign [lindex $split_r_vrows $vr] li scol ecol
                    set rseg [string range [lindex $_rsrc_lines [expr {$li-1}]] $scol [expr {$ecol-1}]]
                    set rish [lindex $split_r_ish [expr {$li-1}]]
                    set risd [lindex $split_r_isd [expr {$li-1}]]
                    set risl [expr {!$rish && !$risd && [parse-list [lindex $_rsrc_lines [expr {$li-1}]]]}]
                    if {$rish} { tui-attr heading } elseif {$risd} { tui-attr dim } elseif {$risl} { tui-attr markup-line }
                    puts -nonewline "[string range $rseg 0 [expr {$tw_r-1}]]\033\[K"
                    if {$rish || $risd || $risl} { tui-attr off }
                } else {
                    puts -nonewline "\033\[K"
                }
            }
        }

        # -- bars --------------------------------------------------------------
        if {$_hm_bar} {
            tui-move [expr {$rows-2}] 0; puts -nonewline "\033\[K"
            tui-move [expr {$rows-1}] 0; puts -nonewline "\033\[K"
        } else {
            set sel_info [expr {$sel_r ne {} ? " \[sel\]" : ""}]
            set sel_hint [expr {$sel_anchor ne "" ? "$::cfg_lbl_sticky cancel-sel" : "$::cfg_lbl_sticky sel"}]
            set _hzone [status-zone-of help_bar]
            if {$::cfg_help_bar ne "" && $_hzone ne ""} { tui-help [expr {$rows-2}] $::cfg_help_bar $cols $_hzone }
            if {$wc_dirty && ([status-zone-of words] ne "" || [status-zone-of chars] ne "" || [status-zone-of goal] ne "")} {
                tui-compute-wc
            }
            timer-tick
            if {$::timer_active || $::timer_last_tick != 0} {
                set timer_display $::timer_remaining
            } else {
                set timer_display [expr {$::cfg_timer_type eq "stopwatch" ? 0 : $::cfg_timer_duration * 60}]
            }
            set tui_state [dict create \
                fn    [expr {$filepath eq "" ? "** scratchpad **" : [file tail $filepath]}] \
                dirty $dirty \
                sel   [expr {$sel_anchor ne ""}] \
                ln    $cy  total [llength $lines] \
                col   [expr {$cx+1}] \
                words $wc_cached \
                chars $cc_cached \
                clock [clock format [clock seconds] -format "%H:%M"] \
                timer $timer_display \
                ws    $::ws_n \
                readonly $readonly]
            if {$::tui_cmd_mode} {
                set bar_left " $message"
                set bar_center ""
                set bar_right ""
            } else {
                set bar_left   " [status-build $::cfg_status_left   $tui_state]"
                set bar_center [status-build $::cfg_status_center $tui_state]
                set bar_right  "[status-build $::cfg_status_right  $tui_state] "
                if {$::cfg_key_error ne "" && $message eq ""} { set message "key conflict: $::cfg_key_error"; set msg_time [clock seconds] }
                if {$message ne "" && [clock seconds] - $msg_time < 4} { set bar_left " $message" }
            }
            tui-bar [expr {$rows-1}] $bar_left $bar_right $cols $bar_center
            set _last_bar_l $bar_left; set _last_bar_c $bar_center; set _last_bar_r $bar_right
        }

        if {$split && $split_focus == 2 && [llength $split_r_vrows] > 0} {
            tui-move [expr {$split_r_vi - $split_r_scroll + $roff + 1}] [expr {$vis_split_r_scx + $rcoff}]
        } else {
            tui-move [expr {$vi - $scroll_y + $roff + ($split ? 1 : 0)}] [expr {$vis_scx + $coff}]
        }
        puts -nonewline "\033\[?25h"; flush stdout
        } ;# _do_draw

        set _gt [expr {($::timer_active && $::cfg_chrono_show) || $::cfg_autosave_enabled ? 50 : -1}]
        set key [tui-getch $_gt]
        set rst       1
        set clear_sel 1

        # Fast path for timer ticks: skip full redraw, update status bar only
        if {$key eq "" && !$wrap_dirty && $dirty_line < 0} {
            if {!$_hm_bar} {
                timer-tick
                set _td [expr {($::timer_active || $::timer_last_tick != 0) ? $::timer_remaining : ($::cfg_timer_type eq "stopwatch" ? 0 : $::cfg_timer_duration * 60)}]
                set _ts [dict create \
                    fn    [expr {$filepath eq "" ? "** scratchpad **" : [file tail $filepath]}] \
                    dirty $dirty sel [expr {$sel_anchor ne ""}] \
                    ln $cy total [llength $lines] col [expr {$cx+1}] \
                    words $wc_cached chars $cc_cached \
                    clock [clock format [clock seconds] -format "%H:%M"] \
                    timer $_td ws $::ws_n readonly $readonly]
                if {$::tui_cmd_mode} {
                    set _bl " $message"; set _bc ""; set _br ""
                } else {
                    set _bl " [status-build $::cfg_status_left $_ts]"
                    set _bc [status-build $::cfg_status_center $_ts]
                    set _br "[status-build $::cfg_status_right $_ts] "
                    if {$message ne "" && [clock seconds] - $msg_time < 4} { set _bl " $message" }
                }
                if {$_bl ne $_last_bar_l || $_bc ne $_last_bar_c || $_br ne $_last_bar_r} {
                    set _last_bar_l $_bl; set _last_bar_c $_bc; set _last_bar_r $_br
                    puts -nonewline "\033\[s"
                    tui-bar [expr {$rows-1}] $_bl $_br $cols $_bc
                    puts -nonewline "\033\[u"; flush stdout
                }
            }
            set _skip_draw 1
            continue
        }

        # -- external modification check ---------------------------------------
        if {$::cfg_watch_file && $filepath ne "" && [file exists $filepath]} {
            set _mtime [file mtime $filepath]
            if {$_mtime != $file_mtime_known} {
                set file_mtime_known $_mtime
                set _wkey [expr {$dirty ? "ed_watch_reload_dirty" : "ed_watch_reload"}]
                if {[tui-confirm [t $_wkey [file tail $filepath]] $rows $cols]} {
                    set lines {}
                    if {[file size $filepath] > 0} {
                        set fh [open $filepath r]; chan configure $fh -encoding utf-8
                        foreach line [split [read $fh] "\n"] { lappend lines $line }
                        close $fh
                        if {[llength $lines] > 1 && [lindex $lines end] eq ""} {
                            set lines [lrange $lines 0 end-1]
                        }
                    }
                    if {[llength $lines] == 0} { set lines [list ""] }
                    set cy 1; set cx 0; set scroll_y 0
                    set undo_stack {}; set redo_stack {}
                    set dirty 0; set wrap_dirty 1
                }
            }
        }

        # split focus==2: swap navigation context (and content for ws2 mode) so key handling targets right pane
        set _fswap 0
        if {$split && $split_focus == 2} {
            if {$split_ws2_mode} {
                foreach {_v _r} {lines split_r_lines  dirty split_r_dirty  filepath split_r_fp} {
                    set _tmp [set $_v]; set $_v [set $_r]; set $_r $_tmp
                }
            }
            foreach {_v _r} {cy split_r_cy  cx split_r_cx  vrows split_r_vrows  ish_cache split_r_ish  isd_cache split_r_isd  scroll_y split_r_scroll  layout_cache split_r_layout  tw tw_r} {
                set _tmp [set $_v]; set $_v [set $_r]; set $_r $_tmp
            }
            set vi $split_r_vi; set scx $split_r_scx
            set _fswap [expr {$split_ws2_mode ? 2 : 1}]
        }

        # modal command mode: arrows drive the bottom menu instead of the cursor
        if {$::tui_cmd_mode} {
            switch -- $key {
                LEFT {
                    set _cm [tui-cmd-menu]
                    set ::tui_cmd_idx [expr {($::tui_cmd_idx - 1 + [llength $_cm]) % [llength $_cm]}]
                    set message [tui-cmd-message $::tui_cmd_idx]; set msg_time [clock seconds]
                    set key ""; set rst 0; set clear_sel 0
                }
                RIGHT {
                    set _cm [tui-cmd-menu]
                    set ::tui_cmd_idx [expr {($::tui_cmd_idx + 1) % [llength $_cm]}]
                    set message [tui-cmd-message $::tui_cmd_idx]; set msg_time [clock seconds]
                    set key ""; set rst 0; set clear_sel 0
                }
                ENTER {
                    set key [lindex [lindex [tui-cmd-menu] $::tui_cmd_idx] 0]
                }
                UP - DOWN - SHIFT-UP - SHIFT-DOWN - SHIFT-LEFT - SHIFT-RIGHT - CTRL-UP - CTRL-DOWN - CTRL-LEFT - CTRL-RIGHT - HOME - END - PPAGE - NPAGE - BACKSPACE - DC - TAB {
                    set key ""; set rst 0; set clear_sel 0
                }
            }
        }
        switch -- $key {
            UP {
                if {$::typewriter_mode && $::cfg_hemingway_mode} {}  \
                elseif {$vi > 0} { if {$sticky<0} {set sticky $scx}; lassign [tui-v2l $vrows [expr {$vi-1}] $sticky] cy cx }
                set rst 0
                if {$sel_sticky} { if {$sel_anchor eq ""} { set sel_anchor [list $cy $cx] }; set clear_sel 0 }
            }
            DOWN {
                if {$::typewriter_mode && $::cfg_hemingway_mode} {}  \
                elseif {$vi < [llength $vrows]-1} { if {$sticky<0} {set sticky $scx}; lassign [tui-v2l $vrows [expr {$vi+1}] $sticky] cy cx }
                set rst 0
                if {$sel_sticky} { if {$sel_anchor eq ""} { set sel_anchor [list $cy $cx] }; set clear_sel 0 }
            }
            SHIFT-UP {
                if {!($::typewriter_mode && $::cfg_hemingway_mode)} {
                    set sel_sticky 0
                    if {$sel_anchor eq ""} { set sel_anchor [list $cy $cx] }
                    if {$vi > 0} { if {$sticky<0} {set sticky $scx}; lassign [tui-v2l $vrows [expr {$vi-1}] $sticky] cy cx }
                    set rst 0; set clear_sel 0
                }
            }
            SHIFT-DOWN {
                if {!($::typewriter_mode && $::cfg_hemingway_mode)} {
                    set sel_sticky 0
                    if {$sel_anchor eq ""} { set sel_anchor [list $cy $cx] }
                    if {$vi < [llength $vrows]-1} { if {$sticky<0} {set sticky $scx}; lassign [tui-v2l $vrows [expr {$vi+1}] $sticky] cy cx }
                    set rst 0; set clear_sel 0
                }
            }
            SHIFT-LEFT {
                if {!($::typewriter_mode && $::cfg_hemingway_mode)} {
                    set sel_sticky 0
                    if {$sel_anchor eq ""} { set sel_anchor [list $cy $cx] }
                    if {$cx > 0} { incr cx -1 } elseif {$cy > 1} { incr cy -1; set cx [string length [lindex $lines [expr {$cy-1}]]] }
                    set clear_sel 0
                }
            }
            SHIFT-RIGHT {
                if {!($::typewriter_mode && $::cfg_hemingway_mode)} {
                    set sel_sticky 0
                    if {$sel_anchor eq ""} { set sel_anchor [list $cy $cx] }
                    if {$cx < [string length [lindex $lines [expr {$cy-1}]]]} { incr cx
                    } elseif {$cy < [llength $lines]} { incr cy; set cx 0 }
                    set clear_sel 0
                }
            }
            LEFT {
                if {$::typewriter_mode && $::cfg_hemingway_mode} {} elseif {$sel_sticky} {
                    if {$cx > 0} { incr cx -1 } elseif {$cy > 1} { incr cy -1; set cx [string length [lindex $lines [expr {$cy-1}]]] }
                    set clear_sel 0
                } elseif {$sel_anchor ne ""} {
                    lassign [tui-sel-range $sel_anchor $cy $cx] cy cx
                } elseif {$cx > 0} { incr cx -1
                } elseif {$cy > 1} { incr cy -1; set cx [string length [lindex $lines [expr {$cy-1}]]] }
            }
            RIGHT {
                if {$::typewriter_mode && $::cfg_hemingway_mode} {} elseif {$sel_sticky} {
                    if {$cx < [string length [lindex $lines [expr {$cy-1}]]]} { incr cx
                    } elseif {$cy < [llength $lines]} { incr cy; set cx 0 }
                    set clear_sel 0
                } elseif {$sel_anchor ne ""} {
                    lassign [tui-sel-range $sel_anchor $cy $cx] sly scx_ ely ecx_
                    set cy $ely; set cx $ecx_
                } elseif {$cx < [string length [lindex $lines [expr {$cy-1}]]]} { incr cx
                } elseif {$cy < [llength $lines]} { incr cy; set cx 0 }
            }
            CTRL-UP {
                set r [expr {$cy - 1}]
                while {$r > 1 && [string trim [lindex $lines [expr {$r-1}]]] eq ""} { incr r -1 }
                while {$r > 1 && [string trim [lindex $lines [expr {$r-2}]]] ne ""} { incr r -1 }
                set cy [expr {max(1,$r)}]; set cx 0; set rst 0
            }
            CTRL-DOWN {
                set r $cy; set _nl [llength $lines]
                while {$r <= $_nl && [string trim [lindex $lines [expr {$r-1}]]] ne ""} { incr r }
                while {$r <= $_nl && [string trim [lindex $lines [expr {$r-1}]]] eq ""} { incr r }
                set cy [expr {min($_nl,$r)}]; set cx 0; set rst 0
            }
            CTRL-LEFT {
                if {$cx == 0 && $cy > 1} {
                    incr cy -1; set cx [string length [lindex $lines [expr {$cy-1}]]]
                }
                set l [lindex $lines [expr {$cy-1}]]
                while {$cx > 0 && [string index $l [expr {$cx-1}]] eq " "} { incr cx -1 }
                while {$cx > 0 && [string index $l [expr {$cx-1}]] ne " "} { incr cx -1 }
                set rst 0
            }
            CTRL-RIGHT {
                set l [lindex $lines [expr {$cy-1}]]; set _nl [llength $lines]
                set len [string length $l]
                while {$cx < $len && [string index $l $cx] ne " "} { incr cx }
                while {$cx < $len && [string index $l $cx] eq " "}  { incr cx }
                if {$cx >= $len && $cy < $_nl} { incr cy; set cx 0 }
                set rst 0
            }
            HOME { set cx [lindex [lindex $vrows $vi] 1] }
            END  { set cx [lindex [lindex $vrows $vi] 2] }
            PPAGE {
                if {$sticky<0} {set sticky $scx}
                lassign [tui-v2l $vrows [expr {max(0,$vi-$th)}] $sticky] cy cx; set rst 0
            }
            NPAGE {
                if {$sticky<0} {set sticky $scx}
                lassign [tui-v2l $vrows [expr {min([llength $vrows]-1,$vi+$th)}] $sticky] cy cx; set rst 0
            }
            BACKSPACE {
                if {!($::typewriter_mode && $::cfg_hemingway_mode)} {
                    tui-push-undo
                    if {$sel_anchor ne ""} {
                        lassign [tui-sel-delete $lines $sel_anchor $cy $cx] lines cy cx; tui-mark-dirty
                    } elseif {$cx > 0} {
                        set l [lindex $lines [expr {$cy-1}]]
                        lset lines [expr {$cy-1}] "[string range $l 0 [expr {$cx-2}]][string range $l $cx end]"
                        incr cx -1; tui-mark-line-dirty
                    } elseif {$cy > 1} {
                        set cx [string length [lindex $lines [expr {$cy-2}]]]
                        lset lines [expr {$cy-2}] "[lindex $lines [expr {$cy-2}]][lindex $lines [expr {$cy-1}]]"
                        set lines [lreplace $lines [expr {$cy-1}] [expr {$cy-1}]]
                        incr cy -1; tui-mark-dirty
                    }
                }
            }
            DC {
                if {!($::typewriter_mode && $::cfg_hemingway_mode)} {
                    tui-push-undo
                    if {$sel_anchor ne ""} {
                        lassign [tui-sel-delete $lines $sel_anchor $cy $cx] lines cy cx; tui-mark-dirty
                    } else {
                        set l [lindex $lines [expr {$cy-1}]]
                        if {$cx < [string length $l]} {
                            lset lines [expr {$cy-1}] "[string range $l 0 [expr {$cx-1}]][string range $l [expr {$cx+1}] end]"
                            tui-mark-line-dirty
                        } elseif {$cy < [llength $lines]} {
                            lset lines [expr {$cy-1}] "${l}[lindex $lines $cy]"
                            set lines [lreplace $lines $cy $cy]; tui-mark-dirty
                        }
                    }
                }
            }
            ENTER {
                tui-push-undo
                if {$sel_anchor ne ""} { lassign [tui-sel-delete $lines $sel_anchor $cy $cx] lines cy cx; tui-mark-dirty }
                set l [lindex $lines [expr {$cy-1}]]
                set lines [linsert [lreplace $lines [expr {$cy-1}] [expr {$cy-1}] \
                    [string range $l 0 [expr {$cx-1}]]] $cy [string range $l $cx end]]
                incr cy; set cx 0; tui-mark-dirty
            }
            TAB {
                tui-push-undo
                if {$sel_anchor ne ""} { lassign [tui-sel-delete $lines $sel_anchor $cy $cx] lines cy cx; tui-mark-dirty }
                set l [lindex $lines [expr {$cy-1}]]
                lset lines [expr {$cy-1}] "[string range $l 0 [expr {$cx-1}]]\t[string range $l $cx end]"
                incr cx 1; tui-mark-line-dirty
            }
            default {
                set c [scan $key %c]
                if {$key eq $::cfg_tui_save} {
                    if {$filepath eq ""} {
                        tui-scratchpad-save $rows $cols lines filepath dirty
                        if {$filepath ne ""} {
                            set file_mtime_known [file mtime $filepath]
                            set message [t ed_saved]; set msg_time [clock seconds]
                        }
                    } elseif {$readonly} {
                        if {[tui-confirm [format [t ed_save_readonly] [file tail $filepath]] $rows $cols]} {
                            set _dir [file dirname $filepath]
                            set _name [string trim [tui-prompt "[t help_save_as]: " $rows $cols]]
                            if {$_name ne ""} {
                                if {[file extension $_name] eq ""} { append _name $::FILE_EXT }
                                set _fp [file join $_dir $_name]
                                if {![file exists $_fp] || [tui-confirm "\"[file tail $_fp]\" exists. Overwrite?" $rows $cols]} {
                                    tui-save-file $_fp $lines
                                    set filepath $_fp; set readonly 0
                                    set file_mtime_known [file mtime $filepath]
                                    recent-push $filepath
                                    set dirty 0; set message [t ed_saved]; set msg_time [clock seconds]
                                }
                            }
                        }
                    } else {
                        tui-save-file $filepath $lines
                        if {$wc_dirty} { tui-compute-wc }
                        daily-update $wc_cached
                        set file_mtime_known [file mtime $filepath]
                        cursor-put $filepath $cy $cx
                        set dirty 0; set message [t ed_saved]; set msg_time [clock seconds]
                    }
                    set clear_sel 0
                } elseif {$::tui_cmd_mode} {
                    # In command mode
                    if {$key eq $::cfg_tui_cmd_mode} {
                        set ::tui_cmd_mode 0
                        set message ""
                        set msg_time [clock seconds]
                        set clear_sel 0
                    } elseif {$key eq "p"} {
                        # Pause if running, resume from saved value if paused
                        if {$::timer_active} { timer-pause } else { timer-resume }
                        set ::tui_cmd_mode 0
                        set message ""
                        set msg_time [clock seconds]
                        set clear_sel 0
                    } elseif {$key eq "t"} {
                        # Start if inactive, reset if active
                        if {$::timer_active} { timer-reset } else { timer-start }
                        set ::tui_cmd_mode 0
                        set message ""
                        set msg_time [clock seconds]
                        set clear_sel 0
                    } elseif {$key eq "q"} {
                        # Quit/close file, exit command mode first
                        set ::tui_cmd_mode 0
                        set _rsl [expr {$_fswap==2 ? $lines : $split_r_lines}]
                        set _rsd [expr {$_fswap==2 ? $dirty : $split_r_dirty}]
                        set _rsf [expr {$_fswap==2 ? $filepath : $split_r_fp}]
                        tui-split-save-right $split $::ws_n $_rsl $_rsd $_rsf
                        lassign [tui-size] rows cols
                        if {$dirty} {
                            if {$readonly} {
                                if {![tui-confirm [t ed_save_readonly_quit] $rows $cols]} {
                                    set clear_sel 0
                                } else {
                                    if {$filepath ne ""} { daily-update $wc_cached; cursor-put $filepath $cy $cx }
                                    if {![tui-ws-check-inactive-dirty $rows $cols]} { set clear_sel 0 } else {
                                        set ::session_file ""; return
                                    }
                                }
                            } else {
                                set r [tui-yesnocancel [t ed_save_before_tui] $rows $cols]
                                if {$r eq "cancel"} {
                                    set clear_sel 0
                                } else {
                                    if {$r eq "yes"} {
                                        if {$filepath eq ""} {
                                            tui-scratchpad-save $rows $cols lines filepath dirty
                                        } else {
                                            tui-save-file $filepath $lines
                                        }
                                    }
                                    if {$filepath ne ""} { daily-update $wc_cached; cursor-put $filepath $cy $cx }
                                    if {![tui-ws-check-inactive-dirty $rows $cols]} { set clear_sel 0 } else {
                                        set ::session_file ""; return
                                    }
                                }
                            }
                        } else {
                            if {$filepath ne ""} { daily-update $wc_cached; cursor-put $filepath $cy $cx }
                            if {![tui-ws-check-inactive-dirty $rows $cols]} { set clear_sel 0 } else {
                                set ::session_file ""; return
                            }
                        }
                    } elseif {$key eq "s"} {
                        lassign [tui-size] rows cols
                        if {$wc_dirty} { tui-compute-wc }
                        if {$filepath ne ""} {
                            daily-update $wc_cached
                            set _r [tui-stats-dialog $filepath $rows $cols]
                            if {$_r ne ""} { set message $_r; set msg_time [clock seconds] }
                        } else {
                            set _sp [scratchpad-stats-record [join $lines "\n"] $wc_cached]
                            set _r [tui-stats-dialog $_sp $rows $cols]
                            if {$_r ne ""} { set message $_r; set msg_time [clock seconds] }
                        }
                        set ::tui_cmd_mode 0
                        puts -nonewline "\033\[2J\033\[H"; flush stdout
                        set wrap_dirty 1
                        set clear_sel 0
                    } elseif {$key eq "w"} {
                        lassign [tui-size] rows cols
                        if {[info procs tui-word-occurrences] ne ""} {
                            set _ap $filepath
                            if {$_ap eq ""} { set _ap [scratch-tmpfile [join $lines "\n"]] }
                            tui-word-occurrences $_ap $rows $cols
                            if {$filepath eq ""} { catch {file delete $_ap} }
                        }
                        set ::tui_cmd_mode 0
                        puts -nonewline "\033\[2J\033\[H"; flush stdout
                        set wrap_dirty 1
                        set clear_sel 0
                    } elseif {$key eq "a"} {
                        lassign [tui-size] rows cols
                        if {[info procs tui-analyse-dialog] ne ""} {
                            set _ap $filepath
                            if {$_ap eq ""} { set _ap [scratch-tmpfile [join $lines "\n"]] }
                            tui-analyse-dialog $_ap $rows $cols
                            if {$filepath eq ""} { catch {file delete $_ap} }
                            if {$::tui_rep_jump ne ""} {
                                set cy [expr {min($::tui_rep_jump, [llength $lines])}]; set cx 0
                            }
                        }
                        set ::tui_cmd_mode 0
                        puts -nonewline "\033\[2J\033\[H"; flush stdout
                        set wrap_dirty 1
                        set clear_sel 0
                    } elseif {$key eq "y"} {
                        lassign [tui-size] rows cols
                        if {[info procs tui-synonyms-dialog] ne ""} {
                            set _word [tui-word-at [lindex $lines [expr {$cy-1}]] $cx]
                            if {$_word ne ""} { tui-synonyms-dialog $_word $rows $cols }
                        }
                        set ::tui_cmd_mode 0
                        puts -nonewline "\033\[2J\033\[H"; flush stdout
                        set wrap_dirty 1
                        set clear_sel 0
                    } elseif {$key eq "b"} {
                        set ::tui_cmd_mode 0
                        set _rsl [expr {$_fswap==2 ? $lines : $split_r_lines}]
                        set _rsd [expr {$_fswap==2 ? $dirty : $split_r_dirty}]
                        set _rsf [expr {$_fswap==2 ? $filepath : $split_r_fp}]
                        tui-split-save-right $split $::ws_n $_rsl $_rsd $_rsf
                        lassign [tui-size] rows cols
                        if {$dirty} {
                            if {$readonly} {
                                if {![tui-confirm [t ed_save_readonly_quit] $rows $cols]} {
                                    set clear_sel 0
                                } else {
                                    if {$filepath ne ""} { daily-update $wc_cached; cursor-put $filepath $cy $cx }
                                    if {![tui-ws-check-inactive-dirty $rows $cols]} { set clear_sel 0 } else {
                                        set ::session_file ""; return
                                    }
                                }
                            } else {
                                set r [tui-yesnocancel [t ed_save_before_tui] $rows $cols]
                                if {$r eq "cancel"} {
                                    set clear_sel 0
                                } else {
                                    if {$r eq "yes"} {
                                        if {$filepath eq ""} {
                                            tui-scratchpad-save $rows $cols lines filepath dirty
                                        } else {
                                            tui-save-file $filepath $lines
                                        }
                                    }
                                    if {$filepath ne ""} { daily-update $wc_cached; cursor-put $filepath $cy $cx }
                                    if {![tui-ws-check-inactive-dirty $rows $cols]} { set clear_sel 0 } else {
                                        set ::session_file ""; return
                                    }
                                }
                            }
                        } else {
                            if {$filepath ne ""} { daily-update $wc_cached; cursor-put $filepath $cy $cx }
                            if {![tui-ws-check-inactive-dirty $rows $cols]} { set clear_sel 0 } else {
                                set ::session_file ""; return
                            }
                        }
                    } elseif {$key ne ""} {
                        # Any non-empty key exits command mode
                        set ::tui_cmd_mode 0
                        set message ""
                        set msg_time [clock seconds]
                        set clear_sel 0
                    }
                } elseif {$key eq $::cfg_tui_cmd_mode} {
                    set ::tui_cmd_mode 1
                    set ::tui_cmd_idx 0
                    set message [tui-cmd-message $::tui_cmd_idx]
                    set msg_time [clock seconds]
                    set clear_sel 0
                } elseif {$key eq $::cfg_tui_close} {
                    set _rsl [expr {$_fswap==2 ? $lines : $split_r_lines}]
                    set _rsd [expr {$_fswap==2 ? $dirty : $split_r_dirty}]
                    set _rsf [expr {$_fswap==2 ? $filepath : $split_r_fp}]
                    tui-split-save-right $split $::ws_n $_rsl $_rsd $_rsf
                    lassign [tui-size] rows cols
                    if {$dirty} {
                        if {$readonly} {
                            if {![tui-confirm [t ed_save_readonly_quit] $rows $cols]} {
                                set clear_sel 0
                            } else {
                                if {$filepath ne ""} { daily-update $wc_cached; cursor-put $filepath $cy $cx }
                                if {![tui-ws-check-inactive-dirty $rows $cols]} { set clear_sel 0 } else {
                                    set ::session_file ""; return
                                }
                            }
                        } else {
                            set r [tui-yesnocancel [t ed_save_before_tui] $rows $cols]
                            if {$r eq "cancel"} {
                                set clear_sel 0
                            } else {
                                if {$r eq "yes"} {
                                    if {$filepath eq ""} {
                                        tui-scratchpad-save $rows $cols lines filepath dirty
                                    } else {
                                        tui-save-file $filepath $lines
                                    }
                                }
                                if {$filepath ne ""} { daily-update $wc_cached; cursor-put $filepath $cy $cx }
                                if {![tui-ws-check-inactive-dirty $rows $cols]} { set clear_sel 0 } else {
                                    set ::session_file ""; return
                                }
                            }
                        }
                    } else {
                        if {$filepath ne ""} { daily-update $wc_cached; cursor-put $filepath $cy $cx }
                        if {![tui-ws-check-inactive-dirty $rows $cols]} { set clear_sel 0 } else {
                            set ::session_file ""; return
                        }
                    }
                } elseif {$key eq $::cfg_tui_open} {
                    set _rsl [expr {$_fswap==2 ? $lines : $split_r_lines}]
                    set _rsd [expr {$_fswap==2 ? $dirty : $split_r_dirty}]
                    set _rsf [expr {$_fswap==2 ? $filepath : $split_r_fp}]
                    tui-split-save-right $split $::ws_n $_rsl $_rsd $_rsf
                    if {$filepath ne "" && !$readonly} { tui-save-file $filepath $lines; daily-update $wc_cached; cursor-put $filepath $cy $cx }
                    set ::session_file ""; set dirty 0
                    if {$::ws_n == 2} { return "__ws2_open__" }
                    return
                } elseif {$key eq $::cfg_tui_undo} {
                    if {!($::typewriter_mode && $::cfg_hemingway_mode) && [llength $undo_stack] > 0} {
                        lappend redo_stack [list $lines $cy $cx]
                        lassign [lindex $undo_stack end] lines cy cx
                        set undo_stack [lrange $undo_stack 0 end-1]; tui-mark-dirty
                    }
                    set clear_sel 0
                } elseif {$key eq $::cfg_tui_redo} {
                    if {[llength $redo_stack] > 0} {
                        lappend undo_stack [list $lines $cy $cx]
                        lassign [lindex $redo_stack end] lines cy cx
                        set redo_stack [lrange $redo_stack 0 end-1]; tui-mark-dirty
                    }
                    set clear_sel 0
                } elseif {$key eq $::cfg_tui_sticky_sel} {
                    if {$sel_sticky} {
                        set sel_sticky 0; set sel_anchor ""
                    } else {
                        set sel_sticky 1; set sel_anchor [list $cy $cx]
                    }
                    set clear_sel 0
                } elseif {$key eq $::cfg_tui_select_all} {
                    set sel_anchor [list 1 0]
                    set cy [llength $lines]; set cx [string length [lindex $lines end]]
                    set clear_sel 0
                } elseif {$key eq $::cfg_tui_copy} {
                    set txt [tui-sel-text $lines $sel_anchor $cy $cx]
                    if {$txt ne ""} { tui-copy $txt; set message "copied"; set msg_time [clock seconds] }
                    set clear_sel 0
                } elseif {$key eq $::cfg_tui_cut} {
                    set txt [tui-sel-text $lines $sel_anchor $cy $cx]
                    if {$txt ne ""} {
                        tui-push-undo; tui-copy $txt
                        lassign [tui-sel-delete $lines $sel_anchor $cy $cx] lines cy cx
                        tui-mark-dirty; set message "cut"; set msg_time [clock seconds]
                    }
                } elseif {$key eq $::cfg_tui_paste || [string match "PASTE:*" $key]} {
                    if {[string match "PASTE:*" $key]} {
                        set txt [string range $key 6 end]
                    } else {
                        set txt [tui-paste]
                    }
                    if {$txt ne ""} {
                        tui-push-undo
                        if {$sel_anchor ne ""} { lassign [tui-sel-delete $lines $sel_anchor $cy $cx] lines cy cx }
                        set plines [split $txt "\n"]
                        set l [lindex $lines [expr {$cy-1}]]
                        set pre [string range $l 0 [expr {$cx-1}]]
                        set post [string range $l $cx end]
                        if {[llength $plines] == 1} {
                            lset lines [expr {$cy-1}] "${pre}${txt}${post}"
                            incr cx [string length $txt]
                        } else {
                            set nl [list "${pre}[lindex $plines 0]"]
                            foreach pl [lrange $plines 1 end-1] { lappend nl $pl }
                            lappend nl "[lindex $plines end]${post}"
                            set lines [lreplace $lines [expr {$cy-1}] [expr {$cy-1}] {*}$nl]
                            incr cy [expr {[llength $plines]-1}]
                            set cx [string length [lindex $plines end]]
                        }
                        tui-mark-dirty
                    }
                } elseif {$key eq $::cfg_tui_find} {
                    lassign [tui-size] rows cols
                    set term [string trim [tui-prompt "find: " $rows $cols]]
                    if {$term ne ""} { set ::tui_search $term }
                    if {$::tui_search ne ""} {
                        set found 0; set n [llength $lines]
                        for {set i 0} {$i < $n} {incr i} {
                            set li [expr {($cy - 1 + $i) % $n + 1}]
                            set l  [lindex $lines [expr {$li - 1}]]
                            set from [expr {$li == $cy && $i == 0 ? $cx + 1 : 0}]
                            set idx [string first [string tolower $::tui_search] [string tolower $l] $from]
                            if {$idx >= 0} { set cy $li; set cx $idx; set found 1; break }
                        }
                        if {!$found} { set message "not found: $::tui_search"; set msg_time [clock seconds] }
                    }
                    set clear_sel 0
                } elseif {$key eq $::cfg_tui_replace} {
                    lassign [tui-size] rows cols
                    set term [string trim [tui-prompt "find: " $rows $cols]]
                    if {$term ne ""} { set ::tui_search $term }
                    if {$::tui_search ne ""} {
                        set repl [tui-prompt "replace with (ESC=cancel): " $rows $cols]
                        if {!$::tui_escaped} {
                            set count 0; set new_lines {}
                            foreach l $lines {
                                set out ""; set pos 0
                                while 1 {
                                    set idx [string first [string tolower $::tui_search] [string tolower $l] $pos]
                                    if {$idx < 0} { append out [string range $l $pos end]; break }
                                    append out [string range $l $pos [expr {$idx-1}]]$repl
                                    set pos [expr {$idx + [string length $::tui_search]}]; incr count
                                }
                                lappend new_lines $out
                            }
                            if {$count > 0} {
                                tui-push-undo; set lines $new_lines; tui-mark-dirty
                                set message "replaced $count occurrence[expr {$count!=1?{s}:{}}]"
                                set msg_time [clock seconds]
                                set cy [expr {max(1, min($cy, [llength $lines]))}]
                                set cx [expr {max(0, min($cx, [string length [lindex $lines [expr {$cy-1}]]]))}]
                            } else { set message "not found: $::tui_search"; set msg_time [clock seconds] }
                        }
                    }
                    set clear_sel 0
                } elseif {$key eq $::cfg_tui_goto} {
                    lassign [tui-size] rows cols
                    set num [tui-prompt "go to line: " $rows $cols]
                    if {[string is integer -strict $num] && $num >= 1} {
                        set cy [expr {min($num, [llength $lines])}]; set cx 0
                    }
                } elseif {$key eq $::cfg_tui_toc} {
                    lassign [tui-size] rows cols
                    set target [tui-toc $lines $rows $cols $cy $filepath]
                    puts -nonewline "\033\[2J"
                    if {[llength $target] >= 2} {
                        set cy [lindex $target 0]; set cx 0
                        set toc_jumped 1
                    }
                } elseif {$key eq $::cfg_tui_dark_toggle} {
                    set ::cfg_dark_mode [expr {!$::cfg_dark_mode}]
                    tui-reverse-video [expr {!$::cfg_dark_mode}]
                    set clear_sel 0
                } elseif {$key eq $::cfg_tui_typewriter} {
                    set ::typewriter_mode [expr {!$::typewriter_mode}]
                    set wrap_dirty 1; puts -nonewline "\033\[2J"
                    set clear_sel 0
                } elseif {$key eq $::cfg_tui_line_nums} {
                    set ::cfg_line_numbers [expr {$::cfg_line_numbers ? 0 : 1}]
                    set clear_sel 0
                } elseif {$key eq $::cfg_tui_help} {
                    lassign [tui-size] rows cols
                    if {$wc_dirty} { tui-compute-wc }
                    set _sel_wc -1; set _sel_cc -1
                    if {$sel_anchor ne ""} {
                        set _stxt [tui-sel-text $lines $sel_anchor $cy $cx]
                        set _sel_wc [llength [regexp -all -inline {\S+} $_stxt]]
                        set _sel_cc [string length $_stxt]
                    }
                    tui-help-dialog $rows $cols $wc_cached $cc_cached $_sel_wc $_sel_cc
                    puts -nonewline "\033\[2J\033\[H"; flush stdout
                    set wrap_dirty 1
                    set clear_sel 0
                } elseif {$key eq "ALT-t"} {
                    if {$::timer_active} { timer-pause } else { timer-start }
                    set clear_sel 0
                } elseif {$key eq "ALT-T"} {
                    timer-reset
                    set clear_sel 0
                } elseif {$key eq $::cfg_tui_workspace} {
                    if {$split && $split_ws2_mode == 0} {
                        # F10 in same-file split: load WS2 into right pane
                        set ::ws_dual_mode 1
                        if {$::ws_n == 1} {
                            set split_r_fp $::ws2_filename; set split_r_dirty $::ws2_dirty; set _c $::ws2_content
                        } else {
                            set split_r_fp $::ws1_filename; set split_r_dirty $::ws1_dirty; set _c $::ws1_content
                        }
                        set split_r_lines [expr {$_c ne "" ? [split $_c "\n"] : [list ""]}]
                        if {$_fswap} {
                            set cy 1; set cx 0; set scroll_y 0
                        } else {
                            set split_r_cy 1; set split_r_cx 0; set split_r_scroll 0
                        }
                        set split_r_wrap_dirty 1; set split_r_layout {}
                        set split_ws2_mode 1; set split_focus 1
                        set wrap_dirty 1; set prev_tw -1
                        puts -nonewline "\033\[2J"; flush stdout
                        set clear_sel 0
                    } elseif {$split && $split_ws2_mode == 1} {
                        # F10 in WS2 split: cycle focus (like F4)
                        set split_focus [expr {$split_focus == 1 ? 2 : 1}]
                        set clear_sel 0
                    } else {
                        # No split: normal workspace toggle
                        tui-split-save-right $split $::ws_n $split_r_lines $split_r_dirty $split_r_fp
                        if {$filepath ne ""} { cursor-put $filepath $cy $cx }
                        set ::tui_ws_save [dict create \
                            filepath $filepath lines $lines cy $cy cx $cx dirty $dirty]
                        set ::session_file ""; return "__ws_toggle__"
                    }
                } elseif {$key eq $::cfg_tui_split} {
                    if {$split} {
                        # Close split
                        if {$split_ws2_mode} {
                            set _rsl [expr {$_fswap==2 ? $lines : $split_r_lines}]
                            set _rsd [expr {$_fswap==2 ? $dirty : $split_r_dirty}]
                            set _rsf [expr {$_fswap==2 ? $filepath : $split_r_fp}]
                            tui-split-save-right 1 $::ws_n $_rsl $_rsd $_rsf
                        }
                        set split 0; set split_ws2_mode 0; set split_focus 1
                        set wrap_dirty 1; set prev_tw -1
                    } else {
                        # Open split: same-file by default
                        set split_r_cy $cy; set split_r_cx $cx; set split_r_scroll $scroll_y
                        set split_r_dirty 0; set split_r_fp $filepath
                        set split_r_lines $lines
                        set split_r_wrap_dirty 1; set split_r_layout {}
                        set split_ws2_mode 0; set split_focus 1
                        set split 1; set wrap_dirty 1; set prev_tw -1
                        # Like GUI: if WS2 was activated, load it into right pane immediately
                        if {$::ws_dual_mode} {
                            if {$::ws_n == 1} {
                                set split_r_fp $::ws2_filename
                                set split_r_dirty $::ws2_dirty
                                set _c $::ws2_content
                            } else {
                                set split_r_fp $::ws1_filename
                                set split_r_dirty $::ws1_dirty
                                set _c $::ws1_content
                            }
                            set split_r_lines [expr {$_c ne "" ? [split $_c "\n"] : [list ""]}]
                            set split_r_cy 1; set split_r_cx 0; set split_r_scroll 0
                            set split_r_wrap_dirty 1; set split_r_layout {}
                            set split_ws2_mode 1
                        }
                    }
                    puts -nonewline "\033\[2J"; flush stdout
                    set clear_sel 0
                } elseif {$split && $key eq $::cfg_tui_split_focus} {
                    # F4: toggle focus between left and right pane
                    set split_focus [expr {$split_focus == 1 ? 2 : 1}]
                    set clear_sel 0
                } elseif {[string match "F*" $key]} {                          ;# ignore unknown F-keys
                    set clear_sel 0
                } elseif {$key eq ""} {                                          ;# timer tick, no key pressed
                    set clear_sel 0
                } elseif {[string length $key] == 1 && ($c eq "" || $c >= 32)} {
                    tui-push-undo
                    if {$sel_anchor ne ""} { lassign [tui-sel-delete $lines $sel_anchor $cy $cx] lines cy cx; tui-mark-dirty }
                    set l [lindex $lines [expr {$cy-1}]]
                    lset lines [expr {$cy-1}] "[string range $l 0 [expr {$cx-1}]]${key}[string range $l $cx end]"
                    incr cx [string length $key]; tui-mark-line-dirty
                }
            }
        }
        if {$_fswap} {
            if {$_fswap == 2} {
                foreach {_v _r} {lines split_r_lines  dirty split_r_dirty  filepath split_r_fp} {
                    set _tmp [set $_v]; set $_v [set $_r]; set $_r $_tmp
                }
            }
            foreach {_v _r} {cy split_r_cy  cx split_r_cx  vrows split_r_vrows  ish_cache split_r_ish  isd_cache split_r_isd  scroll_y split_r_scroll  layout_cache split_r_layout  tw tw_r} {
                set _tmp [set $_v]; set $_v [set $_r]; set $_r $_tmp
            }
            if {$_fswap == 2 && $wrap_dirty}  { set split_r_wrap_dirty 1; set wrap_dirty 0 }
            if {$_fswap == 2 && $dirty_line > 0} { set split_r_wrap_dirty 1; set dirty_line -1 }
            if {$_fswap == 1 && $wrap_dirty}  { set split_r_wrap_dirty 1 }
        }
        if {$rst}       { set sticky -1 }
        if {$clear_sel} { set sel_anchor ""; set sel_sticky 0 }
    }
}

proc tui-info-dialog {text rows cols} {
    set _disp [string map [list $::HOME_DIR ~] $text]
    set _w [expr {min([string length $_disp] + 4, $cols)}]
    set _row [expr {$rows / 2}]
    set _lcol [expr {max(0, ($cols - $_w) / 2)}]
    puts -nonewline "\033\[2J\033\[H"
    foreach _r [list [expr {$_row-1}] [expr {$_row+1}]] {
        tui-move $_r 0; puts -nonewline "\033\[K"
    }
    tui-move $_row $_lcol
    tui-attr reverse
    puts -nonewline [string range "  $_disp  " 0 [expr {$_w-1}]]
    tui-attr off
    tui-bar [expr {$rows-1}] "  q / any key  close" "" $cols
    flush stdout
    set _k ""; while {$_k eq ""} { set _k [tui-getch] }
}

proc tui-stats-dialog {filepath rows cols} {
    if {!$::state_cache_valid} { state-load }
    set name [expr {$filepath eq [scratchpad-stats-path] ? "scratchpad" : [file tail $filepath]}]
    if {![dict exists $::daily_data $filepath] || [dict size [dict get $::daily_data $filepath]] == 0} {
        return [t br_stats_no_data]
    }
    set _fdata [dict get $::daily_data $filepath]
    set _today [clock format [clock seconds] -format "%Y-%m-%d"]
    set _lines [list [list "  [t br_stats_title] - $name" 1] [list "" 0] \
        [list [format "  %-14s %s" "Date" "Words"] 1]]
    set _grand_total 0
    foreach _date [lsort -decreasing [dict keys $_fdata]] {
        set _n [dict get $_fdata $_date]
        incr _grand_total $_n
        set _lbl [expr {$_date eq $_today ? "$_date  <- [t br_stats_today]" : $_date}]
        lappend _lines [list [format "  %-28s %d" $_lbl $_n] 0]
    }
    lappend _lines [list "" 0]
    lappend _lines [list [format "  %-28s %d" [t br_stats_total] $_grand_total] 1]
    lappend _lines [list "" 0]
    set _h [llength $_lines]; set _w 46
    set _left [expr {max(0,($cols-$_w)/2)}]
    set _top  [expr {max(0,($rows-$_h)/2)}]
    puts -nonewline "\033\[2J\033\[H"
    for {set _i 0} {$_i < $_h} {incr _i} {
        tui-move [expr {$_top+$_i}] $_left
        lassign [lindex $_lines $_i] _txt _inv
        if {$_inv} { tui-attr reverse }
        puts -nonewline "[string range $_txt 0 [expr {$_w-1}]]\033\[K"
        if {$_inv} { tui-attr off }
    }
    tui-bar [expr {$rows-1}] "  c [t br_stats_clear]   q / Ctrl+H  close" "" $cols
    flush stdout
    while 1 {
        set _k ""; while {$_k eq ""} { set _k [tui-getch] }
        if {$_k eq "q" || $_k eq $::cfg_tui_help} break
        if {$_k eq "c"} {
            if {[tui-confirm [t br_stats_clear_confirm $name] $rows $cols]} {
                daily-clear $filepath
            }
            break
        }
    }
    return ""
}

proc tui-timer-alert {} {
    lassign [tui-size] rows cols
    while 1 {
        puts -nonewline "\033\[2J"
        set lines {}
        set empty_lines [expr {($rows - 3) / 2}]
        for {set i 0} {$i < $empty_lines} {incr i} { lappend lines "" }
        lappend lines ""
        lappend lines [string repeat " " [expr {($cols - 16) / 2}]] "TIMER FINISHED!"
        lappend lines ""
        for {set i 0} {$i < $empty_lines} {incr i} { lappend lines "" }

        for {set _i 0} {$_i < [llength $lines]} {incr _i} {
            tui-move $_i 0
            puts -nonewline [string range [lindex $lines $_i] 0 [expr {$cols-1}]]
            puts -nonewline "\033\[K"
        }
        tui-bar [expr {$rows-1}] "Press any key to continue" "" $cols
        flush stdout

        set key [tui-getch]
        if {$key ne ""} break
    }
    puts -nonewline "\033\[2J"
}

proc tui-config-dialog {rows cols} {
    catch {
        set timer_dur  $::cfg_timer_duration
        set timer_snd  $::cfg_timer_sound
        set timer_alrt $::cfg_timer_alert
        set timer_typ  $::cfg_timer_type
        set autosave_en  $::cfg_autosave_enabled
        set autosave_int $::cfg_autosave_interval
        set tab 0
        set sel 0
        set max_timer 4
        set max_misc  2

        puts -nonewline "\033\[2J\033\[H"; flush stdout

        while 1 {
            puts -nonewline "\033\[H"

            set _tab0 [expr {$tab == 0 ? "\033\[7m [t config_tab_timer] \033\[m" : " [t config_tab_timer] "}]
            set _tab1 [expr {$tab == 1 ? "\033\[7m [t config_tab_misc] \033\[m"  : " [t config_tab_misc] "}]

            set _lines {}
            lappend _lines "  Config  $_tab0  $_tab1   (TAB to switch)"
            lappend _lines ""

            if {$tab == 0} {
                lappend _lines "  [t timer_section]"
                set _dur_mark  [expr {$sel == 0 ? ">" : " "}]
                lappend _lines "  $_dur_mark [t timer_duration] ${timer_dur}'00\""
                set _type_mark [expr {$sel == 1 ? ">" : " "}]
                lappend _lines "  $_type_mark [t timer_type] $timer_typ"
                set _snd_mark  [expr {$sel == 2 ? ">" : " "}]
                set _snd_txt   [expr {$timer_snd  ? "on" : "off"}]
                lappend _lines "  $_snd_mark [t timer_sound] \[$_snd_txt\]"
                set _alrt_mark [expr {$sel == 3 ? ">" : " "}]
                set _alrt_txt  [expr {$timer_alrt ? "on" : "off"}]
                lappend _lines "  $_alrt_mark [t timer_alert] \[$_alrt_txt\]"
            } else {
                lappend _lines "  [t autosave_section]"
                set _aen_mark  [expr {$sel == 0 ? ">" : " "}]
                set _aen_txt   [expr {$autosave_en ? "on" : "off"}]
                lappend _lines "  $_aen_mark [t autosave_enabled] \[$_aen_txt\]"
                set _aint_mark [expr {$sel == 1 ? ">" : " "}]
                lappend _lines "  $_aint_mark [t autosave_interval] $autosave_int"
            }
            lappend _lines ""

            for {set _i 0} {$_i < [llength $_lines]} {incr _i} {
                tui-move $_i 0
                puts -nonewline [string range [lindex $_lines $_i] 0 [expr {$cols-1}]]
                puts -nonewline "\033\[K"
            }

            set hint "TAB: switch tab  UP/DOWN: nav  LEFT/RIGHT: adjust  s:save  q:cancel"
            tui-bar [expr {$rows-1}] $hint "" $cols
            flush stdout

            set max_fields [expr {$tab == 0 ? $max_timer : $max_misc}]
            set key [tui-getch]
            switch -- $key {
                TAB {
                    set tab [expr {$tab == 0 ? 1 : 0}]
                    set sel 0
                    puts -nonewline "\033\[2J"
                }
                UP - k { if {$sel > 0} { incr sel -1 } }
                DOWN - j { if {$sel < [expr {$max_fields-1}]} { incr sel 1 } }
                LEFT {
                    if {$tab == 0} {
                        if {$sel == 0 && $timer_dur > 1}  { incr timer_dur -1 }
                        if {$sel == 1} { set timer_typ [expr {$timer_typ eq "countdown" ? "stopwatch" : "countdown"}] }
                        if {$sel == 2} { set timer_snd  [expr {!$timer_snd}] }
                        if {$sel == 3} { set timer_alrt [expr {!$timer_alrt}] }
                    } else {
                        if {$sel == 0} { set autosave_en [expr {!$autosave_en}] }
                        if {$sel == 1 && $autosave_int > 1} { incr autosave_int -1 }
                    }
                }
                RIGHT {
                    if {$tab == 0} {
                        if {$sel == 0 && $timer_dur < 120} { incr timer_dur }
                        if {$sel == 1} { set timer_typ [expr {$timer_typ eq "countdown" ? "stopwatch" : "countdown"}] }
                        if {$sel == 2} { set timer_snd  [expr {!$timer_snd}] }
                        if {$sel == 3} { set timer_alrt [expr {!$timer_alrt}] }
                    } else {
                        if {$sel == 0} { set autosave_en [expr {!$autosave_en}] }
                        if {$sel == 1 && $autosave_int < 60} { incr autosave_int }
                    }
                }
                " " {
                    if {$tab == 0} {
                        if {$sel == 1} { set timer_typ [expr {$timer_typ eq "countdown" ? "stopwatch" : "countdown"}] }
                        if {$sel == 2} { set timer_snd  [expr {!$timer_snd}] }
                        if {$sel == 3} { set timer_alrt [expr {!$timer_alrt}] }
                    } else {
                        if {$sel == 0} { set autosave_en [expr {!$autosave_en}] }
                    }
                }
                s {
                    set ::cfg_timer_duration  $timer_dur
                    set ::cfg_timer_type      $timer_typ
                    set ::cfg_timer_sound     $timer_snd
                    set ::cfg_timer_alert     $timer_alrt
                    set ::cfg_autosave_enabled  $autosave_en
                    set ::cfg_autosave_interval $autosave_int
                    ini-save
                    break
                }
                q - "\x1B" { break }
            }
        }
    }
}

proc tui-split-save-right {split ws_n r_lines r_dirty r_fp} {
    if {!$split} return
    if {$ws_n == 1} {
        set ::ws2_content [join $r_lines "\n"]; set ::ws2_dirty $r_dirty; set ::ws2_filename $r_fp
    } else {
        set ::ws1_content [join $r_lines "\n"]; set ::ws1_dirty $r_dirty; set ::ws1_filename $r_fp
    }
}

proc tui-ws-check-inactive-dirty {rows cols} {
    if {!$::ws_dual_mode} { return 1 }
    if {$::ws_n == 1} {
        set iws 2;  set ifn $::ws2_filename;  set isp $::ws2_scratchpad
        set idirty $::ws2_dirty;  set icontent $::ws2_content
    } else {
        set iws 1;  set ifn $::ws1_filename;  set isp $::ws1_scratchpad
        set idirty $::ws1_dirty;  set icontent $::ws1_content
    }
    if {!$idirty || ($ifn eq "" && !$isp)} { return 1 }
    set _name [expr {$isp ? "scratchpad \[$iws\]" : "[file tail $ifn] \[$iws\]"}]
    set r [tui-yesnocancel "$_name: [t ed_save_before_tui]" $rows $cols]
    if {$r eq "cancel"} { return 0 }
    if {$r eq "yes" && $ifn ne ""} {
        set fh [open $ifn w];  chan configure $fh -encoding utf-8
        puts -nonewline $fh $icontent;  close $fh
        if {$iws == 1} { set ::ws1_dirty 0 } else { set ::ws2_dirty 0 }
    }
    return 1
}

proc tui-ws-run {fp} {
    set ::tui_ws_bg [dict create filepath "" lines [list ""] cy 1 cx 0 dirty 0]
    set ::ws_n 1
    set ret [tui-editor $fp]
    while {$ret eq "__ws_toggle__" || $ret eq "__ws2_open__"} {
        if {$ret eq "__ws_toggle__"} {
            set ::ws_dual_mode 1
            set saved $::tui_ws_save
            set next  $::tui_ws_bg
            set ::tui_ws_bg $saved
            set ::ws_n [expr {$::ws_n == 1 ? 2 : 1}]
            # Sync ws1/ws2 globals so split view can read correct inactive-workspace state
            if {$::ws_n == 2} {
                set ::ws1_filename   [dict get $saved filepath]
                set ::ws1_content    [join [dict get $saved lines] "\n"]
                set ::ws1_dirty      [dict get $saved dirty]
                set ::ws1_scratchpad [expr {[dict get $saved filepath] eq ""}]
            } else {
                set ::ws2_filename   [dict get $saved filepath]
                set ::ws2_content    [join [dict get $saved lines] "\n"]
                set ::ws2_dirty      [dict get $saved dirty]
                set ::ws2_scratchpad [expr {[dict get $saved filepath] eq ""}]
            }
            puts -nonewline "\033\[2J"; flush stdout
            set next_fp [dict get $next filepath]
            set ret [tui-editor $next_fp $next]
        } else {
            puts -nonewline "\033\[2J"; flush stdout
            set new_fp [tui-browser]
            if {$new_fp eq ""} { set ::ws_n 1; break }
            puts -nonewline "\033\[2J"; flush stdout
            if {$new_fp eq "__scratchpad__"} { set new_fp "" }
            set ret [tui-editor $new_fp]
        }
    }
    set ::ws_n 1
}

proc tui-main {} {
    if {$::tcl_platform(platform) eq "windows"} {
        puts stderr "writhdeck: TUI mode is not supported on Windows"
        exit 1
    }
    set _stty_fail [catch {exec stty -g <@stdin}]
    if {$_stty_fail} {
        puts stderr "writhdeck: not a terminal"
        exit 1
    }
    tui-init
    set ok [catch {
        if {$::argc > 0} {
            set fp [lindex $::argv 0]
            if {![file exists $fp]} { close [open $fp w] }
            tui-ws-run $fp
        }
        if {$::cfg_browser || $::argc == 0} {
            while 1 {
                set fp [tui-browser]
                if {$fp eq ""} break
                puts -nonewline "\033\[2J"; flush stdout
                if {$fp eq "__scratchpad__"} { tui-ws-run "" } else { tui-ws-run $fp }
            }
        }
    } err info]
    tui-cleanup
    if {$ok} { puts stderr $err }
}


# ===========================================================================
# main-cli.tcl
# ===========================================================================
# --- Development mode: auto-load modules if run directly from src/ ---
if {![info exists ::version]} {
    set srcdir [file dirname [info script]]
    foreach m {boot-cli state config common tui} {
        source [file join $srcdir $m.tcl]
    }
}

# --- CLI-only entry point (always TUI, never GUI) ---
tui-main
