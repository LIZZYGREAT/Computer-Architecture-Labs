# Run the existing testbench for a bounded amount of simulation time.
proc fail {message} {
    puts stderr "ENVIRONMENT_ERROR: $message"
    catch {clear_runtime_sim_options}
    catch {close_project}
    error $message
}

proc clear_runtime_sim_options {} {
    set sim_set [get_filesets -quiet sim_1]
    if {$sim_set eq ""} { return }
    foreach property {
        XSIM.COMPILE.TCL.PRE
        XSIM.ELABORATE.XELAB.MORE_OPTIONS
        XSIM.SIMULATE.XSIM.MORE_OPTIONS
        XSIM.SIMULATE.RUNTIME
        XSIM.SIMULATE.CUSTOM_TCL
    } {
        catch {set_property -name $property -value "" -objects $sim_set}
    }
}

if {[llength $argv] < 7} {
    fail "usage: run_behavioral_sim.tcl <project.xpr> <case> <max-ns> <pipeline-mode> <trace-file> <inst-mif> <result-dir> ?expected-functional-points? ?capture-waveform?"
}

set xpr [file normalize [lindex $argv 0]]
set test_case [lindex $argv 1]
set max_ns [lindex $argv 2]
set pipeline_mode [lindex $argv 3]
set trace_file [file normalize [lindex $argv 4]]
set inst_mif [file normalize [lindex $argv 5]]
set result_dir [file normalize [lindex $argv 6]]
set expected_functional_points 23
set capture_waveform 0
if {[llength $argv] >= 9} {
    set expected_functional_points [lindex $argv 7]
    set capture_waveform [lindex $argv 8]
} elseif {[llength $argv] == 8} {
    set optional_arg [lindex $argv 7]
    if {$optional_arg in {0 1}} {
        set capture_waveform $optional_arg
    } else {
        set expected_functional_points $optional_arg
    }
}
if {![file isfile $xpr]} {
    fail "Vivado project not found: $xpr"
}
if {$test_case ni {lab3 lab4 lab6 lab7}} {
    fail "unsupported case: $test_case"
}
if {![string is integer -strict $max_ns] || $max_ns <= 0} {
    fail "max-ns must be a positive integer"
}
if {$pipeline_mode ni {blocking forwarding}} {
    fail "pipeline-mode must be blocking or forwarding"
}
if {![string is integer -strict $expected_functional_points] || $expected_functional_points < 0} {
    fail "expected-functional-points must be a nonnegative integer"
}
if {$capture_waveform ni {0 1}} {
    fail "capture-waveform must be 0 or 1"
}
if {![file isfile $trace_file] || [file size $trace_file] == 0} {
    fail "reference trace is missing or empty: $trace_file"
}
if {![file isfile $inst_mif] || [file size $inst_mif] == 0} {
    fail "instruction image is missing or empty: $inst_mif"
}
if {![file isdirectory $result_dir]} {
    fail "result directory is missing: $result_dir"
}
if {[catch {open_project -quiet $xpr} message]} {
    fail "cannot open existing project: $message"
}
if {[catch {reset_simulation -simset sim_1} message]} {
    fail "cannot reset stale sim_1 output products: $message"
}
puts "SIM_OUTPUT_PRODUCTS_RESET=1"
set sim_set [get_filesets -quiet sim_1]
if {$sim_set eq ""} {
    fail "sim_1 fileset is missing"
}
set_property TOP tb_top $sim_set
set_property INCREMENTAL false $sim_set
set source_set_name [get_property SOURCE_SET $sim_set]
set source_set [get_filesets -quiet $source_set_name]
if {$source_set eq ""} {
    fail "simulation source set is missing: $source_set_name"
}
set project_source_root [file normalize [file join [file dirname $xpr] .. ..]]
set ip_source_root [string tolower [file normalize [file join $project_source_root rtl xilinx_ip]]]
# The checked-in project lists the RTL in sources_1 but XSim omits it from
# tb_top_vlog.prj. Add those same HDL files explicitly to sim_1 so Vivado
# compiles the testbench hierarchy. IP HDL is omitted here because Vivado
# already adds its generated simulation models from the XCI dependencies.
set hdl_sources {}
set skipped_ip_hdl_count 0
foreach f [get_files -quiet -of_objects $source_set] {
    set ext [string tolower [file extension [string trim $f "{}"]]]
    if {$ext in {.v .sv .vhd .vhdl}} {
        set normalized_file [string tolower [file normalize [string trim $f "{}"]]]
        if {[string first "$ip_source_root/" $normalized_file] == 0} {
            incr skipped_ip_hdl_count
        } else {
            lappend hdl_sources $f
        }
    }
}
if {[llength $hdl_sources] == 0} {
    fail "no HDL sources found in $source_set_name"
}
puts "SIM_EXPLICIT_DESIGN_SOURCE_COUNT=[llength $hdl_sources]"
puts "SIM_EXPLICIT_IP_SOURCE_SKIP_COUNT=$skipped_ip_hdl_count"
foreach f $hdl_sources {
    puts "SIM_EXPLICIT_DESIGN_SOURCE=[string trim $f "{}"]"
}
if {[catch {add_files -fileset $sim_set -norecurse $hdl_sources} message]} {
    fail "cannot add design HDL to simulation set: $message"
}
set sim_file_names {}
foreach f [get_files -quiet -of_objects $sim_set] {
    lappend sim_file_names [string tolower [file normalize [string trim $f "{}"]]]
}
set top_source [file normalize [file join $project_source_root testbench mycpu_tb.v]]
set design_top_source [file normalize [file join $project_source_root rtl soc_lite_top.v]]
set old_tb [get_files -quiet -of_objects $sim_set $top_source]
if {[llength $old_tb] > 0} {
    remove_files -fileset $sim_set $old_tb
}
if {[catch {add_files -fileset $sim_set -norecurse $top_source} message]} {
    fail "cannot re-add simulation testbench: $message"
}
set tb_file [get_files -quiet -of_objects $sim_set $top_source]
if {[llength $tb_file] != 1} {
    fail "expected one testbench file in simulation set, got [llength $tb_file]"
}
set_property FILE_TYPE Verilog $tb_file
set_property USED_IN {simulation} $tb_file
set_property IS_ENABLED true $tb_file
set_property USED_IN_SIMULATION true $tb_file
set_property USED_IN_SYNTHESIS false $tb_file
set_property USED_IN_IMPLEMENTATION false $tb_file
set sim_file_names {}
foreach f [get_files -quiet -of_objects $sim_set] {
    lappend sim_file_names [string tolower [file normalize [string trim $f "{}"]]]
}
if {[lsearch -exact $sim_file_names [string tolower $top_source]] < 0} {
    fail "testbench file is missing from simulation set: $top_source"
}
if {[lsearch -exact $sim_file_names [string tolower $design_top_source]] < 0} {
    fail "design top file is missing from simulation set: $design_top_source"
}
if {[get_property TOP $sim_set] ne "tb_top"} {
    fail "sim_1 must use tb_top"
}

