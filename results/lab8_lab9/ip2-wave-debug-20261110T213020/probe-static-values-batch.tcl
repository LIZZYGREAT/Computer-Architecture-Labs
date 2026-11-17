if {[llength $argv] != 1} {
    error "usage: probe-static-values-batch.tcl <wdb>"
}

set wdb [file normalize [lindex $argv 0]]
puts "STATIC_WDB=$wdb"
open_wave_database -noautoloadwcfg $wdb
puts "STATIC_CURRENT_TIME=[current_time]"

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
exit
