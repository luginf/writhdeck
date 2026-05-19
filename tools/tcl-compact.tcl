#!/usr/bin/env tclsh
# Strip comments, blank lines, and leading whitespace from a generated Tcl file.
# Uses a character-level context scanner to avoid stripping inside "..." strings.

if {$argc != 2} {
    puts stderr "Usage: tclsh tcl-compact.tcl input.tcl output.tcl"
    exit 1
}

set in_path  [lindex $argv 0]
set out_path [lindex $argv 1]

# Scan one line and return the updated context stack.
# Stack elements: "dq" (inside "...") or "br" (inside {...}).
# Rules:
#   top=dq  : " closes string; { } are literal
#   top=br  : { pushes, } pops; " is literal (brace quoting suppresses substitution)
#   top={}  : " opens string, { pushes brace
# Backslash escapes the next character in all contexts.
proc scan_ctx {stack line} {
    set i 0
    set n [string length $line]
    while {$i < $n} {
        set ch [string index $line $i]
        set top [lindex $stack end]
        if {$ch eq "\\"} {
            incr i 2
            continue
        }
        if {$top eq "dq"} {
            if {$ch eq "\""} { set stack [lrange $stack 0 end-1] }
        } elseif {$top eq "br"} {
            if {$ch eq "\{"} { lappend stack br } \
            elseif {$ch eq "\}"} { set stack [lrange $stack 0 end-1] } \
            elseif {$ch eq "\""} { lappend stack dq }
        } else {
            if {$ch eq "\""} { lappend stack dq } elseif {$ch eq "\{"} { lappend stack br }
        }
        incr i
    }
    return $stack
}

set fh [open $in_path r]
chan configure $fh -encoding utf-8
set content [read $fh]
close $fh

set lines  [split $content \n]
set result {}
# ctx tracks the parse context across lines (empty = top-level code).
set ctx {}

foreach line $lines {
    set trimmed [string trim $line]
    set top     [lindex $ctx end]
    set in_dq   [expr {$top eq "dq"}]

    # Always keep shebang
    if {[string match "#!*" $line]} {
        lappend result $line
        set ctx [scan_ctx $ctx $line]
        continue
    }
    # Blank lines: preserve inside "..." (content), drop otherwise
    if {$trimmed eq ""} {
        if {$in_dq} { lappend result $line }
        # blank line doesn't change ctx
        continue
    }
    # Comment-only lines: drop, unless backslash-continuation or inside "..."
    if {$in_dq || ([regexp {^\s*#} $line] && [string match {*\\} $trimmed])} {
        lappend result $line
        set ctx [scan_ctx $ctx $line]
        continue
    }
    if {[regexp {^\s*#} $line]} {
        set ctx [scan_ctx $ctx $line]
        continue
    }
    # Code line (top-level or inside {...} block): strip leading whitespace
    lappend result $trimmed
    set ctx [scan_ctx $ctx $line]
}

set fh [open $out_path w]
chan configure $fh -encoding utf-8
puts -nonewline $fh [join $result \n]
close $fh

set in_size  [file size $in_path]
set out_size [file size $out_path]
set pct      [expr {int(round(100.0 * ($in_size - $out_size) / $in_size))}]
puts "  [file tail $in_path] -> [file tail $out_path]  ($in_size -> $out_size bytes, -$pct%)"