puts "SIM_CASE=$test_case"
puts "SIM_MAX_NS=$max_ns"
puts "PIPELINE_MODE=$pipeline_mode"
puts "TRACE_FILE=$trace_file"
puts "INSTRUCTION_MIF=$inst_mif"
puts "EXPECTED_FUNCTIONAL_POINTS=$expected_functional_points"
puts "SIM_TOP=[get_property TOP $sim_set]"
puts "SIM_INCREMENTAL=[get_property INCREMENTAL $sim_set]"
puts "SIM_SOURCE_SET=$source_set_name"
puts "SIM_FILES_IN_SET=[llength [get_files -quiet -of_objects $sim_set]]"
set pipeline_forwarding [expr {$pipeline_mode eq "forwarding" ? 1 : 0}]
set_property -name XSIM.ELABORATE.XELAB.MORE_OPTIONS \
    -value [format {-generic_top "PIPELINE_FORWARDING=%d"} $pipeline_forwarding] \
    -objects $sim_set
set_property -name XSIM.SIMULATE.XSIM.MORE_OPTIONS \
    -value [format {--testplusarg "TRACE_REF=%s" --testplusarg "EXPECTED_POINTS=%d"} \
        $trace_file $expected_functional_points] \
    -objects $sim_set
set_property -name XSIM.SIMULATE.RUNTIME -value "${max_ns}ns" -objects $sim_set
puts "XSIM_GENERIC_TOP=PIPELINE_FORWARDING=$pipeline_forwarding"
puts "XSIM_TRACE_PLUSARG=TRACE_REF=$trace_file EXPECTED_POINTS=$expected_functional_points"
puts "XSIM_RUNTIME=${max_ns}ns"
set project_name [file rootname [file tail $xpr]]
set sim_working_dir [file normalize [file join [file dirname $xpr] "$project_name.sim" sim_1 behav xsim]]
file mkdir $sim_working_dir
cd $sim_working_dir
puts "SIM_WORKING_DIRECTORY=[pwd]"
set sim_custom_tcl [file join $result_dir xsim-run.tcl]
set sim_inst_mif [file join $sim_working_dir inst_ram.mif]
set sim_tcl_file [open $sim_custom_tcl w]
puts $sim_tcl_file "file copy -force [list $inst_mif] [list $sim_inst_mif]"
puts $sim_tcl_file "puts [list STAGED_INSTRUCTION_MIF=$sim_inst_mif]"
if {$capture_waveform} {
    puts $sim_tcl_file {log_wave -r /tb_top}
    puts "XSIM_WAVE_LOGGING=log_wave -r /tb_top"
}
puts $sim_tcl_file "run $max_ns ns"
puts $sim_tcl_file "quit"
close $sim_tcl_file
if {[catch {set_property -name XSIM.COMPILE.TCL.PRE -value "" -objects $sim_set} message]} {
    fail "cannot clear Vivado's compile hook: $message"
}
puts "XSIM_COMPILE_PRE_HOOK=[get_property XSIM.COMPILE.TCL.PRE $sim_set]"
set_property -name XSIM.SIMULATE.CUSTOM_TCL -value $sim_custom_tcl -objects $sim_set
puts "XSIM_CUSTOM_TCL=$sim_custom_tcl"
puts "XSIM_STAGED_INSTRUCTION_MIF=$sim_inst_mif"

