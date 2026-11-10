# Run the external interrupt acceptance test in an isolated Vivado project.
# Arguments: <lab-root> <new-run-directory> ?hw-int-index-0-to-5?

if {[llength $argv] ni {2 3}} {
    error "usage: run_interrupt_tb.tcl <lab-root> <new-run-directory> ?hw-int-index-0-to-5?"
}

set lab_root [file normalize [lindex $argv 0]]
set run_dir [file normalize [lindex $argv 1]]
set irq_index 0
if {[llength $argv] == 3} { set irq_index [lindex $argv 2] }
if {![string is integer -strict $irq_index] || $irq_index < 0 || $irq_index > 5} {
    error "hardware interrupt input index must be an integer from 0 to 5: $irq_index"
}
set ip_bit [expr {$irq_index + 2}]
set rtl_dir [file join $lab_root lab3 CPU_CDE mycpu_verify rtl myCPU]
set ip_dir [file join $lab_root lab3 CPU_CDE mycpu_verify rtl xilinx_ip]
set tb_file [file join $lab_root lab3 CPU_CDE mycpu_verify testbench interrupt_tb.v]
set project_dir [file join $run_dir vivado_project]

set rtl_sources {}
foreach name {
    mycpu.h tools.v regfile.v alu.v IF_stage.v ID_stage.v EXE_stage.v
    MEM_stage.v WB_stage.v hilo_unit.v cp0_reg.v mycpu_top.v
} {
    lappend rtl_sources [file join $rtl_dir $name]
}
set ip_sources [list \
    [file join $ip_dir lab6_mult33 lab6_mult33.xci] \
    [file join $ip_dir lab6_div32 lab6_div32.xci]]

foreach path [concat $rtl_sources $ip_sources [list $tb_file]] {
    if {![file isfile $path]} {
        error "required interrupt test source is missing: $path"
    }
}
if {[file exists $project_dir]} {
    error "refusing to replace existing interrupt-test project: $project_dir"
}

