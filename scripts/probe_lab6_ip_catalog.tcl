# Read the installed Vivado catalog for multiplier and divider IP definitions.
# Run in batch mode with the output path passed after -tclargs.

if {[llength $argv] != 1} {
    error "usage: probe_lab6_ip_catalog.tcl <output-file>"
}

set output_path [lindex $argv 0]
create_project -in_memory -part xc7a200tfbg676-2
set definitions [lsort [get_ipdefs -all]]
set matches {}
foreach definition $definitions {
    if {[regexp -nocase {(^|:)(mult_gen|div_gen):} $definition]} {
        lappend matches $definition
    }
}
if {[llength $matches] == 0} {
    error "Vivado IP catalog has no mult_gen or div_gen definitions"
}

set output_file [open $output_path w]
puts $output_file "VIVADO_VERSION=[version -short]"
puts $output_file "PART=xc7a200tfbg676-2"
foreach definition $matches {
    puts $output_file "IPDEF=$definition"
}
close $output_file

puts "VIVADO_VERSION=[version -short]"
puts "PART=xc7a200tfbg676-2"
puts "IP_MATCH_COUNT=[llength $matches]"
foreach definition $matches {
    puts "IPDEF=$definition"
}
