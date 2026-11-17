set wdb [file normalize [file join [pwd] results lab8_lab9 interrupt-ip2-20261110T interrupt-ip2.wdb]]
set wcfg [file normalize [file join [pwd] report lab8-9 figures waveforms 10_external_interrupt_ip2.wcfg]]
puts "IP2_STATIC_TEST=B"
puts "IP2_STATIC_WDB=$wdb"
puts "IP2_STATIC_WCFG=$wcfg"
open_wave_database -noautoloadwcfg $wdb
open_wave_config $wcfg
puts "IP2_STATIC_TEST_B_READY=1"
