# Build an independent synthesis project from the current Lab19 RTL tree.
# Usage: vivado -mode batch -source run_lab19_synthesis.tcl -tclargs <repo-root> <run-dir>

if {[llength $argv] != 2} {
    error "usage: run_lab19_synthesis.tcl <repo-root> <run-dir>"
}

set repo [file normalize [lindex $argv 0]]
set run_dir [file normalize [lindex $argv 1]]
set cpu_root [file join $repo lab19 cpu_cache]
set rtl_root [file join $cpu_root rtl]
set project_name r3l19_synthesis
set project_dir [file join $run_dir project]
set input_coe [file join $repo lab19 cache_func obj inst_ram.coe]
set part xc7a200tfbg676-2

file mkdir $run_dir
foreach required [list $input_coe [file join $repo lab13 tlb_verify rtl tlb.v]] {
    if {![file isfile $required]} {
        error "required synthesis input is missing: $required"
    }
}

set cpu_rtl [lsort [glob -nocomplain [file join $rtl_root myCPU *.v]]]
set common_rtl [list \
    [file join $rtl_root axi_wrap axi_wrap.v] \
    [file join $rtl_root ram_wrap axi_wrap_ram.v] \
    [file join $rtl_root CONFREG confreg.v] \
    [file join $rtl_root soc_axi_lite_top.v]]
set include_header [file join $rtl_root myCPU mycpu.h]
set tlb_rtl [file join $repo lab13 tlb_verify rtl tlb.v]

set ip_sources [list \
    [file join $rtl_root xilinx_ip axi_ram axi_ram.xci] \
    [file join $rtl_root xilinx_ip axi_crossbar_1x2 axi_crossbar_1x2.xci] \
    [file join $rtl_root xilinx_ip lab6_mult33 lab6_mult33.xci] \
    [file join $rtl_root xilinx_ip lab6_div32 lab6_div32.xci] \
    [file join $rtl_root xilinx_ip clk_pll clk_pll.xci]]

foreach required [concat $cpu_rtl $common_rtl $ip_sources [list $include_header $tlb_rtl]] {
    if {![file isfile $required]} {
        error "required synthesis source is missing: $required"
    }
}
if {[llength $cpu_rtl] == 0} {
    error "no Lab19 CPU RTL sources were found"
}

create_project $project_name $project_dir -part $part
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

# Stage XCI files inside the run so IP migration and the RAM COE path cannot
# modify the checked-in project inputs or resolve against a different image.
set ip_source_root [file join $run_dir ip-src]
file mkdir $ip_source_root
set staged_ip_files [list]
foreach source_ip $ip_sources {
    set ip_name [file rootname [file tail $source_ip]]
    set staged_ip_dir [file join $ip_source_root $ip_name]
    file mkdir $staged_ip_dir
    set staged_ip [file join $staged_ip_dir [file tail $source_ip]]
    file copy -force $source_ip $staged_ip
    if {$ip_name eq "axi_ram"} {
        set xci_in [open $staged_ip r]
        set xci_text [read $xci_in]
        close $xci_in
        set source_coe_ref "../../../../func_all94/obj/inst_ram.coe"
        if {[string first $source_coe_ref $xci_text] < 0} {
            error "expected axi_ram COE reference was not found in $source_ip"
        }
        set xci_text [string map [list $source_coe_ref [file normalize $input_coe]] $xci_text]
        set xci_out [open $staged_ip w]
        puts -nonewline $xci_out $xci_text
        close $xci_out
    }
    lappend staged_ip_files $staged_ip
}

add_files -norecurse -fileset sources_1 [concat $cpu_rtl $common_rtl $staged_ip_files [list $include_header $tlb_rtl]]
set_property include_dirs [list [file join $rtl_root myCPU]] [get_filesets sources_1]
set_property top soc_axi_lite_top [get_filesets sources_1]
update_compile_order -fileset sources_1

set ip_objects [get_ips -quiet]
if {[llength $ip_objects] != 5} {
    error "expected five Lab19 Xilinx IP objects, found [llength $ip_objects]: $ip_objects"
}
upgrade_ip -quiet $ip_objects
generate_target all $ip_objects
export_ip_user_files -of_objects $ip_objects -no_script -sync -force -quiet
report_ip_status -file [file join $run_dir ip-status.rpt]

set project_xpr [file join $project_dir ${project_name}.xpr]
set active_path [file join $run_dir active-sources.txt]
set active_file [open $active_path w]
puts $active_file "PROJECT_XPR=$project_xpr"
foreach source_file [concat $cpu_rtl $common_rtl $staged_ip_files [list $include_header $tlb_rtl]] {
    puts $active_file "SOURCE=$source_file"
}
close $active_file

set pre_synth_file [open [file join $run_dir synthesis-run.txt] w]
puts $pre_synth_file "SYNTH_TOP=soc_axi_lite_top"
puts $pre_synth_file "PART=$part"
puts $pre_synth_file "VIVADO_VERSION=[version -short]"
puts $pre_synth_file "IP_OBJECTS=[join $ip_objects ,]"
puts $pre_synth_file "SOURCE_FILE_COUNT=[expr {[llength $cpu_rtl] + [llength $common_rtl] + [llength $staged_ip_files] + 2}]"
close $pre_synth_file

puts "SYNTH_TOP=soc_axi_lite_top"
puts "SYNTH_PART=$part"
puts "SYNTH_VIVADO_VERSION=[version -short]"
puts "SYNTH_PROJECT=$project_xpr"
launch_runs synth_1 -jobs 4
wait_on_run synth_1
set synth_run [get_runs synth_1]
set synth_status [get_property STATUS $synth_run]
set synth_progress [get_property PROGRESS $synth_run]
puts "SYNTH_STATUS=$synth_status"
puts "SYNTH_PROGRESS=$synth_progress"

set run_file [open [file join $run_dir synthesis-run.txt] a]
puts $run_file "SYNTH_STATUS=$synth_status"
puts $run_file "SYNTH_PROGRESS=$synth_progress"
close $run_file
if {$synth_progress ne "100%" || ![string match "*Complete*" $synth_status]} {
    error "synthesis did not complete successfully: $synth_status ($synth_progress)"
}

open_run synth_1
report_utilization -file [file join $run_dir utilization.rpt]
report_utilization -hierarchical -file [file join $run_dir utilization-hierarchical.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose \
    -file [file join $run_dir timing-summary.rpt]
check_timing -verbose -file [file join $run_dir check-timing.rpt]
report_clocks -file [file join $run_dir clocks.rpt]
if {[catch {report_clock_interaction -file [file join $run_dir clock-interaction.rpt]} clock_error]} {
    set clock_file [open [file join $run_dir clock-interaction-status.txt] w]
    puts $clock_file "CLOCK_INTERACTION_REPORT_STATUS=UNAVAILABLE"
    puts $clock_file "REASON=$clock_error"
    close $clock_file
} else {
    set clock_file [open [file join $run_dir clock-interaction-status.txt] w]
    puts $clock_file "CLOCK_INTERACTION_REPORT_STATUS=GENERATED"
    close $clock_file
}
close_design
close_project
