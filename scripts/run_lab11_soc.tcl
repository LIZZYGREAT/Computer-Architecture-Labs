# Run the Lab11 AXI3 SoC and strictly validate the full golden trace.
# Usage: vivado -mode batch -source scripts/run_lab11_soc.tcl -tclargs <soc.xpr> <run-dir>
if {[llength $argv] != 2} {
    error "usage: run_lab11_soc.tcl <soc.xpr> <run-dir>"
}

set project_file [file normalize [lindex $argv 0]]
set run_dir [file normalize [lindex $argv 1]]
set gcc_dir "D:/Verilog/2025.2/Vivado/tps/mingw/10.0.0/win64.o/nt/bin"
if {![file isfile $project_file] || ![file isdirectory $run_dir]} {
    error "Lab11 SoC XPR or run directory is missing: $project_file $run_dir"
}

open_project $project_file
set simset [get_filesets sim_1]
puts "CASE=lab11_soc"
puts "PROJECT_XPR=$project_file"
puts "SIM_TOP=[get_property TOP $simset]"
set private_ip [get_ips clk_pll axi_ram axi_crossbar_1x2 lab6_mult33 lab6_div32]
if {[llength $private_ip] != 5} {
    error "expected five run-private IP XCI copies; found [llength $private_ip]"
}
puts "IP_UPGRADE_BEGIN=[join $private_ip ,]"
report_ip_status
upgrade_ip $private_ip
report_ip_status
puts "IP_UPGRADE_END"
set_property XSIM.SIMULATE.RUNTIME 20ms $simset
cd $run_dir
launch_simulation -mode behavioral -simset sim_1 -gcc_install_path $gcc_dir
close_sim

set project_dir [file dirname $project_file]
set project_name [file rootname [file tail $project_file]]
set simulation_log [file join $project_dir "${project_name}.sim" sim_1 behav xsim simulate.log]
if {![file isfile $simulation_log]} {
    error "XSim did not create the Lab11 SoC simulation log: $simulation_log"
}
set log_handle [open $simulation_log r]
set simulation_text [read $log_handle]
close $log_handle
if {![regexp {TRACE_OPEN_PASS path=} $simulation_text]} {
    error "Lab11 golden trace did not open; see $simulation_log"
}
if {![regexp {TRACE_EXHAUSTION_PASS records=([0-9]+) valid=([0-9]+)} $simulation_text -> records valid]} {
    error "Lab11 golden trace was not exhausted; see $simulation_log"
}
if {![regexp {COURSE_SOC_PASS} $simulation_text]} {
    error "Lab11 SoC did not report PASS; see $simulation_log"
}
if {[regexp {COURSE_SOC_FAIL|Fatal:|ERROR:|AXI3_FAULT|LAB11_AXI3} $simulation_text]} {
    error "Lab11 SoC log contains a failure or AXI protocol fault: $simulation_log"
}
set point_pass_count [regexp -all {Functional Test Point PASS} $simulation_text]
if {$point_pass_count != 94} {
    error "expected 94 functional-test points, observed $point_pass_count"
}

set log_copy [file join $run_dir simulate.log]
set result_path [file join $run_dir result.txt]
if {[file exists $log_copy] || [file exists $result_path]} {
    error "refusing to overwrite existing Lab11 SoC evidence in $run_dir"
}
file copy $simulation_log $log_copy
set result_handle [open $result_path w]
puts $result_handle "CASE_NAME=lab11_soc_golden_trace"
puts $result_handle "TRACE_RECORDS=$records"
puts $result_handle "TRACE_VALID_RECORDS=$valid"
puts $result_handle "FUNCTIONAL_POINTS=$point_pass_count"
puts $result_handle "STATUS=PASS"
puts $result_handle "SIMULATION_LOG=simulate.log"
close $result_handle

close_project
puts "LAB11_SOC_RUN_FINISHED"