# Generate Vivado's XSim scripts, then repair the generated source manifest in
# this Vivado process. XSIM.COMPILE.TCL.PRE launches a second Vivado process on
# this host, which currently fails during Tcl app loading before the hook runs.
if {[catch {launch_simulation -simset sim_1 -mode behavioral -scripts_only} message]} {
    fail "cannot generate behavioral simulation scripts: $message"
}
clear_runtime_sim_options
set manifest_file [file join $sim_working_dir tb_top_vlog.prj]
if {![file isfile $manifest_file]} {
    fail "XSim source manifest was not generated: $manifest_file"
}
set manifest_handle [open $manifest_file r]
set manifest_text [read $manifest_handle]
close $manifest_handle
set relative_tb "../../../../../../testbench/mycpu_tb.v"
if {[string first $relative_tb $manifest_text] < 0} {
    set marker "\n\n# compile glbl module"
    set marker_index [string last $marker $manifest_text]
    if {$marker_index < 0} {
        fail "XSim manifest does not contain the expected glbl section: $manifest_file"
    }
    set entry [format "\n\"%s\" \\\n\n# compile glbl module" $relative_tb]
    set replace_end [expr {$marker_index + [string length $marker] - 1}]
    set manifest_text [string replace $manifest_text $marker_index $replace_end $entry]
    set manifest_handle [open $manifest_file w]
    puts -nonewline $manifest_handle $manifest_text
    close $manifest_handle
    puts "TB_MANIFEST_INSERTED=$relative_tb"
} else {
    puts "TB_MANIFEST_ALREADY_PRESENT=$relative_tb"
}
if {[catch {file copy -force $inst_mif $sim_inst_mif} message]} {
    fail "cannot stage instruction memory image: $message"
}
puts "STAGED_INSTRUCTION_MIF=$sim_inst_mif"
set sim_step_error ""
foreach step {compile elaborate simulate} {
    set batch_file [file join $sim_working_dir "$step.bat"]
    if {![file isfile $batch_file]} {
        fail "Vivado did not generate the XSim $step script: $batch_file"
    }
    if {[catch {exec cmd.exe /d /c $batch_file} message]} {
        set sim_step_error "XSim $step step failed: $message"
        break
    }
}
if {$sim_step_error ne ""} {
    fail $sim_step_error
}
puts "SIM_RUN_COMMAND_RETURNED=1"
close_project
exit 0
