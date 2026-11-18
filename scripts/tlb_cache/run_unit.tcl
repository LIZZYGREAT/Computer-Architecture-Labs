# Build an isolated, reproducible unit-test XPR. The official XPRs remain
# untouched; their legacy PLL is replaced only for cycle-based unit benches.
# Usage: vivado -mode batch -source run_unit.tcl -tclargs <case> <suite> <repo-root> <run-dir>
if {[llength $argv] != 4} {
    error "usage: run_unit.tcl <lab13|lab16|lab17> <directed|official> <repo-root> <run-dir>"
}
set case [lindex $argv 0]
set suite [lindex $argv 1]
set repo [file normalize [lindex $argv 2]]
set run_dir [file normalize [lindex $argv 3]]
file mkdir $run_dir

set project_name ${case}_${suite}
set project_dir [file join $run_dir project]
create_project -force $project_name $project_dir -part xc7a200tfbg676-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

if {$case eq "lab13"} {
    set rtl [file join $repo lab13 tlb_verify rtl tlb.v]
    set wrapper [file join $repo lab13 tlb_verify rtl tlb_top.v]
    set official_tb [file join $repo lab13 tlb_verify testbench testbench.v]
    set directed_tb [file join $repo lab13 tlb_verify testbench tb_tlb_directed.sv]
} elseif {$case eq "lab16"} {
    set rtl [file join $repo lab16 cache_verify rtl cache.v]
    set wrapper [file join $repo lab16 cache_verify rtl cache_top.v]
    set official_tb [file join $repo lab16 cache_verify testbench testbench.v]
    set directed_tb [file join $repo lab16 cache_verify testbench tb_cache_directed.sv]
} elseif {$case eq "lab14_translate"} {
    set rtl [list \
        [file join $repo lab13 tlb_verify rtl tlb.v] \
        [file join $repo lab14 cpu_tlb rtl myCPU addr_translate.v]]
    set directed_tb [file join $repo lab14 cpu_tlb testbench tb_lab14_translate.sv]
} elseif {$case eq "lab11_axi3"} {
    set rtl [list \
        [file join $repo lab14 cpu_tlb rtl myCPU IF_stage.v] \
        [file join $repo lab14 cpu_tlb rtl myCPU axi3_cpu_bus.v]]
    set directed_tb [file join $repo lab14 cpu_tlb testbench tb_lab11_axi3_bus.sv]
} elseif {$case eq "lab17"} {
    set rtl [list \
        [file join $repo lab17 cpu_icache rtl myCPU icache.v] \
        [file join $repo lab17 cpu_icache rtl myCPU cache_axi3_bridge.v]]
    set directed_tb [file join $repo lab17 cpu_icache testbench tb_lab17_icache_directed.sv]
} else {
    error "unsupported unit case: $case"
}
if {$case eq "lab17" && $suite ne "directed"} {
    error "Lab17 currently supports only its directed bridge/cache suite"
}

foreach rtl_file $rtl {
    if {![file isfile $rtl_file]} {
        error "required RTL is missing: $rtl_file"
    }
}
if {$suite eq "directed"} {
    if {![file isfile $directed_tb]} {
        error "directed testbench is missing: $directed_tb"
    }
    add_files -fileset sources_1 $rtl
    add_files -fileset sim_1 $directed_tb
    set sim_top [file rootname [file tail $directed_tb]]
} elseif {$suite eq "official"} {
    add_files -fileset sources_1 [list $rtl $wrapper [file join $repo scripts tlb_cache sim_support clk_pll_stub.v]]
    add_files -fileset sim_1 $official_tb
    set sim_top testbench
} else {
    error "unsupported suite: $suite"
}

