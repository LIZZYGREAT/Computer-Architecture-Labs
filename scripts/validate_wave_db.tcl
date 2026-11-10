# Open a static XSim WDB and verify it contains scopes and recorded HDL objects.
# Arguments: <wdb> [<wdb> ...]; run one database per Vivado invocation.

if {[llength $argv] != 1} {
    error "usage: validate_wave_db.tcl <wdb>"
}

set wdb [file normalize [lindex $argv 0]]
if {![file isfile $wdb] || [file size $wdb] == 0} {
    error "waveform database is missing or empty: $wdb"
}

open_wave_database -noautoloadwcfg $wdb
set scopes [get_scopes -r /]
if {[llength $scopes] == 0} {
    error "waveform database has no HDL scopes: $wdb"
}
set clock_objects [get_objects -r -quiet *clk*]
if {[llength $clock_objects] == 0} {
    error "waveform database has no recorded clock object: $wdb"
}

puts "WDB_VALID=$wdb"
puts "WDB_BYTES=[file size $wdb]"
puts "WDB_SCOPE_COUNT=[llength $scopes]"
puts "WDB_CLOCK_OBJECT_COUNT=[llength $clock_objects]"
