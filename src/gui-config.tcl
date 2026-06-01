if {!$::no_gui} {

proc profile-config-update-profile {w} {
    set profile $::profile_config_profile
    if {$profile eq ""} return

    set cur_font $::cfg_font_family
    if {[dict exists $::cfg_profiles $profile font_family]} {
        set cur_font [dict get $::cfg_profiles $profile font_family]
    }
    $w.tab_fonts.ffont.entry delete 0 end
    $w.tab_fonts.ffont.entry insert 0 $cur_font

    set cur_size $::cfg_font_size
    if {[dict exists $::cfg_profiles $profile font_size]} {
        set cur_size [dict get $::cfg_profiles $profile font_size]
    }
    $w.tab_fonts.fsize.spin set $cur_size
    catch {$w.tab_fonts.preview configure -font [list $cur_font $cur_size] -text "Sample Text - $cur_font"}

    set cur_mw $::cfg_margin_width
    if {[dict exists $::cfg_profiles $profile margin_width]} {
        set cur_mw [dict get $::cfg_profiles $profile margin_width]
    }
    $w.tab_profile.fmarginw.spin set $cur_mw

    set cur_mh $::cfg_margin_height
    if {[dict exists $::cfg_profiles $profile margin_height]} {
        set cur_mh [dict get $::cfg_profiles $profile margin_height]
    }
    $w.tab_profile.fmarginh.spin set $cur_mh

    set cur_goal $::cfg_word_goal
    if {[dict exists $::cfg_profiles $profile word_goal]} {
        set cur_goal [dict get $::cfg_profiles $profile word_goal]
    }
    $w.tab_profile.fwordgoal.spin set $cur_goal

    set cur_dark $::cfg_dark_mode
    if {[dict exists $::cfg_profiles $profile dark_mode]} {
        set cur_dark [dict get $::cfg_profiles $profile dark_mode]
    }
    set ::profile_config_dark_mode $cur_dark

    set cur_ls $::cfg_line_spacing
    if {[dict exists $::cfg_profiles $profile line_spacing]} {
        set cur_ls [dict get $::cfg_profiles $profile line_spacing]
    }
    $w.tab_profile.flinespace.spin set $cur_ls

    set cur_bh $::cfg_bar_height
    if {[dict exists $::cfg_profiles $profile bar_height]} {
        set cur_bh [dict get $::cfg_profiles $profile bar_height]
    }
    $w.tab_profile.fbarheight.spin set $cur_bh

    set cur_ln $::cfg_line_numbers
    if {[dict exists $::cfg_profiles $profile line_numbers]} {
        set cur_ln [string is true [dict get $::cfg_profiles $profile line_numbers]]
    }
    set ::profile_config_line_numbers $cur_ln

    set cur_bc $::cfg_block_cursor_gui
    if {[dict exists $::cfg_profiles $profile block_cursor_gui]} {
        set cur_bc [string is true [dict get $::cfg_profiles $profile block_cursor_gui]]
    }
    set ::profile_config_block_cursor $cur_bc

    set cur_bl $::cfg_blink_cursor
    if {[dict exists $::cfg_profiles $profile blink_cursor]} {
        set cur_bl [string is true [dict get $::cfg_profiles $profile blink_cursor]]
    }
    set ::profile_config_blink_cursor $cur_bl

    set idx [lsearch -exact [lsort [font families]] $cur_font]
    $w.tab_fonts.fonts selection clear 0 end
    if {$idx >= 0} { $w.tab_fonts.fonts selection set $idx; $w.tab_fonts.fonts see $idx }
}

proc config-tab-switch {w tab} {
    pack forget $w.tab_profile $w.tab_fonts $w.tab_timer $w.tab_misc $w.tab_display
    $w.tabs.profile configure -fg $::fg_bar -bg $::bg
    $w.tabs.fonts   configure -fg $::fg_bar -bg $::bg
    $w.tabs.timer   configure -fg $::fg_bar -bg $::bg
    $w.tabs.misc    configure -fg $::fg_bar -bg $::bg
    $w.tabs.display configure -fg $::fg_bar -bg $::bg
    if {$tab eq "profile"} {
        pack $w.tab_profile -fill both -expand 1 -padx 8 -pady 8
        $w.tabs.profile configure -fg $::fg -bg $::bg_sel
    } elseif {$tab eq "fonts"} {
        pack $w.tab_fonts -fill both -expand 1 -padx 8 -pady 8
        $w.tabs.fonts configure -fg $::fg -bg $::bg_sel
    } elseif {$tab eq "timer"} {
        pack $w.tab_timer -fill both -expand 1 -padx 8 -pady 8
        $w.tabs.timer configure -fg $::fg -bg $::bg_sel
    } elseif {$tab eq "display"} {
        pack $w.tab_display -fill both -expand 1 -padx 8 -pady 8
        $w.tabs.display configure -fg $::fg -bg $::bg_sel
    } else {
        pack $w.tab_misc -fill both -expand 1 -padx 8 -pady 8
        $w.tabs.misc configure -fg $::fg -bg $::bg_sel
    }
}

proc profile-config-dialog {} {
    set w .profile_config
    catch {destroy $w}
    catch {unset ::profile_config_profile}
    toplevel $w
    wm title $w [t profile_config_title]
    wm transient $w .
    $w configure -bg $::bg

    set profiles [lsort [dict keys $::cfg_profiles]]
    set schemes [lsort [dict keys $::cfg_schemes]]

    if {[llength $profiles] == 0} {
        label $w.msg -text "No profiles defined" -font $::font_sm -fg $::fg_bar -bg $::bg -padx 16 -pady 12
        button $w.close -text [t profile_config_cancel] -font $::font_sm \
            -command "destroy $w" -bg $::bg_bar -fg $::fg_bar
        pack $w.msg -fill x
        pack $w.close -pady 8
        update
        grab $w
        focus $w.close
        return
    }

    # --- Tab bar ---
    frame $w.tabs -bg $::bg
    pack $w.tabs -fill x -padx 8 -pady {8 0}
    button $w.tabs.profile -text [t config_tab_profile] -font $::font_sm -fg $::fg -bg $::bg_sel \
        -command "config-tab-switch $w profile" -borderwidth 1 -relief raised -padx 12 -pady 4
    button $w.tabs.fonts -text [t config_tab_fonts] -font $::font_sm -fg $::fg_bar -bg $::bg \
        -command "config-tab-switch $w fonts" -borderwidth 1 -relief raised -padx 12 -pady 4
    button $w.tabs.timer -text [t config_tab_timer] -font $::font_sm -fg $::fg_bar -bg $::bg \
        -command "config-tab-switch $w timer" -borderwidth 1 -relief raised -padx 12 -pady 4
    button $w.tabs.misc -text [t config_tab_misc] -font $::font_sm -fg $::fg_bar -bg $::bg \
        -command "config-tab-switch $w misc" -borderwidth 1 -relief raised -padx 12 -pady 4
    button $w.tabs.display -text [t config_tab_display] -font $::font_sm -fg $::fg_bar -bg $::bg \
        -command "config-tab-switch $w display" -borderwidth 1 -relief raised -padx 12 -pady 4
    pack $w.tabs.profile -side left -padx 2
    pack $w.tabs.fonts -side left -padx 2
    pack $w.tabs.timer -side left -padx 2
    pack $w.tabs.misc -side left -padx 2
    pack $w.tabs.display -side left -padx 2

    # --- Tab content frames ---
    frame $w.tab_profile -bg $::bg
    frame $w.tab_fonts -bg $::bg
    frame $w.tab_timer -bg $::bg
    frame $w.tab_misc -bg $::bg
    frame $w.tab_display -bg $::bg
    pack $w.tab_profile -fill both -expand 1 -padx 8 -pady 8

    # --- Profile tab content ---
    # --- Global settings frame ---
    frame $w.tab_profile.global -relief ridge -borderwidth 2 -bg $::bg
    pack $w.tab_profile.global -fill x -padx 0 -pady 8

    label $w.tab_profile.global.title -text "Global Settings" -font $::font_sm -fg $::fg_bar -bg $::bg
    pack $w.tab_profile.global.title -anchor w -padx 8 -pady {4 2}

    label $w.tab_profile.global.lbl_defprof -text [t profile_config_default_profile] -font $::font_sm -bg $::bg -fg $::fg
    pack $w.tab_profile.global.lbl_defprof -anchor w -padx 12 -pady {4 2}
    frame $w.tab_profile.global.fprof -bg $::bg
    pack $w.tab_profile.global.fprof -fill x -padx 12 -pady {0 6}
    tk_optionMenu $w.tab_profile.global.fprof.om ::profile_config_default_prof {*}$profiles
    $w.tab_profile.global.fprof.om configure -bg $::bg_bar -fg $::fg_bar -activebackground $::bg_sel -activeforeground $::fg -borderwidth 1 -highlightthickness 0
    set ::profile_config_default_prof $::cfg_profile
    pack $w.tab_profile.global.fprof.om -anchor w

    label $w.tab_profile.global.lbl_scheme -text [t profile_config_default_scheme] -font $::font_sm -bg $::bg -fg $::fg
    pack $w.tab_profile.global.lbl_scheme -anchor w -padx 12 -pady {4 2}
    frame $w.tab_profile.global.fscheme -bg $::bg
    pack $w.tab_profile.global.fscheme -fill x -padx 12 -pady {0 6}
    tk_optionMenu $w.tab_profile.global.fscheme.om ::profile_config_default_scheme {*}$schemes
    $w.tab_profile.global.fscheme.om configure -bg $::bg_bar -fg $::fg_bar -activebackground $::bg_sel -activeforeground $::fg -borderwidth 1 -highlightthickness 0
    set ::profile_config_default_scheme $::cfg_scheme
    pack $w.tab_profile.global.fscheme.om -anchor w

    label $w.tab_profile.global.lbl_lang -text [t profile_config_language] -font $::font_sm -bg $::bg -fg $::fg
    pack $w.tab_profile.global.lbl_lang -anchor w -padx 12 -pady {4 2}
    frame $w.tab_profile.global.flang -bg $::bg
    pack $w.tab_profile.global.flang -fill x -padx 12 -pady {0 6}
    set langs [lsort [dict keys $::i18n]]
    tk_optionMenu $w.tab_profile.global.flang.om ::profile_config_language {*}$langs
    $w.tab_profile.global.flang.om configure -bg $::bg_bar -fg $::fg_bar -activebackground $::bg_sel -activeforeground $::fg -borderwidth 1 -highlightthickness 0
    set ::profile_config_language $::cfg_lang
    pack $w.tab_profile.global.flang.om -anchor w

    # --- Profile-specific settings frame ---
    frame $w.tab_profile.profile -relief ridge -borderwidth 2 -bg $::bg
    pack $w.tab_profile.profile -fill x -padx 0 -pady 8

    label $w.tab_profile.profile.title -text "Profile Settings" -font $::font_sm -fg $::fg_bar -bg $::bg
    pack $w.tab_profile.profile.title -anchor w -padx 8 -pady {4 2}

    # Profile selector row
    frame $w.tab_profile.profile.fprof -bg $::bg
    pack $w.tab_profile.profile.fprof -fill x -padx 12 -pady {0 6}
    label $w.tab_profile.profile.fprof.lbl -text [t profile_config_edit_profile] -font $::font_sm -width 20 -anchor w -bg $::bg -fg $::fg
    tk_optionMenu $w.tab_profile.profile.fprof.om ::profile_config_profile {*}$profiles
    $w.tab_profile.profile.fprof.om configure -bg $::bg_bar -fg $::fg_bar -activebackground $::bg_sel -activeforeground $::fg -borderwidth 1 -highlightthickness 0
    if {[lsearch -exact $profiles $::cfg_profile] >= 0} {
        set ::profile_config_profile $::cfg_profile
    } else {
        set ::profile_config_profile [lindex $profiles 0]
    }
    pack $w.tab_profile.profile.fprof.lbl -side left -padx {0 8}
    pack $w.tab_profile.profile.fprof.om -side left -fill x -expand 1 -padx {8 0}

    # Margin width row
    frame $w.tab_profile.fmarginw -bg $::bg
    pack $w.tab_profile.fmarginw -fill x -padx 12 -pady 4
    label $w.tab_profile.fmarginw.lbl -text [t profile_config_margin_w] -font $::font_sm -width 20 -anchor w -bg $::bg -fg $::fg
    spinbox $w.tab_profile.fmarginw.spin -from 0 -to 200 -width 5 -font $::font_sm -bg $::bg_bar -fg $::fg
    pack $w.tab_profile.fmarginw.lbl -side left
    pack $w.tab_profile.fmarginw.spin -side left -padx {8 0}

    # Margin height row
    frame $w.tab_profile.fmarginh -bg $::bg
    pack $w.tab_profile.fmarginh -fill x -padx 12 -pady 4
    label $w.tab_profile.fmarginh.lbl -text [t profile_config_margin_h] -font $::font_sm -width 20 -anchor w -bg $::bg -fg $::fg
    spinbox $w.tab_profile.fmarginh.spin -from 0 -to 200 -width 5 -font $::font_sm -bg $::bg_bar -fg $::fg
    pack $w.tab_profile.fmarginh.lbl -side left
    pack $w.tab_profile.fmarginh.spin -side left -padx {8 0}

    # Word goal row
    frame $w.tab_profile.fwordgoal -bg $::bg
    pack $w.tab_profile.fwordgoal -fill x -padx 12 -pady 4
    label $w.tab_profile.fwordgoal.lbl -text [t profile_config_word_goal] -font $::font_sm -width 20 -anchor w -bg $::bg -fg $::fg
    spinbox $w.tab_profile.fwordgoal.spin -from 0 -to 10000 -width 8 -font $::font_sm -bg $::bg_bar -fg $::fg
    label $w.tab_profile.fwordgoal.hint -text "(words/day, 0=disabled)" -font $::font_sm -fg $::fg_bar -bg $::bg
    pack $w.tab_profile.fwordgoal.lbl -side left
    pack $w.tab_profile.fwordgoal.spin -side left -padx {8 4}
    pack $w.tab_profile.fwordgoal.hint -side left

    # Dark mode row
    frame $w.tab_profile.fdarkmode -bg $::bg
    pack $w.tab_profile.fdarkmode -fill x -padx 12 -pady 4
    label $w.tab_profile.fdarkmode.lbl -text [t profile_config_dark_mode] -font $::font_sm -width 20 -anchor w -bg $::bg -fg $::fg
    checkbutton $w.tab_profile.fdarkmode.check -variable profile_config_dark_mode -font $::font_sm -bg $::bg -fg $::fg \
        -selectcolor $::bg_sel -activebackground $::bg -activeforeground $::fg \
        -borderwidth 1 -relief raised -highlightthickness 1 -highlightbackground $::fg_bar
    pack $w.tab_profile.fdarkmode.lbl -side left
    pack $w.tab_profile.fdarkmode.check -side left -padx {8 2}

    # Line spacing row
    frame $w.tab_profile.flinespace -bg $::bg
    pack $w.tab_profile.flinespace -fill x -padx 12 -pady 4
    label $w.tab_profile.flinespace.lbl -text [t profile_config_line_spacing] -font $::font_sm -width 20 -anchor w -bg $::bg -fg $::fg
    spinbox $w.tab_profile.flinespace.spin -from 80 -to 200 -width 5 -font $::font_sm -bg $::bg_bar -fg $::fg
    pack $w.tab_profile.flinespace.lbl -side left
    pack $w.tab_profile.flinespace.spin -side left -padx {8 0}

    # Bar height row
    frame $w.tab_profile.fbarheight -bg $::bg
    pack $w.tab_profile.fbarheight -fill x -padx 12 -pady 4
    label $w.tab_profile.fbarheight.lbl -text [t profile_config_bar_height] -font $::font_sm -width 20 -anchor w -bg $::bg -fg $::fg
    spinbox $w.tab_profile.fbarheight.spin -from 0 -to 40 -width 5 -font $::font_sm -bg $::bg_bar -fg $::fg
    pack $w.tab_profile.fbarheight.lbl -side left
    pack $w.tab_profile.fbarheight.spin -side left -padx {8 0}

    # Line numbers row
    frame $w.tab_profile.flinenums -bg $::bg
    pack $w.tab_profile.flinenums -fill x -padx 12 -pady 4
    label $w.tab_profile.flinenums.lbl -text [t profile_config_line_numbers] -font $::font_sm -width 20 -anchor w -bg $::bg -fg $::fg
    checkbutton $w.tab_profile.flinenums.check -variable profile_config_line_numbers -font $::font_sm -bg $::bg -fg $::fg \
        -selectcolor $::bg_sel -activebackground $::bg -activeforeground $::fg \
        -borderwidth 1 -relief raised -highlightthickness 1 -highlightbackground $::fg_bar
    pack $w.tab_profile.flinenums.lbl -side left
    pack $w.tab_profile.flinenums.check -side left -padx {8 2}

    # Block cursor row
    frame $w.tab_profile.fblockcur -bg $::bg
    pack $w.tab_profile.fblockcur -fill x -padx 12 -pady 4
    label $w.tab_profile.fblockcur.lbl -text [t profile_config_block_cursor] -font $::font_sm -width 20 -anchor w -bg $::bg -fg $::fg
    checkbutton $w.tab_profile.fblockcur.check -variable profile_config_block_cursor -font $::font_sm -bg $::bg -fg $::fg \
        -selectcolor $::bg_sel -activebackground $::bg -activeforeground $::fg \
        -borderwidth 1 -relief raised -highlightthickness 1 -highlightbackground $::fg_bar
    pack $w.tab_profile.fblockcur.lbl -side left
    pack $w.tab_profile.fblockcur.check -side left -padx {8 2}

    # Blink cursor row
    frame $w.tab_profile.fblinkcur -bg $::bg
    pack $w.tab_profile.fblinkcur -fill x -padx 12 -pady 4
    label $w.tab_profile.fblinkcur.lbl -text [t profile_config_blink_cursor] -font $::font_sm -width 20 -anchor w -bg $::bg -fg $::fg
    checkbutton $w.tab_profile.fblinkcur.check -variable profile_config_blink_cursor -font $::font_sm -bg $::bg -fg $::fg \
        -selectcolor $::bg_sel -activebackground $::bg -activeforeground $::fg \
        -borderwidth 1 -relief raised -highlightthickness 1 -highlightbackground $::fg_bar
    pack $w.tab_profile.fblinkcur.lbl -side left
    pack $w.tab_profile.fblinkcur.check -side left -padx {8 2}

    # --- Fonts tab content ---
    frame $w.tab_fonts.profile -relief ridge -borderwidth 2 -bg $::bg
    pack $w.tab_fonts.profile -fill x -padx 0 -pady 8

    label $w.tab_fonts.profile.title -text "Profile Settings" -font $::font_sm -fg $::fg_bar -bg $::bg
    pack $w.tab_fonts.profile.title -anchor w -padx 8 -pady {4 2}

    frame $w.tab_fonts.profile.fprof -bg $::bg
    pack $w.tab_fonts.profile.fprof -fill x -padx 12 -pady {0 6}
    label $w.tab_fonts.profile.fprof.lbl -text [t profile_config_edit_profile] -font $::font_sm -width 20 -anchor w -bg $::bg -fg $::fg
    tk_optionMenu $w.tab_fonts.profile.fprof.om ::profile_config_profile {*}$profiles
    $w.tab_fonts.profile.fprof.om configure -bg $::bg_bar -fg $::fg_bar -activebackground $::bg_sel -activeforeground $::fg -borderwidth 1 -highlightthickness 0
    pack $w.tab_fonts.profile.fprof.lbl -side left -padx {0 8}
    pack $w.tab_fonts.profile.fprof.om -side left -fill x -expand 1 -padx {8 0}

    frame $w.tab_fonts.ffont -bg $::bg
    pack $w.tab_fonts.ffont -fill x -padx 12 -pady 4
    label $w.tab_fonts.ffont.lbl -text [t profile_config_font] -font $::font_sm -width 20 -anchor w -bg $::bg -fg $::fg
    entry $w.tab_fonts.ffont.entry -width 30 -font $::font_sm -bg $::bg_bar -fg $::fg
    pack $w.tab_fonts.ffont.lbl -side left
    pack $w.tab_fonts.ffont.entry -side left -fill x -expand 1 -padx {8 0}

    label $w.tab_fonts.lbl_fonts -text "Available fonts:" -font $::font_sm -bg $::bg -fg $::fg
    pack $w.tab_fonts.lbl_fonts -anchor w -padx 12 -pady {4 2}
    frame $w.tab_fonts.fonts_frame -bg $::bg
    pack $w.tab_fonts.fonts_frame -fill both -expand 1 -padx 12 -pady 2
    listbox $w.tab_fonts.fonts -height 6 -width 40 -font $::font_sm -selectmode single \
        -yscrollcommand [list $w.tab_fonts.fonts_scroll set] -bg $::bg_bar -fg $::fg
    scrollbar $w.tab_fonts.fonts_scroll -command [list $w.tab_fonts.fonts yview] -bg $::bg_bar
    foreach f [lsort [font families]] {
        $w.tab_fonts.fonts insert end $f
    }
    pack $w.tab_fonts.fonts -side left -fill both -expand 1 -in $w.tab_fonts.fonts_frame
    pack $w.tab_fonts.fonts_scroll -side left -fill y -in $w.tab_fonts.fonts_frame

    label $w.tab_fonts.preview -text "Preview" -font $::font_sm -bg $::bg -fg $::fg
    pack $w.tab_fonts.preview -fill x -padx 12 -pady {8 2}

    frame $w.tab_fonts.fsize -bg $::bg
    pack $w.tab_fonts.fsize -fill x -padx 12 -pady 4
    label $w.tab_fonts.fsize.lbl -text [t profile_config_size] -font $::font_sm -width 20 -anchor w -bg $::bg -fg $::fg
    spinbox $w.tab_fonts.fsize.spin -from 6 -to 72 -width 5 -font $::font_sm -bg $::bg_bar -fg $::fg -command {
        set font [.profile_config.tab_fonts.ffont.entry get]
        set size [.profile_config.tab_fonts.fsize.spin get]
        if {$font ne "" && $size ne ""} {
            catch {.profile_config.tab_fonts.preview configure -font [list $font $size] -text "Sample Text - $font"}
        }
    }
    pack $w.tab_fonts.fsize.lbl -side left
    pack $w.tab_fonts.fsize.spin -side left -padx {8 0}

    bind $w.tab_fonts.fonts <<ListboxSelect>> {
        set sel [%W curselection]
        if {[llength $sel] > 0} {
            set font_var [%W get [lindex $sel 0]]
            .profile_config.tab_fonts.ffont.entry delete 0 end
            .profile_config.tab_fonts.ffont.entry insert 0 $font_var
            set size [.profile_config.tab_fonts.fsize.spin get]
            if {$size ne ""} {
                .profile_config.tab_fonts.preview configure -font [list $font_var $size] -text "Sample Text - $font_var"
            }
        }
    }

    bind $w.tab_fonts.ffont.entry <KeyRelease> {
        set font [.profile_config.tab_fonts.ffont.entry get]
        set size [.profile_config.tab_fonts.fsize.spin get]
        if {$font ne "" && $size ne ""} {
            catch {.profile_config.tab_fonts.preview configure -font [list $font $size] -text "Sample Text - $font"}
        }
    }

    bind $w.tab_fonts.fsize.spin <KeyRelease> {
        set font [.profile_config.tab_fonts.ffont.entry get]
        set size [.profile_config.tab_fonts.fsize.spin get]
        if {$font ne "" && $size ne ""} {
            catch {.profile_config.tab_fonts.preview configure -font [list $font $size] -text "Sample Text - $font"}
        }
    }

    # --- Timer tab content ---
    frame $w.tab_timer.timer_sec -relief ridge -borderwidth 2 -bg $::bg
    pack $w.tab_timer.timer_sec -fill x -padx 0 -pady 8
    label $w.tab_timer.timer_sec.title -text [t timer_section] -font $::font_sm -fg $::fg_bar -bg $::bg
    pack $w.tab_timer.timer_sec.title -anchor w -padx 8 -pady {4 2}

    frame $w.tab_timer.timer_sec.type -bg $::bg
    pack $w.tab_timer.timer_sec.type -fill x -padx 12 -pady 4
    label $w.tab_timer.timer_sec.type.lbl -text [t timer_type] -font $::font_sm -width 20 -anchor w -bg $::bg -fg $::fg
    set timer_types [list [t timer_type_countdown] [t timer_type_stopwatch]]
    tk_optionMenu $w.tab_timer.timer_sec.type.om ::profile_config_timer_type {*}$timer_types
    $w.tab_timer.timer_sec.type.om configure -bg $::bg_bar -fg $::fg_bar -activebackground $::bg_sel -activeforeground $::fg -borderwidth 1 -highlightthickness 0
    pack $w.tab_timer.timer_sec.type.lbl -side left
    pack $w.tab_timer.timer_sec.type.om -side left -fill x -expand 1 -padx {8 0}

    frame $w.tab_timer.timer_sec.duration -bg $::bg
    pack $w.tab_timer.timer_sec.duration -fill x -padx 12 -pady 4
    label $w.tab_timer.timer_sec.duration.lbl -text [t timer_duration] -font $::font_sm -width 20 -anchor w -bg $::bg -fg $::fg
    spinbox $w.tab_timer.timer_sec.duration.spin -from 1 -to 120 -width 5 -font $::font_sm -bg $::bg_bar -fg $::fg
    label $w.tab_timer.timer_sec.duration.display -text "0'00\"" -font $::font_sm -bg $::bg_bar -fg $::fg -width 5 -anchor e
    pack $w.tab_timer.timer_sec.duration.lbl -side left
    pack $w.tab_timer.timer_sec.duration.spin -side left -padx {8 0}
    pack $w.tab_timer.timer_sec.duration.display -side left -padx {8 0}

    trace add variable ::profile_config_timer_type write [list apply {{name1 name2 op} {
        if {$::profile_config_timer_type eq "stopwatch"} {
            pack forget .profile_config.tab_timer.timer_sec.duration.spin
            pack .profile_config.tab_timer.timer_sec.duration.display -side left -padx {8 0}
        } else {
            pack forget .profile_config.tab_timer.timer_sec.duration.display
            pack .profile_config.tab_timer.timer_sec.duration.spin -side left -padx {8 0}
        }
    }}]

    frame $w.tab_timer.timer_sec.sound -bg $::bg
    pack $w.tab_timer.timer_sec.sound -fill x -padx 12 -pady 4
    label $w.tab_timer.timer_sec.sound.lbl -text [t timer_sound] -font $::font_sm -width 20 -anchor w -bg $::bg -fg $::fg
    checkbutton $w.tab_timer.timer_sec.sound.check -variable profile_config_timer_sound -font $::font_sm -bg $::bg -fg $::fg \
        -selectcolor $::bg_sel -activebackground $::bg -activeforeground $::fg \
        -borderwidth 1 -relief raised -highlightthickness 1 -highlightbackground $::fg_bar
    pack $w.tab_timer.timer_sec.sound.lbl -side left
    pack $w.tab_timer.timer_sec.sound.check -side left -padx {8 2}

    frame $w.tab_timer.timer_sec.alert -bg $::bg
    pack $w.tab_timer.timer_sec.alert -fill x -padx 12 -pady 4
    label $w.tab_timer.timer_sec.alert.lbl -text [t timer_alert] -font $::font_sm -width 20 -anchor w -bg $::bg -fg $::fg
    checkbutton $w.tab_timer.timer_sec.alert.check -variable profile_config_timer_alert -font $::font_sm -bg $::bg -fg $::fg \
        -selectcolor $::bg_sel -activebackground $::bg -activeforeground $::fg \
        -borderwidth 1 -relief raised -highlightthickness 1 -highlightbackground $::fg_bar
    pack $w.tab_timer.timer_sec.alert.lbl -side left
    pack $w.tab_timer.timer_sec.alert.check -side left -padx {8 2}

    frame $w.tab_timer.timer_sec.show -bg $::bg
    pack $w.tab_timer.timer_sec.show -fill x -padx 12 -pady 4
    label $w.tab_timer.timer_sec.show.lbl -text [t chrono_show] -font $::font_sm -width 20 -anchor w -bg $::bg -fg $::fg
    checkbutton $w.tab_timer.timer_sec.show.check -variable profile_config_chrono_show -font $::font_sm -bg $::bg -fg $::fg \
        -selectcolor $::bg_sel -activebackground $::bg -activeforeground $::fg \
        -borderwidth 1 -relief raised -highlightthickness 1 -highlightbackground $::fg_bar
    pack $w.tab_timer.timer_sec.show.lbl -side left
    pack $w.tab_timer.timer_sec.show.check -side left -padx {8 2}

    # --- Misc tab content ---
    frame $w.tab_misc.autosave_sec -relief ridge -borderwidth 2 -bg $::bg
    pack $w.tab_misc.autosave_sec -fill x -padx 0 -pady 8
    label $w.tab_misc.autosave_sec.title -text [t autosave_section] -font $::font_sm -fg $::fg_bar -bg $::bg
    pack $w.tab_misc.autosave_sec.title -anchor w -padx 8 -pady {4 2}

    frame $w.tab_misc.autosave_sec.enabled -bg $::bg
    pack $w.tab_misc.autosave_sec.enabled -fill x -padx 12 -pady 4
    label $w.tab_misc.autosave_sec.enabled.lbl -text [t autosave_enabled] -font $::font_sm -width 20 -anchor w -bg $::bg -fg $::fg
    checkbutton $w.tab_misc.autosave_sec.enabled.check -variable profile_config_autosave_enabled -font $::font_sm -bg $::bg -fg $::fg \
        -selectcolor $::bg_sel -activebackground $::bg -activeforeground $::fg \
        -borderwidth 1 -relief raised -highlightthickness 1 -highlightbackground $::fg_bar
    pack $w.tab_misc.autosave_sec.enabled.lbl -side left
    pack $w.tab_misc.autosave_sec.enabled.check -side left -padx {8 2}

    frame $w.tab_misc.autosave_sec.interval -bg $::bg
    pack $w.tab_misc.autosave_sec.interval -fill x -padx 12 -pady 4
    label $w.tab_misc.autosave_sec.interval.lbl -text [t autosave_interval] -font $::font_sm -width 20 -anchor w -bg $::bg -fg $::fg
    spinbox $w.tab_misc.autosave_sec.interval.spin -from 1 -to 60 -width 5 -font $::font_sm -bg $::bg_bar -fg $::fg
    pack $w.tab_misc.autosave_sec.interval.lbl -side left
    pack $w.tab_misc.autosave_sec.interval.spin -side left -padx {8 0}

    set ::profile_config_autosave_enabled $::cfg_autosave_enabled
    $w.tab_misc.autosave_sec.interval.spin set $::cfg_autosave_interval

    # --- Behaviour section ---
    frame $w.tab_misc.behaviour_sec -relief ridge -borderwidth 2 -bg $::bg
    pack $w.tab_misc.behaviour_sec -fill x -padx 0 -pady 8
    label $w.tab_misc.behaviour_sec.title -text [t config_behaviour_section] -font $::font_sm -fg $::fg_bar -bg $::bg
    pack $w.tab_misc.behaviour_sec.title -anchor w -padx 8 -pady {4 2}

    # docs_dir row (entry + browse button)
    frame $w.tab_misc.behaviour_sec.fdocs -bg $::bg
    pack  $w.tab_misc.behaviour_sec.fdocs -fill x -padx 12 -pady 4
    label $w.tab_misc.behaviour_sec.fdocs.lbl -text [t config_docs_dir] -font $::font_sm -width 30 -anchor w -bg $::bg -fg $::fg
    entry $w.tab_misc.behaviour_sec.fdocs.entry -width 32 -font $::font_sm -bg $::bg_bar -fg $::fg \
        -insertbackground $::fg -selectbackground $::bg_sel -selectforeground $::fg
    button $w.tab_misc.behaviour_sec.fdocs.btn -text [t config_browse] -font $::font_sm \
        -bg $::bg_bar -fg $::fg_bar -padx 4 \
        -command {
            set d [tk_chooseDirectory -initialdir [expr {$::cfg_docs_dir ne "" \
                ? [tilde-expand $::cfg_docs_dir] : $::DOCS_DIR_DEFAULT}] \
                -title "Documents folder" -parent .profile_config]
            if {$d ne ""} {
                .profile_config.tab_misc.behaviour_sec.fdocs.entry delete 0 end
                .profile_config.tab_misc.behaviour_sec.fdocs.entry insert 0 \
                    [string map [list $::HOME_DIR ~] $d]
            }
        }
    pack $w.tab_misc.behaviour_sec.fdocs.lbl -side left
    pack $w.tab_misc.behaviour_sec.fdocs.entry -side left -fill x -expand 1 -padx {4 4}
    pack $w.tab_misc.behaviour_sec.fdocs.btn  -side left

    # Boolean behaviour options
    foreach {fname key var} {
        fbrowser  config_browser_startup      profile_config_browser
        fwatch    config_watch_file           profile_config_watch_file
        fhemingway config_hemingway_mode      profile_config_hemingway
        fshrink   config_split_shrink_margin  profile_config_split_shrink
        fcrestore config_cursor_restore       profile_config_cursor_restore
    } {
        frame $w.tab_misc.behaviour_sec.$fname -bg $::bg
        pack  $w.tab_misc.behaviour_sec.$fname -fill x -padx 12 -pady 3
        label $w.tab_misc.behaviour_sec.$fname.lbl -text [t $key] -font $::font_sm -width 30 -anchor w -bg $::bg -fg $::fg
        checkbutton $w.tab_misc.behaviour_sec.$fname.check -variable $var \
            -font $::font_sm -bg $::bg -fg $::fg \
            -selectcolor $::bg_sel -activebackground $::bg -activeforeground $::fg \
            -borderwidth 1 -relief raised -highlightthickness 1 -highlightbackground $::fg_bar
        pack $w.tab_misc.behaviour_sec.$fname.lbl -side left
        pack $w.tab_misc.behaviour_sec.$fname.check -side left -padx {8 2}
    }

    # Load behaviour values
    $w.tab_misc.behaviour_sec.fdocs.entry insert 0 $::cfg_docs_dir
    set ::profile_config_browser      $::cfg_browser
    set ::profile_config_watch_file   $::cfg_watch_file
    set ::profile_config_hemingway    $::cfg_hemingway_mode
    set ::profile_config_split_shrink $::cfg_split_shrink_margin
    set ::profile_config_cursor_restore $::cfg_cursor_restore

    # --- Display tab content ---
    frame $w.tab_display.statusbar_sec -relief ridge -borderwidth 2 -bg $::bg
    pack $w.tab_display.statusbar_sec -fill x -padx 0 -pady 8
    label $w.tab_display.statusbar_sec.title -text [t config_statusbar_section] -font $::font_sm -fg $::fg_bar -bg $::bg
    pack $w.tab_display.statusbar_sec.title -anchor w -padx 8 -pady {4 2}

    foreach {zone key} {left config_statusbar_left center config_statusbar_center right config_statusbar_right} {
        frame $w.tab_display.statusbar_sec.f$zone -bg $::bg
        pack $w.tab_display.statusbar_sec.f$zone -fill x -padx 12 -pady 3
        label $w.tab_display.statusbar_sec.f$zone.lbl -text [t $key] -font $::font_sm -width 10 -anchor w -bg $::bg -fg $::fg
        entry $w.tab_display.statusbar_sec.f$zone.entry -width 40 -font $::font_sm -bg $::bg_bar -fg $::fg \
            -insertbackground $::fg -selectbackground $::bg_sel -selectforeground $::fg
        pack $w.tab_display.statusbar_sec.f$zone.lbl -side left
        pack $w.tab_display.statusbar_sec.f$zone.entry -side left -fill x -expand 1 -padx {4 0}
    }

    label $w.tab_display.statusbar_sec.tokens -text [t config_statusbar_tokens] \
        -font $::font_sm -fg $::fg_bar -bg $::bg -wraplength 480 -justify left
    pack $w.tab_display.statusbar_sec.tokens -anchor w -padx 12 -pady {6 4}

    frame $w.tab_display.editor_sec -relief ridge -borderwidth 2 -bg $::bg
    pack $w.tab_display.editor_sec -fill x -padx 0 -pady 8
    label $w.tab_display.editor_sec.title -text [t config_editor_section] -font $::font_sm -fg $::fg_bar -bg $::bg
    pack $w.tab_display.editor_sec.title -anchor w -padx 8 -pady {4 2}

    frame $w.tab_display.editor_sec.fhm -bg $::bg
    pack $w.tab_display.editor_sec.fhm -fill x -padx 12 -pady 4
    label $w.tab_display.editor_sec.fhm.lbl -text [t config_heading_marker] -font $::font_sm -width 20 -anchor w -bg $::bg -fg $::fg
    entry $w.tab_display.editor_sec.fhm.entry -width 6 -font $::font_sm -bg $::bg_bar -fg $::fg \
        -insertbackground $::fg -selectbackground $::bg_sel -selectforeground $::fg
    pack $w.tab_display.editor_sec.fhm.lbl -side left
    pack $w.tab_display.editor_sec.fhm.entry -side left -padx {4 0}

    # --- Markup section ---
    frame $w.tab_display.markup_sec -relief ridge -borderwidth 2 -bg $::bg
    pack $w.tab_display.markup_sec -fill x -padx 0 -pady 8
    label $w.tab_display.markup_sec.title -text [t config_markup_section] -font $::font_sm -fg $::fg_bar -bg $::bg
    pack $w.tab_display.markup_sec.title -anchor w -padx 8 -pady {4 2}

    foreach {fname key} {
        fcm  config_comment_marker
        fbm  config_bold_marker
        fim  config_italic_marker
        fum  config_underline_marker
        fsm  config_strikethrough_marker
    } {
        frame $w.tab_display.markup_sec.$fname -bg $::bg
        pack  $w.tab_display.markup_sec.$fname -fill x -padx 12 -pady 3
        label $w.tab_display.markup_sec.$fname.lbl -text [t $key] -font $::font_sm -width 22 -anchor w -bg $::bg -fg $::fg
        entry $w.tab_display.markup_sec.$fname.entry -width 6 -font $::font_sm -bg $::bg_bar -fg $::fg \
            -insertbackground $::fg -selectbackground $::bg_sel -selectforeground $::fg
        pack  $w.tab_display.markup_sec.$fname.lbl -side left
        pack  $w.tab_display.markup_sec.$fname.entry -side left -padx {4 0}
    }

    frame $w.tab_display.markup_sec.fmdh -bg $::bg
    pack  $w.tab_display.markup_sec.fmdh -fill x -padx 12 -pady 3
    label $w.tab_display.markup_sec.fmdh.lbl -text [t config_markdown_headings] -font $::font_sm -width 22 -anchor w -bg $::bg -fg $::fg
    checkbutton $w.tab_display.markup_sec.fmdh.check -variable profile_config_markdown_headings \
        -font $::font_sm -bg $::bg -fg $::fg \
        -selectcolor $::bg_sel -activebackground $::bg -activeforeground $::fg \
        -borderwidth 1 -relief raised -highlightthickness 1 -highlightbackground $::fg_bar
    pack $w.tab_display.markup_sec.fmdh.lbl -side left
    pack $w.tab_display.markup_sec.fmdh.check -side left -padx {8 2}

    # Load display values
    $w.tab_display.statusbar_sec.fleft.entry insert 0 $::cfg_status_left
    $w.tab_display.statusbar_sec.fcenter.entry insert 0 $::cfg_status_center
    $w.tab_display.statusbar_sec.fright.entry insert 0 $::cfg_status_right
    $w.tab_display.editor_sec.fhm.entry insert 0 $::cfg_heading_marker
    $w.tab_display.markup_sec.fcm.entry  insert 0 [marker-val $::cfg_comment_marker]
    $w.tab_display.markup_sec.fbm.entry  insert 0 [marker-val $::cfg_bold_marker]
    $w.tab_display.markup_sec.fim.entry  insert 0 [marker-val $::cfg_italic_marker]
    $w.tab_display.markup_sec.fum.entry  insert 0 [marker-val $::cfg_underline_marker]
    $w.tab_display.markup_sec.fsm.entry  insert 0 [marker-val $::cfg_strikethrough_marker]
    set ::profile_config_markdown_headings $::cfg_markdown_headings

    # Load timer values from config
    set ::profile_config_timer_sound $::cfg_timer_sound
    set ::profile_config_timer_alert $::cfg_timer_alert
    set ::profile_config_chrono_show $::cfg_chrono_show
    set ::profile_config_timer_type $::cfg_timer_type
    $w.tab_timer.timer_sec.duration.spin set $::cfg_timer_duration

    # Update profile display when changed via trace
    trace add variable ::profile_config_profile write [list apply {{name1 name2 op} {
        profile-config-update-profile .profile_config
    }}]

    # Load initial values
    profile-config-update-profile $w

    # Button frame — packed before tab content via -before so it stays visible at top
    frame $w.btns -bg $::bg
    pack $w.btns -before $w.tab_profile -fill x -padx 8 -pady {4 0}
    button $w.btns.apply -text [t profile_config_apply] -font $::font_sm \
        -bg $::bg_bar -fg $::fg_bar -width 12 \
        -command {
            set profile $::profile_config_profile
            set font [.profile_config.tab_fonts.ffont.entry get]
            set size [.profile_config.tab_fonts.fsize.spin get]
            set mw [.profile_config.tab_profile.fmarginw.spin get]
            set mh [.profile_config.tab_profile.fmarginh.spin get]
            set goal [.profile_config.tab_profile.fwordgoal.spin get]
            set dark $::profile_config_dark_mode
            set line_spacing [.profile_config.tab_profile.flinespace.spin get]
            set bar_height   [.profile_config.tab_profile.fbarheight.spin get]
            set line_numbers $::profile_config_line_numbers
            set block_cursor $::profile_config_block_cursor
            set blink_cursor $::profile_config_blink_cursor
            set def_prof $::profile_config_default_prof
            set def_scheme $::profile_config_default_scheme
            set def_lang $::profile_config_language
            set timer_dur [.profile_config.tab_timer.timer_sec.duration.spin get]
            set timer_snd $::profile_config_timer_sound
            set timer_alrt $::profile_config_timer_alert
            set timer_typ $::profile_config_timer_type
            set chrono_shw $::profile_config_chrono_show
            set autosave_en  $::profile_config_autosave_enabled
            set autosave_int [.profile_config.tab_misc.autosave_sec.interval.spin get]
            set docs_dir    [.profile_config.tab_misc.behaviour_sec.fdocs.entry get]
            set browser     $::profile_config_browser
            set watch_file  $::profile_config_watch_file
            set hemingway   $::profile_config_hemingway
            set split_shrink $::profile_config_split_shrink
            set cursor_restore $::profile_config_cursor_restore
            set status_l  [.profile_config.tab_display.statusbar_sec.fleft.entry get]
            set status_c  [.profile_config.tab_display.statusbar_sec.fcenter.entry get]
            set status_r  [.profile_config.tab_display.statusbar_sec.fright.entry get]
            set heading_m [.profile_config.tab_display.editor_sec.fhm.entry get]
            set comment_m [.profile_config.tab_display.markup_sec.fcm.entry get]
            set bold_m    [.profile_config.tab_display.markup_sec.fbm.entry get]
            set italic_m  [.profile_config.tab_display.markup_sec.fim.entry get]
            set under_m   [.profile_config.tab_display.markup_sec.fum.entry get]
            set strike_m  [.profile_config.tab_display.markup_sec.fsm.entry get]
            set md_heads  $::profile_config_markdown_headings

            if {$font eq "" || $size eq "" || $mw eq "" || $mh eq ""} return

            dict set ::cfg_profiles $profile font_family $font
            dict set ::cfg_profiles $profile font_size $size
            dict set ::cfg_profiles $profile margin_width $mw
            dict set ::cfg_profiles $profile margin_height $mh
            dict set ::cfg_profiles $profile word_goal $goal
            dict set ::cfg_profiles $profile dark_mode $dark
            dict set ::cfg_profiles $profile line_spacing $line_spacing
            dict set ::cfg_profiles $profile bar_height $bar_height
            dict set ::cfg_profiles $profile line_numbers $line_numbers
            dict set ::cfg_profiles $profile block_cursor_gui $block_cursor
            dict set ::cfg_profiles $profile blink_cursor $blink_cursor

            set is_current_profile [expr {$profile eq $::cfg_profile}]

            set ::cfg_profile $def_prof
            set ::cfg_scheme $def_scheme
            set ::cfg_lang $def_lang
            set ::cfg_timer_duration $timer_dur
            set ::cfg_timer_sound $timer_snd
            set ::cfg_timer_alert $timer_alrt
            set ::cfg_timer_type $timer_typ
            set ::cfg_chrono_show $chrono_shw
            set ::cfg_autosave_enabled  $autosave_en
            set ::cfg_autosave_interval $autosave_int
            set ::cfg_docs_dir          $docs_dir
            set ::cfg_browser           $browser
            set ::cfg_watch_file        $watch_file
            set ::cfg_hemingway_mode    $hemingway
            set ::cfg_split_shrink_margin $split_shrink
            set ::cfg_cursor_restore    $cursor_restore
            if {$heading_m ne ""} { set ::cfg_heading_marker $heading_m }
            set ::cfg_comment_marker        [marker-val $comment_m]
            set ::cfg_bold_marker           [marker-val $bold_m]
            set ::cfg_italic_marker         [marker-val $italic_m]
            set ::cfg_underline_marker      [marker-val $under_m]
            set ::cfg_strikethrough_marker  [marker-val $strike_m]
            set ::cfg_markdown_headings     $md_heads
            set ::cfg_status_left   $status_l
            set ::cfg_status_center $status_c
            set ::cfg_status_right  $status_r

            ini-save

            scheme-apply $def_scheme
            lassign [theme-colors] bg fg bg_bar fg_bar bg_sel _ _ _ bg2
            set ::bg $bg
            set ::fg $fg
            set ::bg_bar $bg_bar
            set ::fg_bar $fg_bar
            set ::bg2 $bg2
            set ::bg_sel $bg_sel

            if {$is_current_profile} {
                profile-apply $profile
                if {[info exists ::editor_open]} {
                    set f [list $::cfg_font_family $::cfg_font_size]
                    set ::font $f
                    catch {.ed.t configure -font $f}
                    foreach side {l r} {
                        catch {.ed.pw.${side}.t configure -font $f}
                    }
                    .ed.t tag configure heading -font [list $::cfg_font_family $::cfg_font_size bold]
                    apply-line-spacing
                }
            }

            apply-theme

            catch {trace remove variable ::profile_config_profile write}
            destroy .profile_config
            br-reload
        }
    pack $w.btns.apply -side left -padx 4
    button $w.btns.cancel -text [t profile_config_cancel] -font $::font_sm \
        -bg $::bg_bar -fg $::fg_bar -width 12 -command {
            catch {trace remove variable ::profile_config_profile write}
            destroy .profile_config
        }
    pack $w.btns.cancel -side left -padx 4

    update
    set geom [wm geometry $w]
    set width [string range $geom 0 [string first x $geom]-1]
    if {$width < 550} {set width 550}
    wm geometry $w ${width}x[expr {[winfo height $w] + 20}]
    grab $w
    bind $w <Escape> {
        catch {trace remove variable ::profile_config_profile write}
        destroy .profile_config
    }
    focus $w.tab_profile.profile.fprof.om
}

} ;# end if {!$::no_gui}