set_property top $sim_top [get_filesets sim_1]
if {$case eq "lab11_axi3"} {
    set cpu_include [file join $repo lab14 cpu_tlb rtl myCPU]
    set_property include_dirs [list $cpu_include] [get_filesets sources_1]
    set_property include_dirs [list $cpu_include] [get_filesets sim_1]
}
set_property xsim.simulate.log_all_signals true [get_filesets sim_1]
set_property xsim.simulate.runtime 1000000ns [get_filesets sim_1]
update_compile_order -fileset sim_1
puts "CASE=$case"
puts "SUITE=$suite"
puts "PROJECT_XPR=[file join $project_dir ${project_name}.xpr]"
puts "SIM_TOP=$sim_top"
puts "RTL=$rtl"
puts "SIM_FILES=[get_files -of_objects [get_filesets sim_1]]"
set active_path [file join $run_dir active-sources.txt]
set active_file [open $active_path w]
puts $active_file "PROJECT_XPR=[file join $project_dir ${project_name}.xpr]"
foreach f [get_files -of_objects [get_filesets sources_1]] {
    puts $active_file "SOURCE=[get_property NAME $f]"
}
foreach f [get_files -of_objects [get_filesets sim_1]] {
    puts $active_file "SIM_SOURCE=[get_property NAME $f]"
}
if {$case eq "lab11_axi3"} {
    puts $active_file "SOURCE=[file join $repo lab14 cpu_tlb rtl myCPU mycpu.h]"
}
close $active_file
launch_simulation -mode behavioral -simset sim_1
set sim_dir [file join $project_dir ${project_name}.sim sim_1 behav xsim]
set sim_log [file join $sim_dir simulate.log]
if {![file isfile $sim_log]} {
    error "simulation log was not produced: $sim_log"
}
set log_in [open $sim_log r]
set sim_text [read $log_in]
close $log_in
if {[regexp -nocase {WATCHDOG_TIMEOUT|----FAIL!!!|Fatal:|ERROR:|Error:} $sim_text]} {
    error "simulation reported a failure; inspect $sim_log"
}
if {$suite eq "directed"} {
    if {$case eq "lab14_translate"} {
        set pass_marker "LAB14_TRANSLATE_PASS"
    } elseif {$case eq "lab11_axi3"} {
        set pass_marker "LAB11_AXI3_BUS_PASS"
    } elseif {$case eq "lab17"} {
        set pass_marker "DIRECTED_PASS"
    } else {
        set pass_marker "DIRECTED_PASS"
    }
} elseif {$case eq "lab13"} {
    set pass_marker "----PASS!!!"
    foreach marker {"OK!!!write" "OK!!!read" "OK!!!search" "Test end!"} {
        if {[string first $marker $sim_text] < 0} {
            error "official Lab13 simulation missed required marker: $marker"
        }
    }
} else {
    set pass_marker "----PASS!!!"
    if {[string first "Test end!" $sim_text] < 0} {
        error "official Lab16 simulation missed Test end!"
    }
    set index_markers [regexp -all -inline -nocase {index ([0-9a-f]{2}) finished} $sim_text]
    if {[llength $index_markers] != 512} {
        error "official Lab16 simulation expected 256 unique finished indexes"
    }
    set seen_indexes [dict create]
    foreach {marker finished_index} $index_markers {
        dict set seen_indexes [string tolower $finished_index] 1
    }
    if {[dict size $seen_indexes] != 256} {
        error "official Lab16 simulation did not finish every index exactly once"
    }
    for {set index_value 0} {$index_value < 256} {incr index_value} {
        set expected_index [format %02x $index_value]
        if {![dict exists $seen_indexes $expected_index]} {
            error "official Lab16 simulation missed index $expected_index"
        }
    }
    foreach failure_marker {"replace wrong at" "cacheres wrong at"} {
        if {[string first $failure_marker $sim_text] >= 0} {
            error "official Lab16 simulation reported: $failure_marker"
        }
    }
}
if {$case eq "lab17"} {
    foreach marker {
        "DIRECTED_CHECKS=24"
        "DIRECTED_COUNTS_VALID cpu=4/4 data=2/2 writeback=1/1"
        "DIRECTED_FAULT_INJECTION=RID_MISMATCH accepted=1 completed=0 expected_pending=1 axi_fault=1"
        "WAVE_CASE=ICACHE_8_BEAT_REFILL_AND_DATA_ARBITRATION"
        "WAVE_CASE=ICACHE_SAME_LINE_HIT"
        "WAVE_CASE=KSEG1_UNCACHE_SINGLE_BEAT"
        "WAVE_CASE=DIRTY_WRITEBACK_8_BEATS_AND_B"
        "WAVE_CASE=UNCACHE_STORE_AW_W_INDEPENDENT"
        "WAVE_CASE=RID_MISMATCH_STICKY_AXI_FAULT"
        "DIRECTED_PASS"
    } {
        if {[string first $marker $sim_text] < 0} {
            error "Lab17 directed test missed required marker: $marker"
        }
    }
}
if {[string first $pass_marker $sim_text] < 0} {
    error "simulation missed PASS marker $pass_marker; inspect $sim_log"
}
if {$case eq "lab11_axi3"} {
    foreach marker {
        "LAB11_AXI3_IF_REDIRECT_STALLED_AR_PASS"
        "LAB11_AXI3_IF_REDIRECT_ACCEPTED_AR_PASS"
        "LAB11_AXI3_HANDSHAKE_PASS reads=2 stores=2 AW_first=1 W_first=1"
        "LAB11_AXI3_RID_CHECK_PASS"
        "LAB11_AXI3_RRESP_CHECK_PASS"
        "LAB11_AXI3_RLAST_CHECK_PASS"
        "LAB11_AXI3_BID_CHECK_PASS"
        "LAB11_AXI3_BRESP_CHECK_PASS"
    } {
        if {[string first $marker $sim_text] < 0} {
            error "Lab11 AXI regression missed required marker: $marker"
        }
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
if {[file isfile $waveform_path]} {
    file copy -force $waveform_path [file join $run_dir wave-full.wdb]
}
set result_path [file join $run_dir result.txt]
set result [open $result_path w]
puts $result "RUN_ID=[file tail $run_dir]"
puts $result "CASE=$case"
puts $result "SUITE=$suite"
puts $result "STATUS=PASS"
puts $result "SIM_TOP=$sim_top"
puts $result "PASS_MARKER=$pass_marker"
puts $result "PROJECT_XPR=[file join $project_dir ${project_name}.xpr]"
puts $result "WAVEFORM=[expr {[file isfile [file join $run_dir wave-full.wdb]] ? "wave-full.wdb" : "NOT_CAPTURED"}]"
if {$suite eq "directed" && [regexp {DIRECTED_CHECKS=([0-9]+)} $sim_text -> check_count]} {
    puts $result "DIRECTED_CHECKS=$check_count"
}
if {$case eq "lab17" && [regexp {DIRECTED_COUNTS_VALID ([^\r\n]+)} $sim_text -> directed_counts]} {
    puts $result "DIRECTED_COUNTS_VALID=$directed_counts"
}
if {$case eq "lab17" && [regexp {DIRECTED_FAULT_INJECTION=([^\r\n]+)} $sim_text -> fault_injection]} {
    puts $result "DIRECTED_FAULT_INJECTION=$fault_injection"
}
if {$suite eq "official" && $case eq "lab13"} {
    puts $result "OFFICIAL_WRITE=PASS"
    puts $result "OFFICIAL_READ=PASS"
    puts $result "OFFICIAL_SEARCH=PASS"
    puts $result "OFFICIAL_TEST_END=PASS"
}
close $result
close_sim -force
close_project
# Keep the XPR and copied run evidence; remove rebuildable simulator products.
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
puts "UNIT_SIMULATION_FINISHED=true"
