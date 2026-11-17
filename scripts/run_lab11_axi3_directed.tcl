# Build the isolated AXI3 bus and IF-stage test without the course SoC IP.
# Usage: vivado -mode batch -source scripts/run_lab11_axi3_directed.tcl -tclargs <repo-root> <run-dir>
if {[llength $argv] != 2} {
    error "usage: run_lab11_axi3_directed.tcl <repo-root> <run-dir>"
}

set repo_root [file normalize [lindex $argv 0]]
set run_dir [file normalize [lindex $argv 1]]
set cpu_dir [file join $repo_root lab11 CPU_CDE_AXI mycpu_axi_verify rtl myCPU]
set bench_file [file join $repo_root lab11 CPU_CDE_AXI mycpu_axi_verify testbench tb_lab11_axi3_bus.sv]
set if_file [file join $cpu_dir IF_stage.v]
set bus_file [file join $cpu_dir axi3_cpu_bus.v]
set gcc_dir "D:/Verilog/2025.2/Vivado/tps/mingw/10.0.0/win64.o/nt/bin"

foreach required [list $if_file $bus_file $bench_file] {
    if {![file isfile $required]} {
        error "required Lab11 directed source is missing: $required"
    }
}
if {![file isdirectory $run_dir]} {
    error "run directory is missing: $run_dir"
}

set project_dir [file join $run_dir project]
set project_name "lab11_axi3_directed"
create_project -force $project_name $project_dir -part xc7a200tfbg676-2
set_property target_language Verilog [current_project]
add_files -norecurse [list $if_file $bus_file]
set_property include_dirs [list $cpu_dir] [get_filesets sources_1]
add_files -fileset sim_1 -norecurse $bench_file
set_property include_dirs [list $cpu_dir] [get_filesets sim_1]
set simset [get_filesets sim_1]
set_property top tb_lab11_axi3_bus $simset
set_property top_auto_set 0 $simset
update_compile_order -fileset sim_1
puts "CASE=lab11_axi3_directed"
puts "PROJECT_XPR=[get_property DIRECTORY [current_project]]/[get_property NAME [current_project]].xpr"
puts "SIM_TOP=[get_property TOP $simset]"
puts "SIM_FILES=[get_files -of_objects $simset]"

cd $run_dir
launch_simulation -mode behavioral -simset sim_1 -gcc_install_path $gcc_dir
close_sim

set project_name [get_property NAME [current_project]]
set simulation_log [file join $project_dir "${project_name}.sim" sim_1 behav xsim simulate.log]
if {![file isfile $simulation_log]} {
    error "XSim did not create the Lab11 directed simulation log: $simulation_log"
}
set log_handle [open $simulation_log r]
set simulation_text [read $log_handle]
close $log_handle
foreach marker {
    {LAB11_AXI3_HANDSHAKE_PASS reads=2 stores=2 AW_first=1 W_first=1}
    {LAB11_AXI3_RID_CHECK_PASS}
    {LAB11_AXI3_RRESP_CHECK_PASS}
    {LAB11_AXI3_RLAST_CHECK_PASS}
    {LAB11_AXI3_BID_CHECK_PASS}
    {LAB11_AXI3_BRESP_CHECK_PASS}
    {LAB11_AXI3_IF_REDIRECT_STALLED_AR_PASS}
    {LAB11_AXI3_IF_REDIRECT_ACCEPTED_AR_PASS}
    {LAB11_AXI3_BUS_PASS}
} {
    if {[string first $marker $simulation_text] < 0} {
        error "required Lab11 directed-test marker is missing: $marker"
    }
}
if {[regexp {Fatal:|LAB11_AXI3_ASSERT|LAB11_AXI3_WATCHDOG} $simulation_text]} {
    error "Lab11 directed simulation contains a fatal/assertion marker: $simulation_log"
}

set log_copy [file join $run_dir simulate.log]
set result_path [file join $run_dir result.txt]
if {[file exists $log_copy] || [file exists $result_path]} {
    error "refusing to overwrite existing Lab11 directed evidence in $run_dir"
}
file copy $simulation_log $log_copy
set result_handle [open $result_path w]
puts $result_handle "CASE_NAME=lab11_axi3_bus_directed"
puts $result_handle "READ_TRANSACTIONS=2"
puts $result_handle "WRITE_TRANSACTIONS=2"
puts $result_handle "AW_FIRST_CASES=1"
puts $result_handle "W_FIRST_CASES=1"
puts $result_handle "R_ID_RESP_LAST_CHECKS=PASS"
puts $result_handle "B_ID_RESP_CHECKS=PASS"
puts $result_handle "IF_REDIRECT_STALLED_AR=PASS"
puts $result_handle "IF_REDIRECT_ACCEPTED_AR=PASS"
puts $result_handle "STATUS=PASS"
puts $result_handle "SIMULATION_LOG=simulate.log"
close $result_handle

close_project
puts "LAB11_AXI3_DIRECTED_RUN_FINISHED"
