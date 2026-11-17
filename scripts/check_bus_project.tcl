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

if {[catch {report_compile_order -fileset sim_1 -file [file join $output_dir "sim-compile-order.rpt"]} compile_error]} {
    puts $stream "COMPILE_ORDER_STATUS=REPORT_FAILED"
    puts $stream "COMPILE_ORDER_ERROR=$compile_error"
} else {
    puts $stream "COMPILE_ORDER_STATUS=REPORTED"
}

close $stream
close_project
exit 0
