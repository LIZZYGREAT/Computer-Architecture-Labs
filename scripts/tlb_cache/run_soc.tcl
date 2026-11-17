# Create and run the isolated Lab14 CPU/TLB SoC project.
# Usage: vivado -mode batch -source run_soc.tcl -tclargs <repo-root> <run-dir>
if {[llength $argv] != 2} {
    error "usage: run_soc.tcl <repo-root> <run-dir>"
}

set repo [file normalize [lindex $argv 0]]
set run_dir [file normalize [lindex $argv 1]]
set cpu_root [file join $repo lab14 cpu_tlb]
set project_name lab14_tlb_soc
set project_dir [file join $run_dir project]
file mkdir $run_dir

create_project -force $project_name $project_dir -part xc7a200tfbg676-2
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property target_simulator XSim [current_project]

set cpu_rtl [glob -nocomplain [file join $cpu_root rtl myCPU *.v]]
set common_rtl [list \
    [file join $cpu_root rtl axi_wrap axi_wrap.v] \
    [file join $cpu_root rtl ram_wrap axi_wrap_ram.v] \
    [file join $cpu_root rtl CONFREG confreg.v] \
    [file join $cpu_root rtl soc_axi_lite_top.v]]
set ip_files [list \
    [file join $cpu_root rtl xilinx_ip axi_ram axi_ram.xci] \
    [file join $cpu_root rtl xilinx_ip axi_crossbar_1x2 axi_crossbar_1x2.xci] \
    [file join $cpu_root rtl xilinx_ip lab6_mult33 lab6_mult33.xci] \
    [file join $cpu_root rtl xilinx_ip lab6_div32 lab6_div32.xci]]
set coe_file [file join $repo lab14 tlb_func obj inst_ram.coe]
set ip_source_root [file join $run_dir ip-src]
file mkdir $ip_source_root
set staged_ip_files [list]
foreach source_ip $ip_files {
    set ip_name [file rootname [file tail $source_ip]]
    set staged_ip_dir [file join $ip_source_root $ip_name]
    file mkdir $staged_ip_dir
    set staged_ip [file join $staged_ip_dir [file tail $source_ip]]
    file copy -force $source_ip $staged_ip
    if {$ip_name eq "axi_ram"} {
        set xci_in [open $staged_ip r]
        set xci_text [read $xci_in]
        close $xci_in
        set relative_coe "../../../../tlb_func/obj/inst_ram.coe"
        if {[string first $relative_coe $xci_text] < 0} {
            error "Lab14 COE reference not found in staged axi_ram XCI"
        }
        set xci_text [string map [list $relative_coe [file normalize $coe_file]] $xci_text]
        set xci_out [open $staged_ip w]
        puts -nonewline $xci_out $xci_text
        close $xci_out
    }
    lappend staged_ip_files $staged_ip
}
set include_header [file join $cpu_root rtl myCPU mycpu.h]
set tlb_rtl [file join $repo lab13 tlb_verify rtl tlb.v]
set testbench [file join $cpu_root testbench tb_lab14_tlb.sv]

foreach required [concat $cpu_rtl $common_rtl $ip_files [list $include_header $coe_file $tlb_rtl $testbench]] {
    if {![file isfile $required]} {
        error "required S2 source or image is missing: $required"
    }
}

