# Create the Lab6 arithmetic IP in the DUT project's tracked IP source tree.

if {[llength $argv] != 2} {
    error "usage: create_lab6_arithmetic_ip.tcl <dut-xpr> <lab-root>"
}

set xpr [file normalize [lindex $argv 0]]
set lab_root [file normalize [lindex $argv 1]]
set ip_root [file join $lab_root lab3 CPU_CDE mycpu_verify rtl xilinx_ip]
set report_path [file join $lab_root results lab6_lab7 ip-probe dut-ip-status.txt]
file mkdir [file dirname $report_path]

open_project $xpr

set multiplier_name lab6_mult33
if {[llength [get_ips -quiet $multiplier_name]] == 0} {
    create_ip -vlnv xilinx.com:ip:mult_gen:12.0 -module_name $multiplier_name -dir $ip_root
}
set multiplier [get_ips $multiplier_name]
set_property -dict [list \
    CONFIG.PortAType {Signed} \
    CONFIG.PortAWidth {33} \
    CONFIG.PortBType {Signed} \
    CONFIG.PortBWidth {33} \
    CONFIG.PipeStages {1} \
    CONFIG.ClockEnable {true} \
    CONFIG.Multiplier_Construction {Use_LUTs}] $multiplier
generate_target all $multiplier

set divider_name lab6_div32
if {[llength [get_ips -quiet $divider_name]] == 0} {
    create_ip -vlnv xilinx.com:ip:div_gen:5.1 -module_name $divider_name -dir $ip_root
}
set divider [get_ips $divider_name]
set_property -dict [list \
    CONFIG.algorithm_type {Radix2} \
    CONFIG.dividend_and_quotient_width {32} \
    CONFIG.divisor_width {32} \
    CONFIG.remainder_type {Remainder} \
    CONFIG.operand_sign {Unsigned} \
    CONFIG.clocks_per_division {8} \
    CONFIG.divide_by_zero_detect {false} \
    CONFIG.FlowControl {NonBlocking} \
    CONFIG.OutTready {false} \
    CONFIG.latency_configuration {Automatic} \
    CONFIG.ARESETN {true}] $divider
generate_target all $divider

set hilo_unit_file [file join $lab_root lab3 CPU_CDE mycpu_verify rtl myCPU hilo_unit.v]
if {[llength [get_files -quiet $hilo_unit_file]] == 0} {
    add_files -norecurse -fileset sources_1 $hilo_unit_file
}

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

set report [open $report_path w]
puts $report "VIVADO_VERSION=[version -short]"
puts $report "DUT_XPR=$xpr"
foreach {name ip properties} [list \
    $multiplier_name $multiplier {CONFIG.PortAWidth CONFIG.PortBWidth CONFIG.OutputWidthHigh CONFIG.OutputWidthLow CONFIG.PipeStages CONFIG.ClockEnable CONFIG.Multiplier_Construction} \
    $divider_name $divider {CONFIG.algorithm_type CONFIG.dividend_and_quotient_width CONFIG.divisor_width CONFIG.remainder_type CONFIG.operand_sign CONFIG.clocks_per_division CONFIG.latency CONFIG.FlowControl CONFIG.OutTready CONFIG.ARESETN}] {
    puts $report "IP=$name"
    foreach property $properties {
        puts $report "$property=[get_property $property $ip]"
    }
    puts $report "IP_FILE=[get_property IP_FILE $ip]"
}
set status_path [file join $lab_root results lab6_lab7 ip-probe dut-ip-status.rpt]
report_ip_status -file $status_path
puts $report "IP_STATUS_REPORT=$status_path"
puts $report "GENERATE_TARGET=PASS"
close $report

close_project
puts "IP_INTEGRATION_REPORT=$report_path"
