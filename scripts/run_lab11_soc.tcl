# Run the Lab11 AXI3 SoC and strictly validate the full golden trace.
# Usage: vivado -mode batch -source scripts/run_lab11_soc.tcl -tclargs <soc.xpr> <run-dir>
if {[llength $argv] < 2 || [llength $argv] > 6} {
    error "usage: run_lab11_soc.tcl <soc.xpr> <run-dir> ?max-ns? ?reference-trace? ?expected-points? ?capture-waveform(0|1)?"
}

set project_file [file normalize [lindex $argv 0]]
set run_dir [file normalize [lindex $argv 1]]
set max_ns 20000000
set trace_file ""
set expected_points 94
set capture_waveform 0
if {[llength $argv] >= 3} { set max_ns [lindex $argv 2] }
if {[llength $argv] >= 4 && [lindex $argv 3] ne ""} {
    set trace_file [file normalize [lindex $argv 3]]
}
if {[llength $argv] >= 5} { set expected_points [lindex $argv 4] }
if {[llength $argv] >= 6} { set capture_waveform [lindex $argv 5] }
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
if {![string is integer -strict $max_ns] || $max_ns <= 0} {
    error "max-ns must be a positive integer"
}
if {$capture_waveform ni {0 1}} { error "capture-waveform must be 0 or 1" }
set project_dir [file dirname $project_file]
set project_name [file rootname [file tail $project_file]]
set sim_dir [file join $project_dir "${project_name}.sim" sim_1 behav xsim]
set simulation_log [file join $sim_dir simulate.log]
set wdb_file [file join $sim_dir tb_top_behav.wdb]
if {$capture_waveform} {
    if {[file exists $wdb_file]} {
        error "refusing to overwrite existing waveform database: $wdb_file"
    }
    set capture_tcl [file join $run_dir xsim-capture.tcl]
    set capture_handle [open $capture_tcl w]
    puts $capture_handle {log_wave -r /}
    puts $capture_handle "run $max_ns ns"
    close $capture_handle
    set_property -name XSIM.SIMULATE.CUSTOM_TCL -value $capture_tcl -objects $simset
    puts "XSIM_WAVE_LOGGING=log_wave -r /"
}
set_property XSIM.SIMULATE.RUNTIME ${max_ns}ns $simset
if {$trace_file ne ""} {
    if {![file isfile $trace_file] || [file size $trace_file] == 0} {
        error "reference trace is missing or empty: $trace_file"
    }
    set_property -name XSIM.SIMULATE.XSIM.MORE_OPTIONS \
        -value [format {-testplusarg "TRACE_REF=%s"} $trace_file] -objects $simset
}
cd $run_dir
launch_simulation -mode behavioral -simset sim_1 -gcc_install_path $gcc_dir
catch {close_sim}

if {![file isfile $simulation_log]} {
    error "XSim did not create the Lab11 SoC simulation log: $simulation_log"
}
if {$capture_waveform && (![file isfile $wdb_file] || [file size $wdb_file] == 0)} {
    error "requested waveform database was not generated or is empty: $wdb_file"
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
if {![regexp {BUS_METRICS .*duplicate_store_count=([0-9]+).*protocol_assertions_failed=([0-9]+)} $simulation_text -> duplicate_stores protocol_failures]} {
    error "Lab11 bus transaction metrics are missing: $simulation_log"
}
if {$duplicate_stores != 0 || $protocol_failures != 0} {
    error "Lab11 bus protocol checks failed: duplicate_stores=$duplicate_stores protocol_failures=$protocol_failures"
}
if {![regexp {BUS_METRICS .*load_req_accept=([0-9]+).*load_data_complete=([0-9]+).*store_req_accept=([0-9]+).*store_data_complete=([0-9]+)} $simulation_text -> load_accept load_complete store_accept store_complete]} {
    error "Lab11 load/store completion metrics are missing: $simulation_log"
}
if {$load_accept != $load_complete || $store_accept != $store_complete} {
    error "Lab11 outstanding data transactions at test end: loads $load_accept/$load_complete, stores $store_accept/$store_complete"
}
if {[regexp {COURSE_SOC_FAIL|Fatal:|ERROR:|AXI3_FAULT|LAB11_AXI3} $simulation_text]} {
    error "Lab11 SoC log contains a failure or AXI protocol fault: $simulation_log"
}
if {![string is integer -strict $expected_points] || $expected_points <= 0} {
    error "expected-points must be a positive integer"
}
set point_pass_count [regexp -all {Functional Test Point PASS} $simulation_text]
if {$point_pass_count != $expected_points} {
    error "expected $expected_points functional-test points, observed $point_pass_count"
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
puts $result_handle "MAX_SIMULATION_NS=$max_ns"
if {$trace_file eq ""} { set trace_label DEFAULT } else { set trace_label $trace_file }
puts $result_handle "REFERENCE_TRACE=$trace_label"
puts $result_handle "STATUS=PASS"
puts $result_handle "SIMULATION_LOG=simulate.log"
puts $result_handle "WAVEFORM_STATUS=[expr {$capture_waveform ? {CAPTURED} : {NOT_CAPTURED}}]"
close $result_handle

close_project
puts "LAB11_SOC_RUN_FINISHED"
