# Build candidate 33x33 multiply and 32-bit quotient/remainder IPs in an
# isolated in-memory project. No CPU project or source files are modified.

if {[llength $argv] != 1} {
    error "usage: create_lab6_arithmetic_ip_probe.tcl <probe-output-directory>"
}

set probe_root [file normalize [lindex $argv 0]]
file mkdir $probe_root
set generated_root [file join $probe_root generated]
file mkdir $generated_root
create_project -in_memory -part xc7a200tfbg676-2
set report [open [file join $probe_root configuration.txt] w]
puts $report "VIVADO_VERSION=[version -short]"
puts $report "PART=xc7a200tfbg676-2"

set module_name lab6_mult33_probe
set ip_dir [file join $generated_root $module_name]
file mkdir $ip_dir
create_ip -vlnv xilinx.com:ip:mult_gen:12.0 -module_name $module_name \
    -dir $ip_dir
set multiplier [get_ips $module_name]
set_property -dict [list \
    CONFIG.PortAType {Signed} \
    CONFIG.PortAWidth {33} \
    CONFIG.PortBType {Signed} \
    CONFIG.PortBWidth {33} \
    CONFIG.PipeStages {1} \
    CONFIG.ClockEnable {true} \
    CONFIG.Multiplier_Construction {Use_LUTs}] $multiplier
puts $report "IP=xilinx.com:ip:mult_gen:12.0 MODULE=$module_name"
foreach property {CONFIG.PortAWidth CONFIG.PortBWidth CONFIG.OutputWidthHigh CONFIG.OutputWidthLow CONFIG.PipeStages CONFIG.ClockEnable CONFIG.Multiplier_Construction} {
    puts $report "$property=[get_property $property $multiplier]"
}
generate_target all $multiplier
puts $report "GENERATE_TARGET_MULT=PASS"

set module_name lab6_div32_probe
set ip_dir [file join $generated_root $module_name]
file mkdir $ip_dir
create_ip -vlnv xilinx.com:ip:div_gen:5.1 -module_name $module_name \
    -dir $ip_dir
set divider [get_ips $module_name]
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
puts $report "IP=xilinx.com:ip:div_gen:5.1 MODULE=$module_name"
foreach property {CONFIG.algorithm_type CONFIG.dividend_and_quotient_width CONFIG.divisor_width CONFIG.remainder_type CONFIG.operand_sign CONFIG.clocks_per_division CONFIG.latency CONFIG.FlowControl CONFIG.OutTready CONFIG.latency_configuration CONFIG.ARESETN} {
    puts $report "$property=[get_property $property $divider]"
}
generate_target all $divider
puts $report "GENERATE_TARGET_DIV=PASS"

close $report
puts "CONFIGURATION=[file join $probe_root configuration.txt]"
puts "GENERATED_ROOT=$generated_root"
