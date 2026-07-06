# --- split view + second-workspace pane (optional module) ------------------------
# Extracted from src/gui.tcl. Optional GUI module (GUI_SPLIT build flag, same
# pattern as src/gui-config.tcl): loaded before gui.tcl, wrapped in
# if {!$::no_gui}. Call sites in gui.tcl are either guarded with
# [info procs split-toggle] ne "" or gated by ::split_mode / ::split_ws2_mode
# (defined in src/config.tcl, only ever set to 1 here). primary-ed stays in
# gui.tcl (used everywhere, trivial). The pinned-TOC bindings below are
# guarded because the TOC panel is itself an optional module.
if {!$::no_gui} {

    set ::split_ln_was_on 0

    proc split-peer-modified {t} {
        if {[$t edit modified]} { set ::dirty 1; $t edit modified false }
        ed-status
        if {$::hl_after_id ne ""} { after cancel $::hl_after_id }
        set ::hl_after_id [after 300 { set ::hl_after_id ""; highlight-headings; ln-update }]
    }

    proc split-pane-padding {} {
        set px [expr {$::cfg_split_shrink_margin ? max(1,$::cfg_margin_width/2) : $::cfg_margin_width}]
        set py $::cfg_margin_height
        return [list [expr {$px/3}] [expr {$px - $px/3}] [expr {$py/3}] [expr {$py - $py/3}]]
    }

    proc split-make-pane {side bg fg bg_bar bg_sel sp1 sp2 bg2} {
        set frame ".ed.pw.$side"
        frame $frame -bg $bg2
        scrollbar ${frame}.sb -orient vertical -bg $bg_bar -troughcolor $bg
        lassign [split-pane-padding] _padx_in _padx_out _pady_in _pady_out
        .ed.t peer create ${frame}.t \
            -wrap word -font [.ed.t cget -font] \
            -width 1 \
            -bg $bg -fg $fg \
            -insertbackground $fg -selectbackground $bg_sel -selectforeground $fg \
            -blockcursor 0 -insertwidth 2 -insertofftime 0 \
            -borderwidth 0 -padx $_padx_in -pady $_pady_in \
            -highlightthickness 2 -highlightbackground $bg -highlightcolor $fg \
            -yscrollcommand "${frame}.sb set" \
            -spacing1 $sp1 -spacing2 $sp2 -spacing3 0
        ${frame}.sb configure -command "${frame}.t yview"
        pack ${frame}.sb -side right -fill y
        pack ${frame}.t  -fill both  -expand 1 -padx $_padx_out -pady $_pady_out
        set t ${frame}.t
        bind $t <KeyRelease>                { ed-status }
        bind $t <ButtonRelease>             { ed-status }
        bind $t <<Modified>>                [list split-peer-modified $t]
        bind $t <$::cfg_key_save>           { save-file; break }
        bind $t <$::cfg_key_save_as>        { save-as; break }
        bind $t <$::cfg_key_close>          { close-editor; break }
        bind $t <$::cfg_key_paste>          { ed-paste; break }
        bind $t <$::cfg_key_select_all>     "[list $t tag add sel 1.0 end]; break"
        bind $t <$::cfg_key_dark_toggle>    { toggle-dark-mode; break }
        bind $t <Tab>                       {%W insert insert "\t"; break}
        bind $t <$::cfg_key_goto>           { goto-dialog; break }
        bind $t <$::cfg_key_help>           { help-dialog; break }
        bind $t <$::cfg_key_undo>           "if {\$::typewriter_mode && \$::cfg_hemingway_mode} break; [list catch [list $t edit undo]]; ed-status; break"
        bind $t <$::cfg_key_redo>           "[list catch [list $t edit redo]]; ed-status; break"
        bind $t <$::cfg_key_find>           { search-open; break }
        bind $t <$::cfg_key_replace>        { replace-open; break }
        bind $t <$::cfg_key_open>           { open-file-dialog; break }
        bind $t <$::cfg_key_typewriter>     { typewriter-toggle; break }
        bind $t <KeyRelease>               +[list typewriter-tick $t]
        bind $t <ButtonRelease>            +[list typewriter-tick $t]
        foreach _k {Left Right Up Down BackSpace Delete} {
            bind $t <$_k> "if {\$::typewriter_mode && \$::cfg_hemingway_mode} break"
        }
        bind $t <$::cfg_key_toc>            { toc-show; break }
        bind $t <$::cfg_key_toc_pinned>     { if {[info procs toc-panel-toggle] ne ""} { toc-panel-toggle }; break }
        bind $t <$::cfg_key_line_numbers>   { ln-toggle; break }
        bind $t <$::cfg_key_fullscreen>     { toggle-fullscreen; break }
        bind $t <$::cfg_key_split>          { split-toggle; break }
        bind $t <$::cfg_key_split_focus>    { split-cycle-focus; break }
        bind $t <$::cfg_key_workspace>      { workspace-toggle; break }
        bind $t <Control-equal>             { font-resize  1; break }
        bind $t <Control-plus>              { font-resize  1; break }
        bind $t <Control-KP_Add>            { font-resize  1; break }
        bind $t <Control-minus>             { font-resize -1; break }
        bind $t <Control-KP_Subtract>       { font-resize -1; break }
        bind $t <$::cfg_key_sticky_sel>     { break }
        bind-cmd-mode $t
    }

    proc split-open {} {
        if {$::toc_panel_open} { toc-panel-close }
        wm geometry . [winfo width .]x[winfo height .]
        lassign [theme-colors] bg fg bg_bar fg_bar bg_sel _ _ _ bg2
        set sp1 [.ed.t cget -spacing1]
        set sp2 [.ed.t cget -spacing2]
        set cur [.ed.t index insert]

        pack forget .ed.t .ed.sb
        if {[winfo exists .ed.ln]} {
            set ::split_ln_was_on 1
            pack forget .ed.ln
        } else {
            set ::split_ln_was_on 0
        }

        panedwindow .ed.pw -orient horizontal -bg $bg_bar -sashwidth 4 -sashpad 0 -sashrelief flat
        split-make-pane l $bg $fg $bg_bar $bg_sel $sp1 $sp2 $bg2
        split-make-pane r $bg $fg $bg_bar $bg_sel $sp1 $sp2 $bg2
        .ed.pw add .ed.pw.l -stretch always
        .ed.pw add .ed.pw.r -stretch always
        pack .ed.pw -fill both -expand 1 -before .ed.bar

        .ed.pw.l.t mark set insert $cur
        .ed.pw.l.t see insert

        set ::split_mode 1
        focus .ed.pw.l.t
        if {$::ws_dual_mode} { split-ws2-open; focus .ed.pw.l.t }
    }

    proc split-close {} {
        if {!$::split_mode} return
        if {$::split_ws2_mode} {
            split-ws2-save-state
            set ::split_ws2_mode 0
        }
        catch { .ed.t mark set insert [.ed.pw.l.t index insert] }
        pack forget .ed.pw
        destroy .ed.pw
        pack .ed.sb  -side right -fill y
        if {$::split_ln_was_on && [winfo exists .ed.ln]} {
            pack .ed.ln -side left  -fill y
        }
        pack .ed.t -fill both -expand 1 \
            -padx [expr {$::cfg_margin_width - $::cfg_margin_width/3}] \
            -pady [expr {$::cfg_margin_height - $::cfg_margin_height/3}]
        .ed.t see insert
        set ::split_mode 0
        focus .ed.t
    }

    proc split-toggle {} {
        if {$::split_mode} { split-close } else { split-open }
    }

    proc split-cycle-focus {} {
        if {!$::split_mode} return
        if {[focus] eq ".ed.pw.r.t"} {
            focus .ed.pw.l.t
        } else {
            focus .ed.pw.r.t
        }
        if {$::split_ws2_mode} { ed-update-title }
    }

    proc split-ws2-open {} {
        lassign [theme-colors] bg fg bg_bar fg_bar bg_sel _ _ _ bg2
        set sp1 [.ed.t cget -spacing1]
        set sp2 [.ed.t cget -spacing2]
        lassign [split-pane-padding] _padx_in _padx_out _pady_in _pady_out
        catch { pack forget .ed.pw.r.sb .ed.pw.r.t }
        catch { destroy .ed.pw.r.t }
        text .ed.pw.r.t \
            -wrap word -font [.ed.t cget -font] -width 1 \
            -bg $bg -fg $fg -insertbackground $fg \
            -selectbackground $bg_sel -selectforeground $fg \
            -blockcursor 0 -insertwidth 2 -insertofftime 0 \
            -borderwidth 0 -padx $_padx_in -pady $_pady_in \
            -highlightthickness 2 -highlightbackground $bg -highlightcolor $fg \
            -yscrollcommand ".ed.pw.r.sb set" -spacing1 $sp1 -spacing2 $sp2 -spacing3 0
        .ed.pw.r.sb configure -command ".ed.pw.r.t yview"
        pack .ed.pw.r.sb -side right -fill y
        pack .ed.pw.r.t  -fill both  -expand 1 -padx $_padx_out -pady $_pady_out
        if {$::ws_n == 1} {
            set _r_content $::ws2_content;  set _r_dirty $::ws2_dirty;  set _r_cursor $::ws2_cursor
        } else {
            set _r_content $::ws1_content;  set _r_dirty $::ws1_dirty;  set _r_cursor $::ws1_cursor
        }
        .ed.pw.r.t configure -undo 0
        .ed.pw.r.t delete 1.0 end
        if {$_r_content ne ""} { .ed.pw.r.t insert 1.0 $_r_content }
        .ed.pw.r.t edit reset
        .ed.pw.r.t edit modified false
        .ed.pw.r.t configure -undo 1
        if {$_r_dirty} { .ed.pw.r.t edit modified true }
        catch { .ed.pw.r.t mark set insert $_r_cursor }
        .ed.pw.r.t see insert
        bind .ed.pw.l.t <FocusIn>               { if {$::split_ws2_mode} { ed-update-title } }
        bind .ed.pw.r.t <<Modified>>             { split-ws2-track-dirty }
        bind .ed.pw.r.t <FocusIn>               { ed-update-title }
        bind .ed.pw.r.t <KeyRelease>             { ed-status }
        bind .ed.pw.r.t <ButtonRelease>          { ed-status }
        bind .ed.pw.r.t <$::cfg_key_save>        { split-ws2-save; break }
        bind .ed.pw.r.t <$::cfg_key_save_as>     { split-ws2-save-as; break }
        bind .ed.pw.r.t <$::cfg_key_close>       { split-toggle; break }
        bind .ed.pw.r.t <$::cfg_key_paste>       { ed-paste; break }
        bind .ed.pw.r.t <$::cfg_key_select_all>  { .ed.pw.r.t tag add sel 1.0 end; break }
        bind .ed.pw.r.t <$::cfg_key_dark_toggle> { toggle-dark-mode; break }
        bind .ed.pw.r.t <Tab>                    { .ed.pw.r.t insert insert "\t"; break }
        bind .ed.pw.r.t <$::cfg_key_goto>        { goto-dialog; break }
        bind .ed.pw.r.t <$::cfg_key_help>        { help-dialog; break }
        bind .ed.pw.r.t <$::cfg_key_undo>        { catch {.ed.pw.r.t edit undo}; ed-status; break }
        bind .ed.pw.r.t <$::cfg_key_redo>        { catch {.ed.pw.r.t edit redo}; ed-status; break }
        bind .ed.pw.r.t <$::cfg_key_find>        { search-open; break }
        bind .ed.pw.r.t <$::cfg_key_replace>     { replace-open; break }
        bind .ed.pw.r.t <$::cfg_key_open>        { open-file-dialog; break }
        bind .ed.pw.r.t <$::cfg_key_toc>         { toc-show; break }
        bind .ed.pw.r.t <$::cfg_key_toc_pinned>  { if {[info procs toc-panel-toggle] ne ""} { toc-panel-toggle }; break }
        bind .ed.pw.r.t <$::cfg_key_line_numbers> { ln-toggle; break }
        bind .ed.pw.r.t <$::cfg_key_fullscreen>  { toggle-fullscreen; break }
        bind .ed.pw.r.t <$::cfg_key_typewriter>  { typewriter-toggle; break }
        bind .ed.pw.r.t <KeyRelease>            +[list typewriter-tick .ed.pw.r.t]
        bind .ed.pw.r.t <ButtonRelease>         +[list typewriter-tick .ed.pw.r.t]
        foreach _k {Left Right Up Down BackSpace Delete} {
            bind .ed.pw.r.t <$_k> "if {\$::typewriter_mode && \$::cfg_hemingway_mode} break"
        }
        bind .ed.pw.r.t <$::cfg_key_split>       { split-toggle; break }
        bind .ed.pw.r.t <$::cfg_key_split_focus> { split-cycle-focus; break }
        bind .ed.pw.r.t <$::cfg_key_workspace>   { workspace-toggle; break }
        bind .ed.pw.r.t <Control-equal>          { font-resize  1; break }
        bind .ed.pw.r.t <Control-plus>           { font-resize  1; break }
        bind .ed.pw.r.t <Control-KP_Add>         { font-resize  1; break }
        bind .ed.pw.r.t <Control-minus>          { font-resize -1; break }
        bind .ed.pw.r.t <Control-KP_Subtract>    { font-resize -1; break }
        bind .ed.pw.r.t <$::cfg_key_sticky_sel>  { break }
        bind-cmd-mode .ed.pw.r.t
        set ::ws_dual_mode 1
        set ::split_ws2_mode 1
        focus .ed.pw.r.t
    }

    proc split-ws2-track-dirty {} {
        if {[.ed.pw.r.t edit modified]} {
            if {$::ws_n == 1} { set ::ws2_dirty 1 } else { set ::ws1_dirty 1 }
            .ed.pw.r.t edit modified false
        }
        ed-status
    }

    proc split-ws2-save {} {
        set fn [expr {$::ws_n == 1 ? $::ws2_filename : $::ws1_filename}]
        if {$fn eq ""} { split-ws2-save-as; return }
        if {[file exists $fn] && ![file writable $fn]} {
            if {[confirm-dialog [format [t ed_save_readonly] [file tail $fn]]] eq "yes"} { split-ws2-save-as }
            return
        }
        if {[catch {set fh [open $fn w]} err]} { return }
        chan configure $fh -encoding utf-8
        puts -nonewline $fh [.ed.pw.r.t get 1.0 {end - 1 chars}]; close $fh
        if {$::ws_n == 1} {
            set ::ws2_dirty 0; set ::ws2_file_mtime [file mtime $fn]
        } else {
            set ::ws1_dirty 0; set ::ws1_file_mtime [file mtime $fn]
        }
        .ed.pw.r.t edit modified false
        ed-status
    }

    proc split-ws2-save-as {} {
        set cur_fn [expr {$::ws_n == 1 ? $::ws2_filename : $::ws1_filename}]
        set dir [expr {$cur_fn ne "" ? [file dirname $cur_fn] : $::DOCS_DIR_DEFAULT}]
        set name [string trim [input-dialog "Save as" "Save as:"]]
        if {$name eq ""} return
        if {[file extension $name] eq ""} { append name $::FILE_EXT }
        set new_path [file join $dir $name]
        if {[file exists $new_path] && $new_path ne $cur_fn} {
            if {[confirm-dialog "\"$name\" already exists. Overwrite?"] ne "yes"} return
        }
        if {$::ws_n == 1} { set ::ws2_filename $new_path; set ::ws2_scratchpad 0
        } else              { set ::ws1_filename $new_path; set ::ws1_scratchpad 0 }
        split-ws2-save
    }

    proc split-ws2-load-file {path} {
        .ed.pw.r.t configure -undo 0
        .ed.pw.r.t delete 1.0 end
        if {[file exists $path] && [file size $path] > 0} {
            set fh [open $path r]; chan configure $fh -encoding utf-8
            .ed.pw.r.t insert 1.0 [read $fh]; close $fh
        }
        .ed.pw.r.t edit reset; .ed.pw.r.t edit modified false
        .ed.pw.r.t configure -undo 1
        if {$::ws_n == 1} {
            set ::ws2_filename $path; set ::ws2_scratchpad 0; set ::ws2_dirty 0
            set ::ws2_file_mtime [expr {[file exists $path] ? [file mtime $path] : 0}]
        } else {
            set ::ws1_filename $path; set ::ws1_scratchpad 0; set ::ws1_dirty 0
            set ::ws1_file_mtime [expr {[file exists $path] ? [file mtime $path] : 0}]
        }
        recent-push $path
        .ed.pw.r.t mark set insert 1.0; .ed.pw.r.t see insert
        ed-status
    }

    proc split-ws2-save-state {} {
        if {![winfo exists .ed.pw.r.t]} return
        if {$::ws_n == 1} {
            set ::ws2_content [.ed.pw.r.t get 1.0 end-1c]
            set ::ws2_cursor  [.ed.pw.r.t index insert]
        } else {
            set ::ws1_content [.ed.pw.r.t get 1.0 end-1c]
            set ::ws1_cursor  [.ed.pw.r.t index insert]
        }
    }

}
