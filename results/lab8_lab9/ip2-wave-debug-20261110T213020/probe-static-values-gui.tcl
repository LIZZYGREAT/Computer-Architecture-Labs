if {[llength $argv] != 2} {
    error "usage: probe-static-values-gui.tcl <wdb> <wcfg>"
}

set wdb [file normalize [lindex $argv 0]]
set wcfg [file normalize [lindex $argv 1]]
puts "STATIC_WDB=$wdb"
puts "STATIC_WCFG=$wcfg"

open_wave_database -noautoloadwcfg $wdb
if {[catch {open_wave_config $wcfg} message]} {
    puts "STATIC_WCFG_OPEN_ERROR=$message"
} else {
    puts "STATIC_WCFG_OPEN=PASS"
}
if {[catch {current_time} time]} {
    puts "STATIC_CURRENT_TIME_ERROR=$time"
} else {
    puts "STATIC_CURRENT_TIME=$time"
}

foreach path {
    /interrupt_tb/clk
    /interrupt_tb/dut/trap_commit
    /interrupt_tb/dut/trap_pc
    /interrupt_tb/dut/cp0_epc
    /interrupt_tb/dut/eret_commit
    /interrupt_tb/data_sram_wen
} {
    if {[catch {get_value -radix hex $path} value]} {
        puts "STATIC_VALUE_ERROR $path $value"
    } else {
        puts "STATIC_VALUE $path $value"
    }
}

set waves [get_waves *]
puts "STATIC_WAVE_COUNT=[llength $waves]"
if {[llength $waves] > 0} {
    set wave [lindex $waves 0]
    puts "STATIC_FIRST_WAVE=$wave"
    puts "STATIC_FIRST_WAVE_PROPERTIES=[join [list_property $wave] ,]"
    foreach property [list_property $wave] {
        if {[catch {get_property $property $wave} value]} {
            puts "STATIC_WAVE_PROPERTY_ERROR $property $value"
        } else {
            puts "STATIC_WAVE_PROPERTY $property=$value"
        }
    }
}
exit
