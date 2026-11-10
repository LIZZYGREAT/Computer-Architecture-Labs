# Run a CPU-level directed test in a fresh Vivado project.
# Arguments: <lab-root> <new-run-directory> <testbench-top>

if {[llength $argv] != 3} {
    error "usage: run_cpu_directed_tb.tcl <lab-root> <new-run-directory> <testbench-top>"
}

set lab_root [file normalize [lindex $argv 0]]
set run_dir [file normalize [lindex $argv 1]]
set top_name [lindex $argv 2]
if {![regexp {^[A-Za-z_][A-Za-z0-9_]*$} $top_name]} {
    error "invalid testbench top name: $top_name"
}
set rtl_dir [file join $lab_root lab3 CPU_CDE mycpu_verify rtl myCPU]
set ip_dir [file join $lab_root lab3 CPU_CDE mycpu_verify rtl xilinx_ip]
set tb_file [file join $lab_root lab3 CPU_CDE mycpu_verify testbench "$top_name.v"]
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
        error "required CPU-directed test source is missing: $path"
    }
}
if {[file exists $project_dir]} {
    error "refusing to replace existing CPU-directed test project: $project_dir"
}

file mkdir $run_dir
create_project $top_name $project_dir -part xc7a200tfbg676-2
add_files -fileset sources_1 $rtl_sources
add_files -fileset sources_1 $ip_sources
set_property include_dirs [list $rtl_dir] [get_filesets sources_1]
add_files -fileset sim_1 $tb_file
set_property include_dirs [list $rtl_dir] [get_filesets sim_1]
set_property top $top_name [get_filesets sim_1]
set_property XSIM.SIMULATE.RUNTIME 100us [get_filesets sim_1]
set wave_tcl [file join $run_dir capture_cpu_directed_wave.tcl]
set wave_tcl_handle [open $wave_tcl w]
puts $wave_tcl_handle {log_wave -r /}
puts $wave_tcl_handle {run 100us}
close $wave_tcl_handle
set_property XSIM.SIMULATE.CUSTOM_TCL $wave_tcl [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation -simset sim_1 -mode behavioral

set simulation_log [file join $project_dir "$top_name.sim" sim_1 behav xsim simulate.log]
if {![file isfile $simulation_log]} {
    error "XSim did not create its CPU-directed simulation log: $simulation_log"
}
set log_handle [open $simulation_log r]
set simulation_text [read $log_handle]
close $log_handle
if {![regexp {CASE_NAME=[A-Za-z0-9_]+} $simulation_text] ||
    ![regexp {ASSERTIONS_PASS=[1-9][0-9]*} $simulation_text] ||
    ![regexp {TRAPS_OBSERVED=[0-9]+} $simulation_text] ||
    ![regexp {ERETS_OBSERVED=[0-9]+} $simulation_text] ||
    ![regexp {STATUS=PASS} $simulation_text] ||
    [regexp {FAIL|Fatal:|ERROR:} $simulation_text]} {
    error "CPU-directed test did not produce a clean PASS; see $simulation_log"
}

set simulation_log_out [file join $run_dir simulate.log]
if {[file exists $simulation_log_out]} {
    error "refusing to overwrite existing CPU-directed simulation log: $simulation_log_out"
}
file copy $simulation_log $simulation_log_out
set wave_db_candidates [glob -nocomplain [file join $project_dir "$top_name.sim" sim_1 behav xsim *.wdb]]
if {[llength $wave_db_candidates] == 0} {
    error "XSim did not create a CPU-directed WDB"
}
set wave_db_out [file join $run_dir "$top_name.wdb"]
if {[file exists $wave_db_out]} {
    error "refusing to overwrite existing CPU-directed WDB: $wave_db_out"
}
file copy [lindex $wave_db_candidates 0] $wave_db_out
if {[file size $wave_db_out] < 1024} {
    error "CPU-directed WDB is unexpectedly small: $wave_db_out"
}

close_sim
close_project
set result_path [file join $run_dir result.txt]
if {[file exists $result_path]} {
    error "refusing to overwrite existing CPU-directed result summary: $result_path"
}
set result_handle [open $result_path w]
foreach key {CASE_NAME ASSERTIONS_PASS TRAPS_OBSERVED ERETS_OBSERVED} {
    set pattern [format {%s=([^\r\n]+)} $key]
    if {![regexp -line $pattern $simulation_text -> value]} {
        close $result_handle
        error "required summary field $key is missing from $simulation_log"
    }
    puts $result_handle "$key=$value"
}
puts $result_handle "TESTBENCH_TOP=$top_name"
puts $result_handle "STATUS=PASS"
puts $result_handle "SIMULATION_LOG=simulate.log"
puts $result_handle "WAVEFORM_FILE=[file tail $wave_db_out]"
close $result_handle

# Keep the reviewed outputs and discard rebuildable Vivado/XSim project caches.
file delete -force $project_dir $wave_tcl
puts "CPU_DIRECTED_TB_RUN_COMPLETE=1"
puts "CPU_DIRECTED_TB_TOP=$top_name"
puts "CPU_DIRECTED_TB_WDB=$wave_db_out"
