# Run the Lab10 SoC against its strict golden-trace checker.
# Usage: vivado -mode batch -source scripts/run_lab10_soc.tcl -tclargs <soc.xpr> <run-dir>
if {[llength $argv] != 2} {
    error "usage: run_lab10_soc.tcl <soc.xpr> <run-dir>"
}

set project_file [file normalize [lindex $argv 0]]
set run_dir [file normalize [lindex $argv 1]]
set gcc_dir "D:/Verilog/2025.2/Vivado/tps/mingw/10.0.0/win64.o/nt/bin"
if {![file isfile $project_file] || ![file isdirectory $run_dir]} {
    error "SoC XPR or run directory is missing: $project_file $run_dir"
}

open_project $project_file
set simset [get_filesets sim_1]
puts "CASE=lab10_soc"
puts "PROJECT_XPR=$project_file"
puts "SIM_TOP=[get_property TOP $simset]"
set legacy_ip [get_ips clk_pll data_ram inst_ram]
if {[llength $legacy_ip] != 3} {
    error "expected private clk_pll/data_ram/inst_ram XCI copies; found [llength $legacy_ip]"
}
puts "IP_UPGRADE_BEGIN=[join $legacy_ip ,]"
report_ip_status
upgrade_ip $legacy_ip
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
    error "XSim did not create its Lab10 SoC log: $simulation_log"
}
set log_handle [open $simulation_log r]
set simulation_text [read $log_handle]
close $log_handle
if {![regexp {TRACE_OPEN_PASS path=} $simulation_text]} {
    error "golden trace did not open; see $simulation_log"
}
if {![regexp {TRACE_EXHAUSTION_PASS records=([0-9]+) valid=([0-9]+)} $simulation_text -> records valid]} {
    error "golden trace was not exhausted; see $simulation_log"
}
if {![regexp {COURSE_SOC_PASS} $simulation_text]} {
    error "Lab10 SoC did not report PASS; see $simulation_log"
}
if {[regexp {COURSE_SOC_FAIL|Fatal:|ERROR:} $simulation_text]} {
    error "Lab10 SoC log contains a failure marker: $simulation_log"
}

set simulation_log_copy [file join $run_dir simulate.log]
set result_path [file join $run_dir result.txt]
if {[file exists $simulation_log_copy] || [file exists $result_path]} {
    error "refusing to overwrite existing Lab10 SoC evidence in $run_dir"
}
file copy $simulation_log $simulation_log_copy
set result_handle [open $result_path w]
puts $result_handle "CASE_NAME=lab10_soc_golden_trace"
puts $result_handle "TRACE_RECORDS=$records"
puts $result_handle "TRACE_VALID_RECORDS=$valid"
puts $result_handle "STATUS=PASS"
puts $result_handle "SIMULATION_LOG=simulate.log"
close $result_handle

close_project
puts "LAB10_SOC_RUN_FINISHED"
