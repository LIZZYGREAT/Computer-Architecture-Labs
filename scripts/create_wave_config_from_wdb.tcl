# Create a fresh WCFG bound to an existing static Vivado WDB.
# Arguments: <wdb> <output-wcfg> <scope-relative-path~radix> ...

if {[llength $argv] < 3} {
    error "usage: create_wave_config_from_wdb.tcl <wdb> <output-wcfg> <relative-signal~radix> ..."
}

set wdb [file normalize [lindex $argv 0]]
set wcfg [file normalize [lindex $argv 1]]
if {![file isfile $wdb]} {
    error "waveform database is missing: $wdb"
}
if {[file exists $wcfg]} {
    error "refusing to overwrite existing WCFG: $wcfg"
}

open_wave_database -noautoloadwcfg $wdb
set scopes [get_scopes -r /]
if {[llength $scopes] == 0} {
    error "waveform database contains no HDL scopes: $wdb"
}
set config_name [file rootname [file tail $wcfg]]
create_wave_config $config_name
set wave_count 0
set all_objects [get_objects -r -quiet *]

foreach spec [lrange $argv 2 end] {
    set fields [split $spec ~]
    if {[llength $fields] != 2} {
        error "invalid signal specification '$spec'; expected relative/path~radix"
    }
    lassign $fields relative_path radix
    if {$radix ni {bin hex dec unsigned}} {
        error "unsupported radix '$radix' in '$spec'"
    }
    # Match names as strings rather than Tcl glob patterns. Bus suffixes such
    # as [31:0] have special meaning to glob matching and must remain literal.
    # XSim's WDB object names omit packed-vector width selectors such as [31:0].
    regsub {\[[0-9]+:[0-9]+\]$} $relative_path {} relative_path
    set leaf_name [file tail $relative_path]
    set objects {}
    set suffix "/$relative_path"
    foreach candidate $all_objects {
        set candidate_length [string length $candidate]
        set suffix_length [string length $suffix]
        if {[string equal [file tail $candidate] $leaf_name] &&
            $candidate_length >= $suffix_length &&
            [string equal [string range $candidate [expr {$candidate_length - $suffix_length}] end] $suffix]} {
            lappend objects $candidate
        }
    }
    if {[llength $objects] != 1} {
        error "expected one HDL object ending in '$suffix', found [llength $objects]"
    }
    set added [add_wave -radix $radix [lindex $objects 0]]
    puts "WCFG_SIGNAL=[lindex $objects 0]"
    incr wave_count
}

save_wave_config $wcfg
if {![file isfile $wcfg] || [file size $wcfg] == 0} {
    error "Vivado did not write the requested WCFG: $wcfg"
}
puts "WDB=$wdb"
puts "WCFG=$wcfg"
puts "WCFG_WAVE_COUNT=$wave_count"