file mkdir $run_dir
create_project interrupt_tb $project_dir -part xc7a200tfbg676-2
add_files -fileset sources_1 $rtl_sources
add_files -fileset sources_1 $ip_sources
set_property include_dirs [list $rtl_dir] [get_filesets sources_1]
add_files -fileset sim_1 $tb_file
set_property include_dirs [list $rtl_dir] [get_filesets sim_1]
set_property verilog_define [list IRQ_INDEX=$irq_index] [get_filesets sim_1]
set_property top interrupt_tb [get_filesets sim_1]
set_property XSIM.SIMULATE.RUNTIME 100us [get_filesets sim_1]
set wave_tcl [file join $run_dir capture_interrupt_wave.tcl]
set vcd_out [file join $run_dir "interrupt-ip$ip_bit-capture.vcd"]
set wave_tcl_handle [open $wave_tcl w]
puts $wave_tcl_handle {puts "CUSTOM_CAPTURE_BEGIN=1"}
puts $wave_tcl_handle [list open_vcd $vcd_out]
puts $wave_tcl_handle {puts "CUSTOM_CAPTURE_VCD_OPEN=1"}
foreach signal {
    /interrupt_tb/clk
    /interrupt_tb/resetn
    /interrupt_tb/hw_int
    /interrupt_tb/dut/cp0_reg/cause_ip
    /interrupt_tb/dut/cp0_reg/status_ie
    /interrupt_tb/dut/cp0_reg/status_im
    /interrupt_tb/dut/cp0_reg/status_exl
    /interrupt_tb/dut/cp0_reg/interrupt_pending
    /interrupt_tb/dut/exe_stage/es_pc
    /interrupt_tb/dut/exe_stage/es_valid
    /interrupt_tb/dut/mem_stage/ms_pc
    /interrupt_tb/dut/mem_stage/ms_exception_valid
    /interrupt_tb/dut/mem_stage/ms_exception_code
    /interrupt_tb/dut/trap_commit
    /interrupt_tb/dut/trap_code
    /interrupt_tb/dut/trap_pc
    /interrupt_tb/dut/cp0_epc
    /interrupt_tb/dut/eret_commit
    /interrupt_tb/dut/pipeline_flush
    /interrupt_tb/debug_wb_pc
    /interrupt_tb/debug_wb_rf_wen
    /interrupt_tb/data_sram_wen
} {
    puts $wave_tcl_handle [list log_vcd $signal]
}
puts $wave_tcl_handle {puts "CUSTOM_CAPTURE_LOG_WAVE_BEGIN=1"}
puts $wave_tcl_handle {if {[catch {log_wave -r /} message]} { puts "CUSTOM_CAPTURE_LOG_WAVE_ERROR=$message"; error $message }}
puts $wave_tcl_handle {puts "CUSTOM_CAPTURE_LOG_WAVE_DONE=1"}
puts $wave_tcl_handle {run 100us}
puts $wave_tcl_handle {close_vcd}
puts $wave_tcl_handle {puts "CUSTOM_CAPTURE_VCD_CLOSED=1"}
close $wave_tcl_handle
set_property XSIM.SIMULATE.CUSTOM_TCL $wave_tcl [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation -simset sim_1 -mode behavioral

set simulation_log [file join $project_dir interrupt_tb.sim sim_1 behav xsim simulate.log]
if {![file isfile $simulation_log]} {
    error "XSim did not create its interrupt simulation log: $simulation_log"
}
set log_handle [open $simulation_log r]
set simulation_text [read $log_handle]
close $log_handle
if {![regexp {INTERRUPT_TB_PASS} $simulation_text] ||
    [regexp {INTERRUPT_TB_FAIL|Fatal:} $simulation_text]} {
    error "external interrupt test did not produce a clean PASS; see $simulation_log"
}

set simulation_log_out [file join $run_dir simulate.log]
if {[file exists $simulation_log_out]} {
    error "refusing to overwrite existing interrupt simulation log: $simulation_log_out"
}
file copy $simulation_log $simulation_log_out

set xsim_output_dir [file join $project_dir interrupt_tb.sim sim_1 behav xsim]
proc describe_wdb_candidates {label candidates} {
    puts "${label}_CANDIDATE_COUNT=[llength $candidates]"
    foreach candidate $candidates {
        puts "${label}_CANDIDATE=[file normalize $candidate] BYTES=[file size $candidate] MTIME=[clock format [file mtime $candidate] -format {%Y-%m-%dT%H:%M:%S}]"
    }
}

set candidate_error 0
set wave_db_candidates [glob -nocomplain -types f [file join $xsim_output_dir *.wdb]]
describe_wdb_candidates WDB_BEFORE_CLOSE $wave_db_candidates
set wave_db ""
set before_close_out [file join $run_dir probe-before-close.wdb]
if {[llength $wave_db_candidates] == 1} {
    set wave_db [file normalize [lindex $wave_db_candidates 0]]
    if {[file exists $before_close_out]} {
        error "refusing to overwrite pre-close WDB probe: $before_close_out"
    }
    file copy $wave_db $before_close_out
    puts "WDB_BEFORE_CLOSE_PATH=$before_close_out"
    puts "WDB_BEFORE_CLOSE_BYTES=[file size $before_close_out]"
} else {
    set candidate_error 1
}
if {![file isfile $vcd_out] || [file size $vcd_out] < 1024} {
    error "XSim did not create a usable external-interrupt VCD: $vcd_out"
}

set close_sim_failed [catch {close_sim} close_sim_message]
puts "CLOSE_SIM_STATUS=[expr {$close_sim_failed ? {FAIL} : {PASS}}]"
if {$close_sim_failed} { puts "CLOSE_SIM_ERROR=$close_sim_message" }

set wave_db_candidates_after [glob -nocomplain -types f [file join $xsim_output_dir *.wdb]]
describe_wdb_candidates WDB_AFTER_CLOSE $wave_db_candidates_after
set after_close_out [file join $run_dir probe-after-close.wdb]
if {[llength $wave_db_candidates_after] == 1} {
    set wave_db_after [file normalize [lindex $wave_db_candidates_after 0]]
    if {[file exists $after_close_out]} {
        error "refusing to overwrite post-close WDB probe: $after_close_out"
    }
    file copy $wave_db_after $after_close_out
    puts "WDB_AFTER_CLOSE_PATH=$after_close_out"
    puts "WDB_AFTER_CLOSE_BYTES=[file size $after_close_out]"
} else {
    set candidate_error 1
}

set close_project_failed [catch {close_project} close_project_message]
puts "CLOSE_PROJECT_STATUS=[expr {$close_project_failed ? {FAIL} : {PASS}}]"
if {$close_project_failed} { puts "CLOSE_PROJECT_ERROR=$close_project_message" }
if {$close_sim_failed || $close_project_failed || $candidate_error} {
    error "diagnostic capture did not complete cleanly; inspect candidate and close statuses above"
}

puts "INTERRUPT_TB_RUN_COMPLETE=1"
puts "INTERRUPT_TB_IP_BIT=$ip_bit"
puts "INTERRUPT_TB_WDB_BEFORE_CLOSE=$before_close_out"
puts "INTERRUPT_TB_WDB_AFTER_CLOSE=$after_close_out"
puts "INTERRUPT_TB_VCD=$vcd_out"
