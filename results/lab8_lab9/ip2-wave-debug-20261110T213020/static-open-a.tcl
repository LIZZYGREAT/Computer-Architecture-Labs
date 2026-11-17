set wdb [file normalize [file join [pwd] results lab8_lab9 interrupt-ip2-20261110T interrupt-ip2.wdb]]
puts "IP2_STATIC_TEST=A"
puts "IP2_STATIC_WDB=$wdb"
open_wave_database -noautoloadwcfg $wdb
add_wave /interrupt_tb/clk
puts "IP2_STATIC_TEST_A_READY=1"
