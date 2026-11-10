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
set wave_tcl_handle [open $wave_tcl w]
puts $wave_tcl_handle {log_wave -r /}
puts $wave_tcl_handle {run 100us}
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

set wave_db_candidates [glob -nocomplain [file join $project_dir interrupt_tb.sim sim_1 behav xsim *.wdb]]
if {[llength $wave_db_candidates] == 0} {
    error "XSim did not create an external-interrupt WDB"
}
set wave_db [lindex $wave_db_candidates 0]
set wave_db_out [file join $run_dir "interrupt-ip$ip_bit.wdb"]
if {[file exists $wave_db_out]} {
    error "refusing to overwrite existing interrupt WDB: $wave_db_out"
}
file copy $wave_db $wave_db_out
if {[file size $wave_db_out] < 1024} {
    error "external-interrupt WDB is unexpectedly small: $wave_db_out"
}

close_sim
close_project
puts "INTERRUPT_TB_RUN_COMPLETE=1"
puts "INTERRUPT_TB_IP_BIT=$ip_bit"
puts "INTERRUPT_TB_WDB=$wave_db_out"
