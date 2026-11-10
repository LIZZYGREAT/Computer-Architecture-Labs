if {[llength $argv] != 2} {
    error "usage: probe-static-values-final.tcl <wdb> <wcfg>"
}

set wdb [file normalize [lindex $argv 0]]
set wcfg [file normalize [lindex $argv 1]]
puts "STATIC_WDB=$wdb"
puts "STATIC_WCFG=$wcfg"

open_wave_database -noautoloadwcfg $wdb
if {[catch {open_wave_config $wcfg} message]} {
    puts "STATIC_WCFG_OPEN=FAIL $message"
    exit 1
}
puts "STATIC_WCFG_OPEN=PASS"
puts "STATIC_WAVE_COUNT=[llength [get_waves *]]"

if {[catch {current_time} value]} {
    puts "STATIC_CURRENT_TIME=UNAVAILABLE $value"
} else {
    puts "STATIC_CURRENT_TIME=$value"
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
        puts "STATIC_VALUE_UNAVAILABLE $path $value"
    } else {
        puts "STATIC_VALUE $path $value"
    }
}

exit
