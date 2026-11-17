# Read-only inspection of the official Lab13 and Lab16 Vivado projects.
# Usage: vivado -mode batch -source check_official_projects.tcl -tclargs <out-dir> <tlb.xpr> <cache.xpr>
if {[llength $argv] != 3} {
    error "usage: check_official_projects.tcl <out-dir> <tlb.xpr> <cache.xpr>"
}
set out_dir [file normalize [lindex $argv 0]]
set specs [list \
    [list lab13 [file normalize [lindex $argv 1]]] \
    [list lab16 [file normalize [lindex $argv 2]]]]
file mkdir $out_dir
set summary_path [file join $out_dir official-project-inspection.txt]
set summary [open $summary_path w]
set failed 0
foreach spec $specs {
    lassign $spec case xpr
    puts $summary "CASE=$case"
    puts $summary "XPR=$xpr"
    if {![file isfile $xpr]} {
        puts $summary "OPEN_STATUS=MISSING_XPR"
        set failed 1
        continue
    }
    if {[catch {open_project -read_only $xpr} reason]} {
        puts $summary "OPEN_STATUS=ERROR"
        puts $summary "OPEN_ERROR=$reason"
        set failed 1
        continue
    }
    puts $summary "OPEN_STATUS=PASS"
    puts $summary "PART=[get_property PART [current_project]]"
    puts $summary "DESIGN_TOP=[get_property TOP [get_filesets sources_1]]"
    puts $summary "SIM_TOP=[get_property TOP [get_filesets sim_1]]"
    set files [get_files -quiet -of_objects [get_filesets sources_1]]
    puts $summary "SOURCES_1_FILE_COUNT=[llength $files]"
    foreach f $files {
        puts $summary "SOURCE=[get_property NAME $f]|TYPE=[get_property FILE_TYPE $f]"
    }
    set ip_path [file join $out_dir ${case}-ip-status.rpt]
    if {[catch {report_ip_status -file $ip_path} reason]} {
        puts $summary "IP_STATUS=ERROR"
        puts $summary "IP_STATUS_ERROR=$reason"
        set failed 1
    } else {
        puts $summary "IP_STATUS=REPORTED"
        puts $summary "IP_STATUS_REPORT=$ip_path"
        set ips [get_ips -quiet]
        puts $summary "IP_COUNT=[llength $ips]"
        foreach ip $ips {
            puts $summary "IP=[get_property NAME $ip]|DEF=[get_property IPDEF $ip]"
        }
    }
    close_project
    puts $summary "CLOSED=true"
}
close $summary
if {$failed} {
    puts "PROJECT_INSPECTION_STATUS=FAIL"
    exit 1
}
puts "PROJECT_INSPECTION_STATUS=PASS"
