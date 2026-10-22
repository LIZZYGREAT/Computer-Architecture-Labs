# Run the standalone HI/LO and generated-IP simulation in a dedicated simset.

if {[llength $argv] != 2} {
    error "usage: run_hilo_unit_tb.tcl <dut-xpr> <lab-root>"
}

set xpr [file normalize [lindex $argv 0]]
set lab_root [file normalize [lindex $argv 1]]
open_project -quiet $xpr

set simset [get_filesets -quiet sim_hilo]
if {[llength $simset] == 0} {
    set simset [create_fileset -simset sim_hilo]
}
set tb_path [file join $lab_root lab3 CPU_CDE mycpu_verify testbench hilo_unit_tb.v]
if {[llength [get_files -quiet $tb_path]] == 0} {
    add_files -fileset $simset $tb_path
}
set_property top hilo_unit_tb $simset
update_compile_order -fileset $simset
set project_name [file rootname [file tail $xpr]]
set sim_dir [file normalize [file join [file dirname $xpr] "$project_name.sim" sim_hilo behav xsim]]
file mkdir $sim_dir
cd $sim_dir
launch_simulation -simset $simset -mode behavioral
run all
close_sim
close_project
puts "HILO_UNIT_TB_RUN_COMPLETE=1"
