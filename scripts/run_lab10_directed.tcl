# Run the Lab10 request/response stage testbench from a generated, isolated XPR.
# Usage: vivado -mode batch -source scripts/run_lab10_directed.tcl -tclargs <unit.xpr> <run-dir>
if {[llength $argv] != 2} {
    puts stderr "usage: run_lab10_directed.tcl <unit.xpr> <run-dir>"
    exit 2
}

set project_file [file normalize [lindex $argv 0]]
set run_dir [file normalize [lindex $argv 1]]
set gcc_dir "D:/Verilog/2025.2/Vivado/tps/mingw/10.0.0/win64.o/nt/bin"
if {![file exists $project_file] || ![file isdirectory $run_dir]} {
    puts stderr "unit project or run directory is missing: $project_file $run_dir"
    exit 2
}

open_project $project_file
puts "CASE=lab10"
puts "PROJECT_XPR=$project_file"
set simset [get_filesets sim_1]
puts "SIM_TOP=[get_property TOP $simset]"
puts "SIM_FILES=[get_files -of_objects $simset]"
cd $run_dir
launch_simulation -mode behavioral -simset sim_1 \
                  -gcc_install_path $gcc_dir
close_sim

set project_dir [file dirname $project_file]
set project_name [file rootname [file tail $project_file]]
set simulation_log [file join $project_dir "${project_name}.sim" sim_1 behav xsim simulate.log]
if {![file isfile $simulation_log]} {
    error "XSim did not create its directed simulation log: $simulation_log"
}
set log_handle [open $simulation_log r]
set simulation_text [read $log_handle]
close $log_handle
foreach marker {
    {LAB10_IF_PASS accepts=4 responses=4}
    {LAB10_MEM_PASS accepts=11 responses=11 stores=5 loads=6}
    {LAB10_BUS_PASS}
} {
    if {[string first $marker $simulation_text] < 0} {
        error "required directed-test marker is missing: $marker"
    }
}
if {[regexp {Fatal:|LAB10_[A-Z_]*FAIL} $simulation_text]} {
    error "directed test log contains a failure: $simulation_log"
}

set simulation_log_copy [file join $run_dir simulate.log]
if {[file exists $simulation_log_copy]} {
    error "refusing to overwrite directed simulation evidence: $simulation_log_copy"
}
file copy $simulation_log $simulation_log_copy
set result_path [file join $run_dir result.txt]
if {[file exists $result_path]} {
    error "refusing to overwrite directed result summary: $result_path"
}
set result_handle [open $result_path w]
puts $result_handle "CASE_NAME=lab10_bus_directed"
puts $result_handle "IF_ACCEPTS=4"
puts $result_handle "IF_RESPONSES=4"
puts $result_handle "DATA_ACCEPTS=11"
puts $result_handle "DATA_RESPONSES=11"
puts $result_handle "STORE_TRANSACTIONS=5"
puts $result_handle "LOAD_TRANSACTIONS=6"
puts $result_handle "STATUS=PASS"
puts $result_handle "SIMULATION_LOG=simulate.log"
close $result_handle

close_project
puts "LAB10_DIRECTED_RUN_FINISHED"
