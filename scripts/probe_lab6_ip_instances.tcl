# Instantiate catalog defaults in an isolated in-memory project, print every
# CONFIG property, and generate simulation/synthesis/instantiation products.

if {[llength $argv] != 1} {
    error "usage: probe_lab6_ip_instances.tcl <probe-output-directory>"
}

set probe_root [file normalize [lindex $argv 0]]
file mkdir $probe_root
set generated_root [file join $probe_root generated]
file mkdir $generated_root
create_project -in_memory -part xc7a200tfbg676-2
set report_path [file join $probe_root ip-properties.txt]
set report [open $report_path w]
puts $report "VIVADO_VERSION=[version -short]"
puts $report "PART=xc7a200tfbg676-2"

foreach {short_name vlnv} {
    mult xilinx.com:ip:mult_gen:12.0
    div xilinx.com:ip:div_gen:5.1
} {
    set module_name "lab6_${short_name}_probe"
    set ip_dir [file join $generated_root $module_name]
    file mkdir $ip_dir
    create_ip -vlnv $vlnv -module_name $module_name -dir $ip_dir
    set ip [get_ips $module_name]
    puts $report "IP=$vlnv"
    foreach property [lsort [list_property $ip]] {
        if {[regexp {^(CONFIG\.|GENERATION_STATUS$|IS_LOCKED$|IP_FILE$)} $property]} {
            set value "<unreadable>"
            catch {set value [get_property $property $ip]}
            puts $report "$property=$value"
        }
    }
    if {[catch {generate_target all $ip} message]} {
        puts $report "GENERATE_TARGET_ERROR=$message"
        close $report
        error "$module_name output generation failed: $message"
    }
    puts $report "GENERATE_TARGET=PASS"
}

close $report
puts "IP_PROPERTIES=$report_path"
puts "GENERATED_ROOT=$generated_root"
