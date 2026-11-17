# Read-only Vivado project/IP/source preflight for the Lab10/Lab11 projects.
if {[llength $argv] != 3} {
    puts stderr "usage: check_bus_project.tcl <case> <project.xpr> <output-dir>"
    exit 2
}

set case_name [lindex $argv 0]
set project_file [file normalize [lindex $argv 1]]
set output_dir [file normalize [lindex $argv 2]]
file mkdir $output_dir
set report_file [file join $output_dir "project-preflight.txt"]
set stream [open $report_file w]
puts $stream "CASE=$case_name"
puts $stream "PROJECT_XPR=$project_file"
puts $stream "VIVADO_VERSION=[version -short]"
puts $stream "OPEN_MODE=READ_ONLY"
flush $stream
set failures {}

if {![file exists $project_file]} {
    puts $stream "PROJECT_STATUS=MISSING"
    close $stream
    exit 2
}

if {[catch {open_project -read_only $project_file} open_error]} {
    puts $stream "PROJECT_STATUS=OPEN_FAILED"
    puts $stream "PROJECT_ERROR=$open_error"
    close $stream
    exit 2
}
puts $stream "PROJECT_STATUS=OPENED"

set design_set [get_filesets sources_1]
set sim_set [get_filesets sim_1]
puts $stream "DESIGN_TOP=[get_property TOP $design_set]"
puts $stream "SIM_TOP=[get_property TOP $sim_set]"
set expected_design_top [expr {$case_name eq "lab10" ? "soc_sram_lite_top" : "soc_axi_lite_top"}]
if {$case_name ni {lab10 lab11}} {
    puts $stream "CASE_STATUS=INVALID_CASE"
    close $stream
    close_project
    exit 2
}
if {[get_property TOP $design_set] ne $expected_design_top || [get_property TOP $sim_set] ne "tb_top"} {
    puts $stream "TOP_STATUS=FAIL"
    close $stream
    close_project
    exit 2
}

