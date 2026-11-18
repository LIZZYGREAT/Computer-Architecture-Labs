set project_file [file normalize [lindex $argv 0]]
set output_dir [file normalize [lindex $argv 1]]
open_project $project_file
set clk_pll_xci [file normalize [lindex $argv 2]]
add_files -norecurse -fileset sources_1 $clk_pll_xci
set clk_pll_ip [get_ips -quiet clk_pll]
if {[llength $clk_pll_ip] != 1} { error "Expected one clk_pll IP for synthesis" }
upgrade_ip -quiet $clk_pll_ip
generate_target all $clk_pll_ip
export_ip_user_files -of_objects $clk_pll_ip -no_script -sync -force -quiet
reset_run synth_1
set_property top soc_axi_lite_top [get_filesets sources_1]
puts "SYNTH_TOP=soc_axi_lite_top"
puts "SYNTH_PART=[get_property PART [current_project]]"
launch_runs synth_1 -jobs 4
wait_on_run synth_1
set synth_run [get_runs synth_1]
set synth_status [get_property STATUS $synth_run]
set synth_progress [get_property PROGRESS $synth_run]
puts "SYNTH_STATUS=$synth_status"
puts "SYNTH_PROGRESS=$synth_progress"
if {$synth_progress ne "100%" || ![string match "*Complete*" $synth_status]} {
    error "Synthesis did not complete successfully: $synth_status ($synth_progress)"
}
open_run synth_1
report_utilization -file [file join $output_dir utilization.rpt]
if {[catch {report_timing_summary -file [file join $output_dir timing-summary.rpt]} timing_error]} {
    set timing_file [open [file join $output_dir timing-summary.txt] w]
    puts $timing_file "TIMING_REPORT_STATUS=UNAVAILABLE"
    puts $timing_file "REASON=$timing_error"
    close $timing_file
} else {
    set timing_file [open [file join $output_dir timing-summary.txt] w]
    puts $timing_file "TIMING_REPORT_STATUS=GENERATED"
    close $timing_file
}
close_design
close_project