add_files -norecurse -fileset sources_1 [concat $cpu_rtl $common_rtl $staged_ip_files [list $include_header $coe_file $tlb_rtl]]
add_files -norecurse -fileset sim_1 $testbench
set_property include_dirs [list [file join $cpu_root rtl myCPU]] [get_filesets sources_1]
set_property top soc_axi_lite_top [get_filesets sources_1]
set_property top tb_lab14_tlb [get_filesets sim_1]
set_property xsim.simulate.log_all_signals true [get_filesets sim_1]
set_property xsim.simulate.runtime 20000000ns [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
set ip_objects [get_ips -quiet]
if {[llength $ip_objects] > 0} {
    upgrade_ip -quiet $ip_objects
    generate_target all $ip_objects
    export_ip_user_files -of_objects $ip_objects -no_script -sync -force -quiet
}
report_ip_status -file [file join $run_dir ip-status.rpt]

set project_xpr [file join $project_dir ${project_name}.xpr]
set active_path [file join $run_dir active-sources.txt]
set active_file [open $active_path w]
puts $active_file "PROJECT_XPR=$project_xpr"
foreach f [concat $cpu_rtl $common_rtl $ip_files [list $include_header $coe_file $tlb_rtl]] {
    puts $active_file "SOURCE=$f"
}
foreach f [get_files -of_objects [get_filesets sim_1]] {
    puts $active_file "SIM_SOURCE=[get_property NAME $f]"
}
close $active_file

puts "CASE=lab14"
puts "SUITE=official"
puts "PROJECT_XPR=$project_xpr"
puts "SIM_TOP=tb_lab14_tlb"
puts "PROGRAM_IMAGE=$coe_file"
launch_simulation -mode behavioral

set sim_dir [file join $project_dir ${project_name}.sim sim_1 behav xsim]
set sim_log [file join $sim_dir simulate.log]
if {![file isfile $sim_log]} {
    error "simulation log was not produced: $sim_log"
}
set h [open $sim_log r]
set sim_text [read $h]
close $h
if {[regexp -nocase {LAB14_WATCHDOG_TIMEOUT|LAB14_SCORE_|LAB14_TEST_SEQUENCE|LAB14_SOFTWARE_REPORTED_FAILURE|Fatal:|ERROR:|Error:} $sim_text]} {
    error "Lab14 simulation reported a failure; inspect $sim_log"
}
if {[regexp -all {LAB14_TESTPOINT=} $sim_text] != 6} {
    error "expected six Lab14 score points; inspect $sim_log"
}
if {[string first "LAB14_N1_N6_PASS score=6/6" $sim_text] < 0} {
    error "Lab14 simulation missed n1-n6 PASS marker; inspect $sim_log"
}

foreach filename {compile.log elaborate.log simulate.log} {
    set source_path [file join $sim_dir $filename]
    if {[file isfile $source_path]} {
        file copy -force $source_path [file join $run_dir $filename]
    }
}
set compile_order_path [file join $sim_dir tb_lab14_tlb_vlog.prj]
if {[file isfile $compile_order_path]} {
    file copy -force $compile_order_path [file join $run_dir sim-compile-order.prj]
}
set waveform_path [file join $sim_dir tb_lab14_tlb_behav.wdb]
if {[file isfile $waveform_path]} {
    file copy -force $waveform_path [file join $run_dir wave-full.wdb]
}

set result [open [file join $run_dir result.txt] w]
puts $result "RUN_ID=[file tail $run_dir]"
puts $result "CASE=lab14"
puts $result "SUITE=official"
puts $result "STATUS=PASS"
puts $result "SIM_TOP=tb_lab14_tlb"
puts $result "PASS_MARKER=LAB14_N1_N6_PASS score=6/6"
puts $result "TESTPOINTS=6"
puts $result "TLB_OP_COMMIT=MEM"
puts $result "PROJECT_XPR=$project_xpr"
puts $result "PROGRAM_IMAGE=$coe_file"
puts $result "WAVEFORM=[expr {[file isfile [file join $run_dir wave-full.wdb]] ? "wave-full.wdb" : "NOT_CAPTURED"}]"
close $result

close_sim -force
close_project
# Keep the XPR and copied run evidence; remove rebuildable Vivado products.
foreach generated [list \
    [file join $run_dir .Xil] \
    [file join $run_dir xsim.dir] \
    [file join $project_dir ${project_name}.cache] \
    [file join $project_dir ${project_name}.hw] \
    [file join $project_dir ${project_name}.ip_user_files] \
    [file join $project_dir ${project_name}.sim] \
    [file join $project_dir ${project_name}.gen]] {
    if {[file isdirectory $generated]} { file delete -force $generated }
}
foreach staged_ip_dir [glob -nocomplain [file join $ip_source_root *]] {
    foreach staged_product [glob -nocomplain [file join $staged_ip_dir *]] {
        if {[file extension $staged_product] ne ".xci"} {
            file delete -force $staged_product
        }
    }
}
puts "SOC_SIMULATION_FINISHED=true"