set cpu_files {}
set file_counts [dict create]
foreach source [get_files -of_objects $design_set] {
    set source_name [string trim [get_property NAME $source] "{}"]
    set source_type "unknown"
    set source_enabled "unknown"
    set source_synthesis "unknown"
    set source_simulation "unknown"
    catch {set source_type [get_property FILE_TYPE $source]}
    catch {set source_enabled [get_property IS_ENABLED $source]}
    catch {set source_synthesis [get_property USED_IN_SYNTHESIS $source]}
    catch {set source_simulation [get_property USED_IN_SIMULATION $source]}
    puts $stream "SOURCE_ENTRY=$source_name|TYPE=$source_type|ENABLED=$source_enabled|SYNTHESIS=$source_synthesis|SIMULATION=$source_simulation"
    if {![file exists $source_name]} {
        puts $stream "MISSING_SOURCE=$source_name"
        lappend failures "missing source $source_name"
    }
    set source_lower [string tolower [file normalize $source_name]]
    dict incr file_counts $source_lower
    if {[string match -nocase */rtl/mycpu/* $source_name]} {
        lappend cpu_files [file tail $source_name]
    }
}
puts $stream "CPU_FILES_IN_SOURCES_1=[llength $cpu_files]"
puts $stream "CPU_SOURCE_NAMES=[join [lsort -dictionary $cpu_files] {;}]"
foreach source_name [dict keys $file_counts] {
    if {[dict get $file_counts $source_name] != 1} {
        puts $stream "DUPLICATE_SOURCE=[dict get $file_counts $source_name]:$source_name"
        lappend failures "duplicate project source $source_name"
    }
}

set required_sources {mycpu_top.v IF_stage.v ID_stage.v EXE_stage.v MEM_stage.v WB_stage.v cp0_reg.v regfile.v alu.v tools.v hilo_unit.v mycpu.h}
if {$case_name eq "lab11"} { lappend required_sources axi3_cpu_bus.v }
set source_names {}
foreach source_name $cpu_files {
    lappend source_names [string tolower $source_name]
}
foreach required $required_sources {
    if {[lsearch -exact $source_names [string tolower $required]] < 0} {
        puts $stream "REQUIRED_CPU_SOURCE_MISSING=$required"
        lappend failures "required CPU source missing $required"
    }
}

foreach {set_name file_set} [list sources_1 $design_set sim_1 $sim_set] {
    set manifest [open [file join $output_dir "${set_name}-files.txt"] w]
    set listed_files [get_files -of_objects $file_set]
    puts $stream "${set_name}_FILE_COUNT=[llength $listed_files]"
    if {[llength $listed_files] == 0} {
        lappend failures "empty source list in $set_name"
    }
    set listed_names {}
    foreach source $listed_files {
        puts $manifest [get_property NAME $source]
        lappend listed_names [string tolower [file tail [get_property NAME $source]]]
    }
    close $manifest
    if {$set_name eq "sim_1" && [lsearch -exact $listed_names "mycpu_tb.v"] < 0} {
        puts $stream "SIM_TESTBENCH_MISSING=mycpu_tb.v"
        lappend failures "simulation testbench is missing from sim_1"
    }
}

if {[catch {report_ip_status -file [file join $output_dir "ip-status.rpt"]} ip_error]} {
    puts $stream "IP_STATUS=REPORT_FAILED"
    puts $stream "IP_ERROR=$ip_error"
    lappend failures "IP status report failed"
} else {
    puts $stream "IP_STATUS=REPORTED"
}

set required_ips {clk_pll lab6_mult33 lab6_div32}
if {$case_name eq "lab10"} {
    lappend required_ips data_ram inst_ram
} else {
    lappend required_ips axi_ram axi_crossbar_1x2
}
foreach ip_name $required_ips {
    set ip_obj [get_ips -quiet $ip_name]
    if {[llength $ip_obj] != 1} {
        puts $stream "REQUIRED_IP_MISSING=$ip_name"
        lappend failures "required IP missing $ip_name"
    } else {
        set locked "unknown"
        catch {set locked [get_property IS_LOCKED $ip_obj]}
        puts $stream "IP_ENTRY=$ip_name|IS_LOCKED=$locked"
    }
}
puts $stream "IP_LOCK_INTERPRETATION=read-only XPR and original 2019.2 IP revisions may report locked; runtime uses isolated private IP copies"

if {[catch {report_compile_order -of_objects $sim_set -file [file join $output_dir "sim-compile-order.rpt"]} compile_error]} {
    puts $stream "COMPILE_ORDER_REPORT_STATUS=REPORT_FAILED"
    puts $stream "COMPILE_ORDER_ERROR=$compile_error"
} else {
    puts $stream "COMPILE_ORDER_REPORT_STATUS=REPORTED"
}

foreach fileset_name {sources_1 sim_1} {
    set fileset [get_filesets $fileset_name]
    foreach usage {simulation synthesis} {
        set compile_files {}
        catch {set compile_files [get_files -quiet -compile_order sources -used_in $usage -of_objects $fileset]}
        puts $stream "${usage}_COMPILE_ORDER_${fileset_name}_COUNT=[llength $compile_files]"
        set manifest [open [file join $output_dir "${fileset_name}-${usage}-compile-order.txt"] w]
        foreach source $compile_files {
            puts $manifest [string trim [get_property NAME $source] "{}"]
        }
        close $manifest
    }
}
puts $stream "COMPILE_ORDER_STATUS=REQUIRES_RUNTIME_CONFIRMATION"
puts $stream "COMPILE_ORDER_NOTE=Read-only scan of this legacy XPR does not populate the compiler order; Vivado simulation compile/elaboration is the authoritative gate"

close $stream
close_project
if {[llength $failures] > 0} {
    set fail_stream [open $report_file a]
    puts $fail_stream "PREFLIGHT=FAIL"
    foreach failure $failures { puts $fail_stream "PREFLIGHT_ERROR=$failure" }
    close $fail_stream
    exit 1
}
set pass_stream [open $report_file a]
puts $pass_stream "PREFLIGHT=PASS"
close $pass_stream
exit 0
