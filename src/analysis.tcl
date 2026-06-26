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
    button $w.btns.ok    -text "OK" -font $::font_sm -command [list destroy $w]
    pack $w.btns.ok    -side right -padx 8 -pady 6
    pack $w.btns.rep   -side right -padx 4 -pady 6
    pack $w.btns.occ   -side right -padx 4 -pady 6
    pack $w.btns.spell -side right -padx 4 -pady 6

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
        tui-bar [expr {$rows - 1}] "  UP/DOWN scroll  r:repetitions  w:words  o:spelling  q close" "" $cols
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
