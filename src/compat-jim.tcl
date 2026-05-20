# compat-jim.tcl — JimTcl 0.84+ compatibility shim
# Included only in writhdeck-jim.tcl builds (make jimtcl).
# Must be the first module loaded after boot-jim.tcl.
#
# Fixes five incompatibilities with standard Tcl 8.5+:
#   1. chan configure  → fconfigure wrapper (strips -encoding, unsupported in JimTcl)
#   2. string is true  → JimTcl has no "true" class; use switch-based truthy check
#   3. string is integer -strict → strip -strict flag (minor empty-string difference only)
#   4. file normalize on non-existent paths → JimTcl errors; fallback to manual normalization
#   5. min()/max() in expr {} → JimTcl has no math function support; override expr with
#      a scanner that transforms min(a,b)/max(a,b) to [_min ...]/[_max ...] proc calls

# --- 1. chan configure -------------------------------------------------------
proc chan {sub args} {
    switch -- $sub {
        configure {
            set ch [lindex $args 0]
            set opts {}
            set i 1
            while {$i < [llength $args]} {
                if {[lindex $args $i] eq "-encoding"} {
                    incr i 2
                } else {
                    lappend opts [lindex $args $i]
                    incr i
                }
            }
            if {[llength $opts]} { fconfigure $ch {*}$opts }
        }
        default { error "chan $sub: not implemented in JimTcl compat" }
    }
}

# --- 2+3. string is true / string is integer -strict ------------------------
rename string __str_jim

proc string {sub args} {
    if {$sub eq "is"} {
        set cls [lindex $args 0]
        if {$cls eq "true"} {
            switch -- [__str_jim tolower [lindex $args end]] {
                1 - yes - true - on  { return 1 }
                default              { return 0 }
            }
        }
        if {$cls eq "integer" && [lindex $args 1] eq "-strict"} {
            return [__str_jim is integer [lindex $args end]]
        }
    }
    __str_jim $sub {*}$args
}

# --- 4. file normalize on non-existent paths --------------------------------
rename file __file_jim

proc file {sub args} {
    if {$sub eq "normalize"} {
        if {[catch {__file_jim normalize [lindex $args 0]} r]} {
            set p [lindex $args 0]
            if {![__str_jim match /* $p]} {
                set p [__file_jim join [pwd] $p]
            }
            set out {}
            foreach seg [split $p /] {
                if {$seg eq ".."} {
                    set out [lrange $out 0 end-1]
                } elseif {$seg ne "." && $seg ne ""} {
                    lappend out $seg
                }
            }
            return "/[join $out /]"
        }
        return $r
    }
    __file_jim $sub {*}$args
}

# --- 5. min()/max() in expr {} ----------------------------------------------
# rename expr FIRST so all compat procs can call __expr_orig safely
rename expr __expr_orig

proc _min {a b} { __expr_orig {$a < $b ? $a : $b} }
proc _max {a b} { __expr_orig {$a > $b ? $a : $b} }

# Scanner: transforms min(a,b)/max(a,b) → [_min [__expr_orig {a}] [__expr_orig {b}]]
# Handles nesting and parenthesized sub-expressions.
# Uses __expr_orig internally to avoid triggering the overridden expr.
proc _transform_expr {e} {
    set e [string map [list "\\\n" " "] $e]
    set out ""
    set i 0
    set len [string length $e]
    while {[__expr_orig {$i < $len}]} {
        set mi [string first "min(" $e $i]
        set ma [string first "max(" $e $i]
        if {$mi < 0} { set mi $len }
        if {$ma < 0} { set ma $len }
        set pos [__expr_orig {$mi < $ma ? $mi : $ma}]
        if {[__expr_orig {$pos >= $len}]} {
            append out [string range $e $i end]
            break
        }
        # Guard: skip if preceded by a word character (e.g. "maximum(")
        if {$pos > 0 && [regexp {[A-Za-z0-9_]} [string index $e [__expr_orig {$pos - 1}]]]} {
            append out [string index $e $i]
            set i [__expr_orig {$i + 1}]
            continue
        }
        append out [string range $e $i [__expr_orig {$pos - 1}]]
        set fn [string range $e $pos [__expr_orig {$pos + 2}]]
        set j [__expr_orig {$pos + 4}]
        set depth 1
        while {[__expr_orig {$j < $len && $depth > 0}]} {
            set ch [string index $e $j]
            if {$ch eq "("} { set depth [__expr_orig {$depth + 1}] }
            if {$ch eq ")"} { set depth [__expr_orig {$depth - 1}] }
            if {[__expr_orig {$depth > 0}]} { set j [__expr_orig {$j + 1}] }
        }
        set args_str [string range $e [__expr_orig {$pos + 4}] [__expr_orig {$j - 1}]]
        set ci -1
        set d 0
        for {set k 0} {[__expr_orig {$k < [string length $args_str]}]} {set k [__expr_orig {$k + 1}]} {
            set ch [string index $args_str $k]
            if {$ch eq "("} { set d [__expr_orig {$d + 1}] }
            if {$ch eq ")"} { set d [__expr_orig {$d - 1}] }
            if {$ch eq "," && [__expr_orig {$d == 0}]} { set ci $k; break }
        }
        if {$ci < 0} {
            append out [string range $e $pos $j]
            set i [__expr_orig {$j + 1}]
            continue
        }
        set a [string trim [string range $args_str 0 [__expr_orig {$ci - 1}]]]
        set b [string trim [string range $args_str [__expr_orig {$ci + 1}] end]]
        set a [_transform_expr $a]
        set b [_transform_expr $b]
        append out "\[_${fn} \[__expr_orig {${a}}\] \[__expr_orig {${b}}\]\]"
        set i [__expr_orig {$j + 1}]
    }
    return $out
}

proc expr {args} {
    if {[llength $args] == 1} {
        set e [_transform_expr [lindex $args 0]]
        uplevel 1 [list __expr_orig $e]
    } else {
        uplevel 1 [list __expr_orig {*}$args]
    }
}
