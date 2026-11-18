# Create and run an isolated CPU SoC regression project.
# Usage: vivado -mode batch -source run_soc.tcl -tclargs <repo-root> <run-dir> ?lab14|lab11_trace|lab17|lab17_baseline?
if {[llength $argv] < 2 || [llength $argv] > 3} {
    error "usage: run_soc.tcl <repo-root> <run-dir> ?lab14|lab11_trace|lab17|lab17_baseline?"
}

set repo [file normalize [lindex $argv 0]]
set run_dir [file normalize [lindex $argv 1]]
set suite [expr {[llength $argv] == 3 ? [lindex $argv 2] : "lab14"}]
set cpu_root [file join $repo lab14 cpu_tlb]
set project_name ${suite}_soc
set project_dir [file join $run_dir project]
file mkdir $run_dir

if {$suite eq "lab14"} {
    set coe_file [file join $repo lab14 tlb_func obj inst_ram.coe]
    set testbench [file join $cpu_root testbench tb_lab14_tlb.sv]
    set sim_top tb_lab14_tlb
    set sim_runtime 20000000ns
    set trace_file ""
} elseif {$suite eq "lab11_trace"} {
    set coe_file [file join $repo lab11 CPU_CDE_AXI soft func_lab9 obj inst_ram.coe]
    set original_testbench [file join $cpu_root testbench mycpu_tb.v]
    set testbench [file join $run_dir tb_lab11_trace.v]
    set trace_file [file join $repo lab11 CPU_CDE_AXI cpu132_gettrace golden_trace.txt]
    set sim_top tb_top
    set sim_runtime 100000000ns
    if {![file isfile $original_testbench] || ![file isfile $trace_file]} {
        error "Lab11 golden-trace testbench or reference trace is missing"
    }
    set tb_in [open $original_testbench r]
    set tb_text [read $tb_in]
    close $tb_in
    set old_trace_define {`define TRACE_REF_FILE "../../../../../../../cpu132_gettrace/golden_trace.txt"}
    if {[string first $old_trace_define $tb_text] < 0} {
        error "Lab11 testbench trace macro is not at the expected baseline definition"
    }
    set new_trace_define [format {`define TRACE_REF_FILE "%s"} [file normalize $trace_file]]
    set tb_text [string map [list $old_trace_define $new_trace_define] $tb_text]
    set tb_out [open $testbench w]
    puts -nonewline $tb_out $tb_text
    close $tb_out
} elseif {$suite eq "lab17" || $suite eq "lab17_baseline"} {
    set cpu_root [file join $repo lab17 cpu_icache]
    set coe_file [file join $repo lab17 func_all94 obj inst_ram.coe]
    set testbench [file join $cpu_root testbench tb_lab17_functional.sv]
    set sim_top [expr {$suite eq "lab17" ? "tb_lab17_icache" : "tb_lab17_baseline"}]
    set sim_runtime 250000000ns
    set trace_file ""
} else {
    error "unsupported SoC regression suite: $suite"
}

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
        if {$suite eq "lab17" || $suite eq "lab17_baseline"} {
            set relative_coe "../../../../func_all94/obj/inst_ram.coe"
        } else {
            set relative_coe "../../../../tlb_func/obj/inst_ram.coe"
        }
        if {[string first $relative_coe $xci_text] < 0} {
            error "COE reference not found in staged axi_ram XCI"
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

foreach required [concat $cpu_rtl $common_rtl $ip_files [list $include_header $coe_file $tlb_rtl $testbench]] {
    if {![file isfile $required]} {
        error "required S2 source or image is missing: $required"
    }
}

add_files -norecurse -fileset sources_1 [concat $cpu_rtl $common_rtl $staged_ip_files [list $include_header $coe_file $tlb_rtl]]
add_files -norecurse -fileset sim_1 $testbench
set_property include_dirs [list [file join $cpu_root rtl myCPU]] [get_filesets sources_1]
set_property top soc_axi_lite_top [get_filesets sources_1]
set_property top $sim_top [get_filesets sim_1]
set log_all_signals [expr {$suite eq "lab14"}]
set_property xsim.simulate.log_all_signals $log_all_signals [get_filesets sim_1]
set_property xsim.simulate.runtime $sim_runtime [get_filesets sim_1]
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
foreach f [concat $cpu_rtl $common_rtl $staged_ip_files [list $include_header $coe_file $tlb_rtl]] {
    puts $active_file "SOURCE=$f"
}
if {$suite eq "lab11_trace"} {
    puts $active_file "SOURCE=$original_testbench"
}
foreach f [get_files -of_objects [get_filesets sim_1]] {
    puts $active_file "SIM_SOURCE=[get_property NAME $f]"
}
close $active_file

if {$suite eq "lab14"} {
    puts "CASE=lab14"
} elseif {$suite eq "lab17" || $suite eq "lab17_baseline"} {
    puts "CASE=lab17"
} else {
    puts "CASE=lab11"
}
puts "SUITE=$suite"
puts "PROJECT_XPR=$project_xpr"
puts "SIM_TOP=$sim_top"
puts "PROGRAM_IMAGE=$coe_file"
if {$trace_file ne ""} { puts "TRACE_REFERENCE=$trace_file" }
launch_simulation -mode behavioral

set sim_dir [file join $project_dir ${project_name}.sim sim_1 behav xsim]
set sim_log [file join $sim_dir simulate.log]
if {![file isfile $sim_log]} {
    error "simulation log was not produced: $sim_log"
}
set h [open $sim_log r]
set sim_text [read $h]
close $h
if {$suite eq "lab14"} {
    set case_name lab14
    set pass_marker "LAB14_N1_N6_PASS score=6/6"
    if {[regexp -nocase {LAB14_WATCHDOG_TIMEOUT|LAB14_SCORE_|LAB14_TEST_SEQUENCE|LAB14_SOFTWARE_REPORTED_FAILURE|Fatal:|ERROR:|Error:} $sim_text]} {
        error "Lab14 simulation reported a failure; inspect $sim_log"
    }
    if {[regexp -all {LAB14_TESTPOINT=} $sim_text] != 6} {
        error "expected six Lab14 score points; inspect $sim_log"
    }
    if {[string first $pass_marker $sim_text] < 0} {
        error "Lab14 simulation missed n1-n6 PASS marker; inspect $sim_log"
    }
} elseif {$suite eq "lab11_trace"} {
    set case_name lab11
    set pass_marker "COURSE_SOC_PASS"
    if {[regexp -nocase {COURSE_SOC_FAIL=|Fail!!!Total|Fatal:|ERROR:|Error:} $sim_text]} {
        error "Lab11 golden-trace regression reported a failure; inspect $sim_log"
    }
    foreach marker {"----PASS!!!" "TRACE_OPEN_PASS" "TRACE_EXHAUSTION_PASS" "COURSE_SOC_PASS"} {
        if {[string first $marker $sim_text] < 0} {
            error "Lab11 golden-trace regression missed marker $marker; inspect $sim_log"
        }
    }
} else {
    set case_name lab17
    if {$suite eq "lab17"} {
        set pass_marker "LAB17_ICACHE_FUNCTIONAL_PASS score=94/94"
    } else {
        set pass_marker "LAB17_BASELINE_FUNCTIONAL_PASS score=94/94"
    }
    if {[regexp -nocase {LAB17_FAIL=|Fatal:|ERROR:|Error:} $sim_text]} {
        error "Lab17 functional regression reported a failure; inspect $sim_log"
    }
    if {[regexp -all {LAB17_TESTPOINT=} $sim_text] != 94} {
        error "Lab17 functional regression expected 94 ordered score points; inspect $sim_log"
    }
    foreach marker [list $pass_marker "CACHE_STATS " "AXI_METRICS " "STORE_COUNTS accepted="] {
        if {[string first $marker $sim_text] < 0} {
            error "Lab17 functional regression missed required marker $marker; inspect $sim_log"
        }
    }
    if {![regexp {STORE_COUNTS accepted=([0-9]+) completed=([0-9]+) duplicate_store=0} $sim_text -> accepted_stores completed_stores] ||
        $accepted_stores != $completed_stores} {
        error "Lab17 store completion accounting is inconsistent; inspect $sim_log"
    }
    if {![regexp {AXI_METRICS ar=([0-9]+) r=([0-9]+) aw=([0-9]+) w=([0-9]+) b=([0-9]+)} $sim_text -> ar_count r_count aw_count w_count b_count] ||
        $r_count < $ar_count || $aw_count != $b_count || $aw_count != $w_count} {
        error "Lab17 AXI transaction/beat metrics are inconsistent; inspect $sim_log"
    }
}

foreach filename {compile.log elaborate.log simulate.log} {
    set source_path [file join $sim_dir $filename]
    if {[file isfile $source_path]} {
        file copy -force $source_path [file join $run_dir $filename]
    }
}
set compile_order_path [file join $sim_dir ${sim_top}_vlog.prj]
if {[file isfile $compile_order_path]} {
    file copy -force $compile_order_path [file join $run_dir sim-compile-order.prj]
}
set waveform_path [file join $sim_dir ${sim_top}_behav.wdb]
if {$suite eq "lab14" && [file isfile $waveform_path]} {
    file copy -force $waveform_path [file join $run_dir wave-full.wdb]
}

set result [open [file join $run_dir result.txt] w]
puts $result "RUN_ID=[file tail $run_dir]"
puts $result "CASE=$case_name"
puts $result "SUITE=$suite"
puts $result "STATUS=PASS"
puts $result "SIM_TOP=$sim_top"
puts $result "PASS_MARKER=$pass_marker"
if {$suite eq "lab14"} {
    puts $result "TESTPOINTS=6"
    puts $result "TLB_OP_COMMIT=MEM"
} elseif {$suite eq "lab11_trace"} {
    puts $result "TRACE_REFERENCE=$trace_file"
    set testpoint_count [regexp -all {Functional Test Point PASS!!!} $sim_text]
    puts $result "TESTPOINTS=$testpoint_count"
    if {[regexp {TRACE_EXHAUSTION_PASS records=([0-9]+) valid=([0-9]+)} $sim_text -> trace_records trace_valid]} {
        puts $result "TRACE_RECORDS=$trace_records"
        puts $result "TRACE_VALID_RECORDS=$trace_valid"
    }
    if {[regexp {BUS_METRICS ([^\r\n]+)} $sim_text -> bus_metrics]} {
        puts $result "BUS_METRICS=$bus_metrics"
    }
} else {
    puts $result "TESTPOINTS=94"
    if {[regexp {CACHE_STATS ([^\r\n]+)} $sim_text -> cache_metrics]} {
        puts $result "CACHE_STATS=$cache_metrics"
    }
    if {[regexp {AXI_METRICS ([^\r\n]+)} $sim_text -> axi_metrics]} {
        puts $result "AXI_METRICS=$axi_metrics"
    }
    if {[regexp {STORE_COUNTS ([^\r\n]+)} $sim_text -> store_metrics]} {
        puts $result "STORE_COUNTS=$store_metrics"
    }
    if {[regexp {cycles=([0-9]+)} $sim_text -> functional_cycles]} {
        puts $result "FUNCTIONAL_CYCLES=$functional_cycles"
    }
}
puts $result "PROJECT_XPR=$project_xpr"
puts $result "PROGRAM_IMAGE=$coe_file"
if {$suite eq "lab14" && [file isfile [file join $run_dir wave-full.wdb]]} {
    puts $result "WAVEFORM=wave-full.wdb"
} elseif {$suite eq "lab11_trace"} {
    puts $result "WAVEFORM=OMITTED_LONG_RUN"
} elseif {$suite eq "lab17" || $suite eq "lab17_baseline"} {
    puts $result "WAVEFORM=OMITTED_FUNCTIONAL_RUN_USE_DIRECTED_WAVEFORM"
} else {
    puts $result "WAVEFORM=NOT_CAPTURED"
}
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
