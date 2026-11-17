if {[llength $argv] != 2} {
    error "usage: probe-static-values.tcl <wdb> <wcfg>"
}

set wdb [file normalize [lindex $argv 0]]
set wcfg [file normalize [lindex $argv 1]]
puts "STATIC_WDB=$wdb"
puts "STATIC_WCFG=$wcfg"

open_wave_database -noautoloadwcfg $wdb
open_wave_config $wcfg
puts "STATIC_CURRENT_TIME=[current_time]"

foreach path {
    /interrupt_tb/clk
    /interrupt_tb/dut/trap_commit
    /interrupt_tb/dut/trap_pc
    /interrupt_tb/dut/eret_commit
    /interrupt_tb/data_sram_wen
} {
    if {[catch {get_value -radix hex $path} value]} {
        puts "STATIC_VALUE_ERROR $path $value"
    } else {
        puts "STATIC_VALUE $path $value"
    }
}
