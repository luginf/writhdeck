#!/usr/bin/env tclsh
# Unit tests for core shared procs (parsers, state persistence, status bar,
# browser file filter).
#
# Loads writhdeck-cli.tcl (TUI build, no Tk needed) up to but excluding the
# main-cli.tcl entry point, with HOME redirected to a temp sandbox so tests
# never touch the developer's real ~/Documents/writhdeck or state file.

set errors 0
set tests  0

proc check {label expr} {
    global errors tests
    incr tests
    if {[uplevel 1 [list expr $expr]]} {
        return 1
    }
    puts "FAIL: $label"
    puts "      expr: $expr"
    incr errors
    return 0
}

proc check-eq {label actual expected} {
    global errors tests
    incr tests
    if {$actual eq $expected} { return 1 }
    puts "FAIL: $label"
    puts "      expected: $expected"
    puts "      actual:   $actual"
    incr errors
    return 0
}

# --- sandbox HOME ---------------------------------------------------------------
set sandbox [file join [expr {[info exists ::env(TMPDIR)] ? $::env(TMPDIR) : "/tmp"}] \
    "writhdeck-test-units-[pid]"]
file mkdir $sandbox
set ::env(HOME) $sandbox
catch {unset ::env(COMP_LINE)}
catch {unset ::env(COMP_POINT)}
set ::argv {}
set ::argc 0

# --- load the CLI build without its entry point ----------------------------------
if {[catch {
    set fp [open writhdeck-cli.tcl r]
    set content [read $fp]
    close $fp
    set mi [string first "\n# main-cli.tcl\n" $content]
    if {$mi < 0} { error "section header '# main-cli.tcl' not found" }
    set cut [string last "\n# ===" $content $mi]
    if {$cut < 0} { set cut $mi }
    eval [string range $content 0 $cut]
} err]} {
    puts "ERROR: Failed to load writhdeck-cli.tcl: $err"
    file delete -force $sandbox
    exit 1
}

# ================================================================================
# Line parsers (parse-heading / heading-level / parse-comment / parse-list)
# Defaults: heading marker "=", comment marker "%", markdown_support on.
# ================================================================================
set ::cfg_heading_marker "="
set ::cfg_comment_marker "%"
set ::cfg_markdown_support 1
markers-update

check-eq "parse-heading marker line"        [parse-heading "= Title ="]      "Title"
check-eq "parse-heading nested markers"     [parse-heading "== Sub =="]      "= Sub ="
check-eq "parse-heading markdown"           [parse-heading "## Md heading"]  "Md heading"
check-eq "parse-heading plain line"         [parse-heading "just text"]      ""
check-eq "heading-level marker line"        [heading-level "== Sub =="]      {Sub 2}
check-eq "heading-level markdown"           [heading-level "### Three"]      {Three 3}
check-eq "heading-level plain line"         [heading-level "nope"]           ""
check    "parse-comment marker"             {[parse-comment "% a note"] == 1}
check    "parse-comment plain"              {[parse-comment "text % not comment"] == 0}
check    "parse-list dash"                  {[parse-list "- item"] == 1}
check    "parse-list indented dash"         {[parse-list "   - item"] == 1}
check    "parse-list star (markdown on)"    {[parse-list "* item"] == 1}
check    "parse-list dash no space"         {[parse-list "-item"] == 0}
check    "parse-list plain"                 {[parse-list "no list"] == 0}

# markdown_support off: md headings and "* " bullets no longer match
set ::cfg_markdown_support 0
markers-update
check-eq "parse-heading markdown (md off)"  [parse-heading "## Md heading"]  ""
check-eq "heading-level markdown (md off)"  [heading-level "### Three"]      ""
check    "parse-list star (md off)"         {[parse-list "* item"] == 0}
check    "parse-list dash (md off)"         {[parse-list "- item"] == 1}
set ::cfg_markdown_support 1
markers-update

# custom heading marker must be regexp-escaped
set ::cfg_heading_marker "**"
markers-update
check-eq "parse-heading custom ** marker"   [parse-heading "** Custom **"]   "Custom"
set ::cfg_heading_marker "="
markers-update

# ================================================================================
# State persistence round-trip (.writhdeck.json)
# ================================================================================
set ::cfg_cursor_restore 1
set today [clock format [clock seconds] -format "%Y-%m-%d"]

set doc1 [file join $sandbox "some dir" "with \"quote\".txt"]
set doc2 [file join $sandbox plain.txt]
file mkdir [file dirname $doc1]
close [open $doc1 w]
close [open $doc2 w]

set ::cursor_cache   {}
set ::favorites_list {}
set ::recent_list    {}
set ::daily_data     {}
set ::state_cache_valid 1

