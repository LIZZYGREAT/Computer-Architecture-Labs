# Run the CP0 unit test in an isolated, generated Vivado project.
# Arguments: <lab-root> <new-run-directory>

if {[llength $argv] != 2} {
    error "usage: run_cp0_unit_tb.tcl <lab-root> <new-run-directory>"
}

set lab_root [file normalize [lindex $argv 0]]
set run_dir [file normalize [lindex $argv 1]]
set dut_file [file join $lab_root lab3 CPU_CDE mycpu_verify rtl myCPU cp0_reg.v]
set tb_file [file join $lab_root lab3 CPU_CDE mycpu_verify testbench cp0_unit_tb.v]
set project_dir [file join $run_dir vivado_project]

foreach path [list $dut_file $tb_file] {
    if {![file isfile $path]} {
        error "required CP0 unit-test source is missing: $path"
    }
}
if {[file exists $project_dir]} {
    error "refusing to replace existing CP0 unit-test project: $project_dir"
}

file mkdir $run_dir
create_project cp0_unit_tb $project_dir -part xc7a200tfbg676-2
add_files -fileset sources_1 $dut_file
add_files -fileset sim_1 $tb_file
set_property top cp0_unit_tb [get_filesets sim_1]
set_property XSIM.SIMULATE.RUNTIME 100us [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation -simset sim_1 -mode behavioral

set simulation_log [file join $project_dir cp0_unit_tb.sim sim_1 behav xsim simulate.log]
if {![file isfile $simulation_log]} {
    error "XSim did not create its simulation log: $simulation_log"
}
set log_handle [open $simulation_log r]
set simulation_text [read $log_handle]
close $log_handle
if {![regexp {CASE_NAME=cp0_reg_unit} $simulation_text] ||
    ![regexp {ASSERTIONS_PASS=([1-9][0-9]*)} $simulation_text] ||
    ![regexp {TRAPS_OBSERVED=2} $simulation_text] ||
    ![regexp {STATUS=PASS} $simulation_text] ||
    [regexp {CP0_TB_FAIL|Fatal:} $simulation_text]} {
    error "CP0 unit test did not produce a clean PASS; see $simulation_log"
}

close_sim
close_project
puts "CP0_UNIT_TB_RUN_COMPLETE=1"
