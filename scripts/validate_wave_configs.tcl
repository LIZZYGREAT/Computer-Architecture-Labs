# Open each WCFG against its matching static WDB and fail on missing waves.
# Arguments: <wdb> <wcfg> [<wcfg> ...]

if {[llength $argv] < 2} {
    error "usage: validate_wave_configs.tcl <wdb> <wcfg> [<wcfg> ...]"
}

set wdb [file normalize [lindex $argv 0]]
if {![file isfile $wdb]} { error "waveform database is missing: $wdb" }
set expected_db [string map {\\ /} $wdb]
open_wave_database -noautoloadwcfg $wdb
if {[llength [get_scopes -r /]] == 0} {
    error "waveform database contains no HDL scopes: $wdb"
}

foreach wcfg [lrange $argv 1 end] {
    set wcfg [file normalize $wcfg]
    if {![file isfile $wcfg] || [file size $wcfg] == 0} {
        error "wave configuration is missing or empty: $wcfg"
    }
    set handle [open $wcfg r]
    set contents [read $handle]
    close $handle
    if {[string first $expected_db [string map {\\ /} $contents]] < 0} {
        error "WCFG does not reference the requested WDB: $wcfg"
    }
    if {![regexp {<WVObjectSize size="([0-9]+)"} $contents -> expected_wave_count]} {
        error "WCFG does not declare a wave count: $wcfg"
    }
    set wvobjects [regexp -all -inline {<wvobject fp_name="[^"]+" type="[^"]+"} $contents]
    if {[llength $wvobjects] != $expected_wave_count} {
        error "WCFG declares $expected_wave_count waves but contains [llength $wvobjects] HDL objects: $wcfg"
    }
    set missing_paths {}
    foreach wvobject $wvobjects {
        if {![regexp {fp_name="([^"]+)"} $wvobject -> hdl_path]} {
            error "could not read HDL path from WCFG object '$wvobject': $wcfg"
        }
        if {[llength [get_objects -r -quiet $hdl_path]] == 0} {
            lappend missing_paths $hdl_path
        }
    }
    if {[llength $missing_paths] > 0} {
        error "WCFG references HDL objects missing from the WDB: [join $missing_paths {, }] ($wcfg)"
    }
    if {[catch {open_wave_config $wcfg} message]} {
        error "Vivado could not open WCFG '$wcfg': $message"
    }
    set waves [get_waves *]
    if {[llength $waves] != $expected_wave_count} {
        error "loaded [llength $waves] waves, expected $expected_wave_count from $wcfg"
    }
    puts "WAVE_CONFIG_VALID=$wcfg"
    puts "WAVE_CONFIG_WDB=$wdb"
    puts "WAVE_CONFIG_WAVE_COUNT=[llength $waves]"
    puts "WAVE_CONFIG_SIGNAL_PATHS_RESOLVED=[llength $wvobjects]"
}

puts "WAVE_CONFIG_VALIDATION_COMPLETE=1"
