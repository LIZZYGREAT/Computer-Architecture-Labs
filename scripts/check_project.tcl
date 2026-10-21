# Read-only preflight for the existing Lab3 Vivado project.
proc fail {message} {
    puts stderr "ENVIRONMENT_ERROR: $message"
    error $message
}

if {[llength $argv] < 2} {
    fail "usage: check_project.tcl <project.xpr> <report-dir>"
}

set xpr [file normalize [lindex $argv 0]]
set report_dir [file normalize [lindex $argv 1]]
if {![file isfile $xpr]} {
    fail "Vivado project not found: $xpr"
}
set xpr_file [open $xpr r]
set xpr_text [read $xpr_file]
close $xpr_file
set auto_disabled_count [regexp -all {<Attr Name="AutoDisabled" Val="1"/>} $xpr_text]
puts "AUTODISABLED_COUNT=$auto_disabled_count"
if {$auto_disabled_count > 0} {
    fail "project contains automatically disabled sources; restore them before simulation"
}
file mkdir $report_dir

if {[catch {open_project -quiet $xpr} message]} {
    fail "cannot open existing project: $message"
}

set project [current_project]
set part [get_property PART $project]
set source_set [get_filesets -quiet sources_1]
set sim_set [get_filesets -quiet sim_1]
if {$source_set eq "" || $sim_set eq ""} {
    fail "project must contain sources_1 and sim_1 filesets"
}

set source_top [get_property TOP $source_set]
set sim_top [get_property TOP $sim_set]
set source_set_name [get_property NAME $source_set]
set sim_source_set "unknown"
catch {set sim_source_set [get_property SOURCE_SET $sim_set]}
puts "PROJECT=$xpr"
puts "PART=$part"
puts "DESIGN_TOP=$source_top"
puts "SIM_TOP=$sim_top"
puts "SIM_SOURCE_SET=$sim_source_set"
foreach project_property [list_property $project] {
    if {[string match -nocase *sim* $project_property] || [string match -nocase *source* $project_property] || [string match -nocase *include* $project_property]} {
        set value "unknown"
        catch {set value [get_property $project_property $project]}
        puts "PROJECT_PROPERTY=$project_property VALUE=$value"
    }
}
if {$source_top ne "soc_lite_top"} {
    fail "unexpected design top: $source_top (expected soc_lite_top)"
}
if {$sim_top ne "tb_top"} {
    fail "unexpected simulation top: $sim_top (expected tb_top)"
}

set missing_files {}
foreach fileset [list $source_set $sim_set] {
    set files [get_files -quiet -of_objects $fileset]
    puts "FILESET=[get_property NAME $fileset] FILE_COUNT=[llength $files]"
    if {[llength $files] == 0} {
        fail "empty fileset: [get_property NAME $fileset]"
    }
    foreach f $files {
        set name [string trim $f "{}"]
        puts "FILE_ENTRY=$name"
        if {![file exists $name]} {
            lappend missing_files $name
        }
    }
}
foreach f [get_files -quiet -of_objects $source_set] {
    set path [string trim $f "{}"]
    set used "unknown"
    set enabled "unknown"
    set type "unknown"
    catch {set used [get_property USED_IN_SIMULATION $f]}
    catch {set enabled [get_property IS_ENABLED $f]}
    catch {set type [get_property FILE_TYPE $f]}
    puts "SOURCE_FILE=$path TYPE=$type USED_IN_SIMULATION=$used ENABLED=$enabled"
}
set diagnostic_files [concat [get_files -quiet -of_objects $source_set] [get_files -quiet -of_objects $sim_set]]
foreach f $diagnostic_files {
    set path [string trim $f "{}"]
    if {[string match -nocase *mycpu_tb.v $path] || [string match -nocase *soc_lite_top.v $path] || [string match -nocase *EXE_stage.v $path]} {
        puts "DIAGNOSTIC_FILE=$path"
        foreach property [list_property $f] {
            if {[string match -nocase *used* $property] || [string match -nocase *enabled* $property] || [string match -nocase *scope* $property] || [string match -nocase *library* $property] || [string match -nocase *disable* $property] || [string match -nocase *sim* $property] || [string match -nocase *type* $property] || [string match -nocase *top* $property]} {
                set value "unknown"
                catch {set value [get_property $property $f]}
                puts "FILE_PROPERTY=$property VALUE=$value"
            }
        }
    }
}
foreach compile_set [list $source_set $sim_set] {
    set sim_compile_files {}
    catch {set sim_compile_files [get_files -quiet -compile_order sources -used_in simulation -of_objects $compile_set]}
    puts "SIM_COMPILE_ORDER_SET=[get_property NAME $compile_set] COUNT=[llength $sim_compile_files]"
    foreach f $sim_compile_files {
        puts "SIM_COMPILE_FILE=[string trim $f "{}"]"
    }
}
foreach property [list_property $sim_set] {
    if {[string match -nocase *xsim* $property] || [string match -nocase *increment* $property] || [string match -nocase *include*design* $property]} {
        set value "unknown"
        catch {set value [get_property $property $sim_set]}
        puts "SIM_PROPERTY=$property VALUE=$value"
    }
}
if {[llength $missing_files] > 0} {
    puts stderr "MISSING_SOURCE_FILES=[join $missing_files {; }]"
    fail "project references missing source or simulation files"
}

set ip_report [file join $report_dir ip_status.rpt]
if {[catch {report_ip_status -file $ip_report} message]} {
    fail "cannot inspect IP status: $message"
}
set ip_status_file ""
set ip_status_text ""
set ip_status_open_error ""
for {set retry 0} {$retry < 20} {incr retry} {
    if {![catch {set ip_status_file [open $ip_report r]} ip_status_open_error]} {
        set ip_status_text [read $ip_status_file]
        close $ip_status_file
        break
    }
    after 250
}
if {$ip_status_file eq ""} {
    fail "cannot open IP status report after retries: $ip_report ($ip_status_open_error)"
}
set ips [get_ips -quiet]
puts "IP_COUNT=[llength $ips]"
set expected_ips {clk_pll data_ram inst_ram}
foreach ip $ips {
    set locked 0
    catch {set locked [get_property IS_LOCKED $ip]}
    if {$locked} {
        fail "IP is locked: [get_property NAME $ip]"
    }
}
foreach name $expected_ips {
    if {![regexp -nocase "\\|\\s*$name\\s*\\|\\s*Up-to-date\\s*\\|" $ip_status_text]} {
        fail "IP $name is missing or not Up-to-date; see $ip_report"
    }
    puts "IP=$name STATUS=Up-to-date LOCKED=0"
}
puts "IP_STATUS_REPORT=$ip_report"
puts "PREFLIGHT=PASS"
close_project
exit 0
