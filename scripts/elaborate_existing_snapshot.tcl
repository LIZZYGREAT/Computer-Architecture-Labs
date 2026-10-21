# Elaborate an already compiled XSim snapshot without cleaning its work folder.
proc fail {message} {
    puts stderr "ENVIRONMENT_ERROR: $message"
    error $message
}

if {[llength $argv] < 3} {
    fail "usage: elaborate_existing_snapshot.tcl <project.xpr> <gcc-install-path> <overlay-data-dir>"
}

set xpr [file normalize [lindex $argv 0]]
set gcc_install_path [file normalize [lindex $argv 1]]
set overlay_data_dir [file normalize [lindex $argv 2]]
if {![file isfile $xpr]} {
    fail "Vivado project not found: $xpr"
}
if {![file isfile [file join $gcc_install_path gcc.exe]]} {
    fail "XSim GCC executable was not found: [file join $gcc_install_path gcc.exe]"
}
if {![file isfile [file join $overlay_data_dir xsim xsim.ini]] ||
    ![file isfile [file join $overlay_data_dir xsim include iki.h]]} {
    fail "XSim overlay data is incomplete: $overlay_data_dir"
}
if {[catch {open_project -quiet $xpr} message]} {
    fail "cannot open existing project: $message"
}

set sim_set [get_filesets -quiet sim_1]
if {$sim_set eq ""} {
    fail "sim_1 fileset is missing"
}
set_property TOP tb_top $sim_set
set_property -name XSIM.ELABORATE.XELAB.MORE_OPTIONS -value {-v 2} -objects $sim_set
set ::env(GCC_SIM_EXE_PATH) $gcc_install_path
set gcc_root [file dirname $gcc_install_path]
set gcc_exec_prefix [file join $gcc_root libexec gcc x86_64-w64-mingw32 9.5.0]
append gcc_exec_prefix /
set gcc_include_dirs [list [file join $gcc_root x86_64-w64-mingw32 include] \
                           [file join $gcc_root lib gcc x86_64-w64-mingw32 9.5.0 include] \
                           [file join $gcc_root include]]
set ::env(GCC_EXEC_PREFIX) $gcc_exec_prefix
set ::env(COMPILER_PATH) $gcc_exec_prefix
set ::env(CPATH) [join $gcc_include_dirs ";"]
set ::env(C_INCLUDE_PATH) $::env(CPATH)
set ::env(LIBRARY_PATH) [file join $gcc_root lib]
set gcc_libexec_candidates [glob -nocomplain [file join [file dirname $gcc_install_path] libexec gcc x86_64-w64-mingw32 *]]
if {[llength $gcc_libexec_candidates] > 0} {
    set ::env(RDI_MINGW_LIB) "$gcc_install_path;[lindex $gcc_libexec_candidates 0]"
} else {
    set ::env(RDI_MINGW_LIB) $gcc_install_path
}
set ::env(PATH) "$gcc_install_path;$::env(PATH)"
set overlay_root [file dirname $overlay_data_dir]
set ::env(XILINX_VIVADO) $overlay_root
set ::env(RDI_APPROOT) $overlay_root
set ::env(RDI_DATADIR) $overlay_data_dir
set project_name [file rootname [file tail $xpr]]
set sim_working_dir [file normalize [file join [file dirname $xpr] "$project_name.sim" sim_1 behav xsim]]
if {![file isdirectory [file join $sim_working_dir xsim.dir]]} {
    fail "compiled XSim library is missing: [file join $sim_working_dir xsim.dir]"
}
cd $sim_working_dir
puts "SIM_WORKING_DIRECTORY=[pwd]"
puts "XSIM_GCC_INSTALL_PATH=$gcc_install_path"
puts "GCC_SIM_EXE_PATH=$::env(GCC_SIM_EXE_PATH)"
puts "RDI_MINGW_LIB=$::env(RDI_MINGW_LIB)"
puts "GCC_EXEC_PREFIX=$::env(GCC_EXEC_PREFIX)"
puts "XILINX_VIVADO=$::env(XILINX_VIVADO)"
puts "RDI_DATADIR=$::env(RDI_DATADIR)"
if {[catch {launch_simulation -gcc_install_path $gcc_install_path -simset sim_1 -mode behavioral -step elaborate -noclean_dir} message]} {
    fail "cannot elaborate existing XSim snapshot: $message"
}
puts "ELABORATE=PASS"
close_project
exit 0
