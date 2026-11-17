# Read-only Vivado project/IP/source preflight for the Lab10/Lab11 projects.
if {[llength $argv] != 3} {
    puts stderr "usage: check_bus_project.tcl <case> <project.xpr> <output-dir>"
    exit 2
}

set case_name [lindex $argv 0]
set project_file [file normalize [lindex $argv 1]]
set output_dir [file normalize [lindex $argv 2]]
file mkdir $output_dir
set report_file [file join $output_dir "project-preflight.txt"]
set stream [open $report_file w]
puts $stream "CASE=$case_name"
puts $stream "PROJECT_XPR=$project_file"
puts $stream "VIVADO_VERSION=[version -short]"
puts $stream "OPEN_MODE=READ_ONLY"
flush $stream

if {![file exists $project_file]} {
    puts $stream "PROJECT_STATUS=MISSING"
    close $stream
    exit 2
}

if {[catch {open_project -read_only $project_file} open_error]} {
    puts $stream "PROJECT_STATUS=OPEN_FAILED"
    puts $stream "PROJECT_ERROR=$open_error"
    close $stream
    exit 2
}
puts $stream "PROJECT_STATUS=OPENED"

set design_set [get_filesets sources_1]
set sim_set [get_filesets sim_1]
puts $stream "DESIGN_TOP=[get_property TOP $design_set]"
puts $stream "SIM_TOP=[get_property TOP $sim_set]"
set expected_design_top [expr {$case_name eq "lab10" ? "soc_sram_lite_top" : "soc_axi_lite_top"}]
if {$case_name ni {lab10 lab11}} {
    puts $stream "CASE_STATUS=INVALID_CASE"
    close $stream
    close_project
    exit 2
}
if {[get_property TOP $design_set] ne $expected_design_top || [get_property TOP $sim_set] ne "tb_top"} {
    puts $stream "TOP_STATUS=FAIL"
    close $stream
    close_project
    exit 2
}

set cpu_files {}
set file_counts [dict create]
foreach source [get_files -of_objects $design_set] {
    set source_name [string trim [get_property NAME $source] "{}"]
    set source_type "unknown"
    set source_enabled "unknown"
    set source_synthesis "unknown"
    set source_simulation "unknown"
    catch {set source_type [get_property FILE_TYPE $source]}
    catch {set source_enabled [get_property IS_ENABLED $source]}
    catch {set source_synthesis [get_property USED_IN_SYNTHESIS $source]}
    catch {set source_simulation [get_property USED_IN_SIMULATION $source]}
    puts $stream "SOURCE_ENTRY=$source_name|TYPE=$source_type|ENABLED=$source_enabled|SYNTHESIS=$source_synthesis|SIMULATION=$source_simulation"
    if {![file exists $source_name]} {
        puts $stream "MISSING_SOURCE=$source_name"
    }
    set source_lower [string tolower [file normalize $source_name]]
    dict incr file_counts $source_lower
    if {[string match -nocase */rtl/mycpu/* $source_name]} {
        lappend cpu_files [file tail $source_name]
    }
}
puts $stream "CPU_FILES_IN_SOURCES_1=[llength $cpu_files]"
puts $stream "CPU_SOURCE_NAMES=[join [lsort -dictionary $cpu_files] {;}]"
foreach source_name [dict keys $file_counts] {
    if {[dict get $file_counts $source_name] != 1} {
        puts $stream "DUPLICATE_SOURCE=[dict get $file_counts $source_name]:$source_name"
    }
}

foreach fileset_name {sources_1 sim_1} {
    if {[catch {update_compile_order -fileset $fileset_name} update_error]} {
        puts $stream "COMPILE_ORDER_UPDATE_${fileset_name}=FAILED"
        puts $stream "COMPILE_ORDER_UPDATE_ERROR=${update_error}"
    } else {
        puts $stream "COMPILE_ORDER_UPDATE_${fileset_name}=OK"
    }
}

foreach {set_name file_set} [list sources_1 $design_set sim_1 $sim_set] {
    set manifest [open [file join $output_dir "${set_name}-files.txt"] w]
    foreach source [get_files -of_objects $file_set] {
        puts $manifest [get_property NAME $source]
    }
    close $manifest
}

if {[catch {report_ip_status -file [file join $output_dir "ip-status.rpt"]} ip_error]} {
    puts $stream "IP_STATUS=REPORT_FAILED"
    puts $stream "IP_ERROR=$ip_error"
} else {
    puts $stream "IP_STATUS=REPORTED"
}

if {[catch {report_compile_order -of_objects $sim_set -file [file join $output_dir "sim-compile-order.rpt"]} compile_error]} {
    puts $stream "COMPILE_ORDER_STATUS=REPORT_FAILED"
    puts $stream "COMPILE_ORDER_ERROR=$compile_error"
} else {
    puts $stream "COMPILE_ORDER_STATUS=REPORTED"
}

foreach fileset_name {sources_1 sim_1} {
    set fileset [get_filesets $fileset_name]
    foreach usage {simulation synthesis} {
        set compile_files {}
        catch {set compile_files [get_files -quiet -compile_order sources -used_in $usage -of_objects $fileset]}
        puts $stream "${usage}_COMPILE_ORDER_${fileset_name}_COUNT=[llength $compile_files]"
        set manifest [open [file join $output_dir "${fileset_name}-${usage}-compile-order.txt"] w]
        foreach source $compile_files {
            puts $manifest [string trim [get_property NAME $source] "{}"]
        }
        close $manifest
    }
}

close $stream
close_project
exit 0