cursor-put $doc1 5 3
toggle-favorite $doc1
lappend ::recent_list [file normalize $doc2]
# doc1 is a favorite: daily-cleanup keeps all its dates (multi-date exercises
# the \t JSON escaping); doc2 keeps only today's entry
dict set ::daily_data [file normalize $doc1] [dict create 2026-01-01 100 $today 250]
dict set ::daily_data [file normalize $doc2] [dict create $today 42]
state-save

# force reload from disk
set ::state_cache_valid 0
state-load

check-eq "cursor round-trip"        [cursor-get $doc1] {5 3}
check-eq "cursor unknown file"      [cursor-get [file join $sandbox nope.txt]] {1 0}
check    "favorite round-trip"      {[file normalize $doc1] in $::favorites_list}
check    "recent round-trip"        {[file normalize $doc2] in $::recent_list}
check-eq "daily multi-date (favorite)" \
    [dict get $::daily_data [file normalize $doc1]] \
    [dict create 2026-01-01 100 $today 250]
check-eq "daily single date"        [dict get $::daily_data [file normalize $doc2] $today] 42

# the state file must be valid JSON as far as \t escaping goes: no literal tabs
set fh [open $::STATE_FILE r]; set raw [read $fh]; close $fh
check    "no literal tab in JSON"   {[string first "\t" $raw] < 0}

# toggle-favorite off removes the entry
toggle-favorite $doc1
check    "favorite toggled off"     {[file normalize $doc1] ni $::favorites_list}

# ================================================================================
# status-build
# ================================================================================
set state [dict create fn draft.txt dirty 1 sel 0 ln 12 total 40 col 7 \
    words 1500 chars 9000 clock 12:30 timer 240]

set ::ws_dual_mode 0
check-eq "status filename+dirty"    [status-build {filename dirty} $state] "draft.txt \[+\]"
check-eq "status literal token"     [status-build {filename | words} $state] "draft.txt|  1500w"
check-eq "status ln/col"            [status-build {ln col} $state] "  Ln 12/40  Col 7  "

set ::ws_dual_mode 1
set ::ws_n 2
check-eq "status workspace token"   [status-build {workspace filename} $state] "\[2\] draft.txt"
set ::ws_dual_mode 0

set ::cfg_chrono_show 1
set ::timer_active 1
check-eq "status timer active"      [status-build {timer} $state] " \[4'00\"\]"
set ::timer_active 0
check-eq "status timer inactive"    [status-build {timer} $state] "  4'00\""
set ::cfg_chrono_show 0

set state2 [dict replace $state dirty 0 readonly 1]
check-eq "status readonly flag"     [status-build {filename} $state2] "draft.txt \[[t ed_readonly]\]"

# ================================================================================
# list-docs browser filter
# ================================================================================
set ldir [file join $sandbox listdocs]
file mkdir $ldir
set now [clock seconds]
set i 0
foreach f {b.md a.txt notes.log .hidden.txt} {
    close [open [file join $ldir $f] w]
    # distinct decreasing mtimes -> deterministic newest-first order
    file mtime [file join $ldir $f] [expr {$now - [incr i]}]
}
file mkdir [file join $ldir subdir]

set ::cfg_browser_filter "*.txt *.t2t *.md *.ini"
set ::cfg_browser_show_all 0
check-eq "list-docs default filter" [list-docs $ldir] {b.md a.txt}
set ::cfg_browser_show_all 1
check-eq "list-docs show_all"       [list-docs $ldir] {b.md a.txt notes.log}
set ::cfg_browser_show_all 0
set ::cfg_browser_filter "*.log"
check-eq "list-docs custom filter"  [list-docs $ldir] {notes.log}
set ::cfg_browser_filter ""
check-eq "list-docs empty filter"   [list-docs $ldir] {b.md a.txt notes.log}
set ::cfg_browser_filter "*.txt *.t2t *.md *.ini"

# ================================================================================
# br-filter-match (incremental browser filter, "/" key)
# ================================================================================
set ::br_type_filter ""
check    "filter empty matches all"   {[br-filter-match "anything.txt"] == 1}
set ::br_type_filter "dra"
check    "filter substring match"     {[br-filter-match "draft.txt"] == 1}
check    "filter case-insensitive"    {[br-filter-match "DRAFT2.txt"] == 1}
check    "filter no match"            {[br-filter-match "notes.txt"] == 0}
set ::br_type_filter "*"
check    "filter no glob expansion"   {[br-filter-match "draft.txt"] == 0}
set ::br_type_filter ""

# ================================================================================
file delete -force $sandbox

if {$errors == 0} {
    puts "OK: $tests unit tests passed"
    exit 0
} else {
    puts "FAIL: $errors of $tests unit tests failed"
    exit 1
}
