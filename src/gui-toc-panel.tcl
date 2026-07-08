# --- pinned TOC panel (optional module) -----------------------------------------
# Extracted from src/gui.tcl. Optional GUI module (GUI_TOC_PANEL build flag,
# same pattern as src/gui-config.tcl): loaded before gui.tcl, wrapped in
# if {!$::no_gui}. Every call site in gui.tcl / gui-split.tcl is guarded with
# [info procs toc-panel-toggle] ne "" (or gated by ::toc_panel_open, which can
# only become 1 here). The state vars ::toc_panel_open / ::toc_ed stay in
# gui.tcl so var-gated call sites remain valid when this module is absent.
if {!$::no_gui} {

    proc toc-panel-update-margin {on} {
        if {$::split_mode} return
        set mw [expr {$::cfg_margin_width * ($::typewriter_mode && $::cfg_hemingway_mode ? 2 : 1)}]
        set padx_out [expr {$mw - $mw / 3}]
        if {$on} {
            catch { pack configure .ed.t -padx [list $padx_out 0] }
        } else {
            catch { pack configure .ed.t -padx $padx_out }
        }
    }

    proc toc-panel-fill {headings} {
        set lst .ed.toc.lst
        $lst delete 0 end
        if {![llength $headings]} {
            $lst insert end " [t toc_no_headings]"
            return
        }
        foreach item $headings {
            lassign $item ln title level
            set indent [string repeat "  " [expr {$level - 1}]]
            $lst insert end " ${indent}${title}"
        }
    }

    proc toc-panel-select-near-cursor {} {
        if {![winfo exists .ed.toc.lst]} return
        set headings [toc-collect]
        if {![llength $headings]} return
        set curline [lindex [split [$::toc_ed index insert] .] 0]
        set presel 0
        set idx 0
        foreach item $headings {
            if {[lindex $item 0] <= $curline} { set presel $idx }
            incr idx
        }
        .ed.toc.lst selection clear 0 end
        .ed.toc.lst selection set $presel
        .ed.toc.lst see $presel
    }

    proc toc-panel-refresh {} {
        if {!$::toc_panel_open} return
        if {![winfo exists .ed.toc.lst]} return
        set ::toc_ed [active-ed]
        if {$::split_ws2_mode && $::toc_ed eq ".ed.pw.r.t"} {
            set ::toc_fn [expr {$::ws_n == 1 ? $::ws2_filename : $::ws1_filename}]
        } else {
            set ::toc_fn $::filename
        }
        toc-panel-fill [toc-collect]
        toc-panel-select-near-cursor
    }

    proc toc-panel-jump {} {
        if {![winfo exists .ed.toc.lst]} return
        set sel [.ed.toc.lst curselection]
        if {![llength $sel]} return
        set headings [toc-collect]
        set selIdx [lindex $sel 0]
        if {$selIdx >= [llength $headings]} return
        lassign [lindex $headings $selIdx] ln title
        dict set ::session_headings $::toc_fn $selIdx
        $::toc_ed mark set insert $ln.0
        $::toc_ed see insert
        focus $::toc_ed
    }

    proc toc-panel-open {} {
        set ::toc_ed [active-ed]
        if {$::split_ws2_mode && $::toc_ed eq ".ed.pw.r.t"} {
            set ::toc_fn [expr {$::ws_n == 1 ? $::ws2_filename : $::ws1_filename}]
        } else {
            set ::toc_fn $::filename
        }
        lassign [theme-colors] bg fg bg_bar fg_bar bg_sel _ c_heading _ _

        frame .ed.toc -bg $bg_bar -bd 0 -width 180
        pack propagate .ed.toc 0

        frame .ed.toc.sep -bg $fg_bar -width 5 -cursor sb_h_double_arrow
        pack .ed.toc.sep -side left -fill y
        bind .ed.toc.sep <ButtonPress-1>  {
            set ::_toc_drag_x %X
            set ::_toc_drag_w [winfo width .ed.toc]
        }
        bind .ed.toc.sep <B1-Motion> {
            set _w [expr {max(80, min(500, $::_toc_drag_w - (%X - $::_toc_drag_x)))}]
            .ed.toc configure -width $_w
        }

        frame .ed.toc.inner -bg $bg_bar
        pack .ed.toc.inner -fill both -expand 1

        label .ed.toc.inner.hdr -text [t toc_title] \
            -bg $bg_bar -fg $fg_bar -font $::font_sm -anchor w -padx 6 -pady 4
        pack .ed.toc.inner.hdr -side top -fill x

        scrollbar .ed.toc.sb -orient vertical \
            -command {.ed.toc.lst yview} \
            -bg $bg_bar -troughcolor $bg
        listbox .ed.toc.lst \
            -font $::font_sm -bg $bg -fg $c_heading \
            -selectbackground $bg_sel -selectforeground $fg \
            -activestyle none -borderwidth 0 -highlightthickness 0 \
            -relief flat -width 0 -height 0 \
            -yscrollcommand {.ed.toc.sb set}
        pack .ed.toc.sb  -in .ed.toc.inner -side right -fill y
        pack .ed.toc.lst -in .ed.toc.inner -fill both -expand 1

        pack .ed.toc -side right -fill y -after .ed.sb

        bind .ed.toc.lst <ButtonRelease-1>     toc-panel-jump
        bind .ed.toc.lst <Return>              toc-panel-jump
        bind .ed.toc.lst <$::cfg_key_toc>      toc-panel-close
        bind .ed.toc.lst <$::cfg_key_toc_pinned> toc-panel-close
        bind .ed.toc.lst <Escape>              { focus $::toc_ed }

        set ::toc_panel_open 1
        toc-panel-update-margin 1
        toc-panel-fill [toc-collect]
        toc-panel-select-near-cursor
    }

    proc toc-panel-close {} {
        catch { destroy .ed.toc }
        set ::toc_panel_open 0
        toc-panel-update-margin 0
        catch { focus $::toc_ed }
    }

    proc toc-panel-theme {} {
        if {!$::toc_panel_open} return
        lassign [theme-colors] bg fg bg_bar fg_bar bg_sel _ c_heading _ _
        catch { .ed.toc configure -bg $bg_bar }
        catch { .ed.toc.sep configure -bg $fg_bar }
        catch { .ed.toc.inner configure -bg $bg_bar }
        catch { .ed.toc.inner.hdr configure -bg $bg_bar -fg $fg_bar }
        catch { .ed.toc.sb configure -bg $bg_bar -troughcolor $bg }
        catch { .ed.toc.lst configure -bg $bg -fg $c_heading \
                    -selectbackground $bg_sel -selectforeground $fg }
    }

    proc toc-panel-toggle {} {
        if {$::toc_panel_open} { toc-panel-close } else { toc-panel-open }
    }

}
