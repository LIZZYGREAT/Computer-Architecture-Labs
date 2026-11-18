
set wave_log [open C:/Users/lenovo/Desktop/Projects/FPGA/results/lab13-lab19/lab17/r2l17fault06/wave-config-hook.log w]
if {[catch {
    set wave_config [current_wave_config]
    if {[string length $wave_config] == 0} { create_wave_config }
    add_wave /
    set wave_added [list]
    foreach wave_object {/tb_lab17_icache_directed/dut_bridge/axi_fault /tb_lab17_icache_directed/dut_icache/cache_fault /tb_lab17_icache_directed/dut_icache/state /tb_lab17_icache_directed/dut_icache/cpu_data_ok /tb_lab17_icache_directed/rid /tb_lab17_icache_directed/rresp /tb_lab17_icache_directed/rlast /tb_lab17_icache_directed/rvalid /tb_lab17_icache_directed/rready} {
        set wave_matches [get_objects -quiet $wave_object]
        if {[llength $wave_matches] > 0} {
            add_wave $wave_matches
            lappend wave_added $wave_object
        }
    }
    save_wave_config C:/Users/lenovo/Desktop/Projects/FPGA/results/lab13-lab19/lab17/r2l17fault06/wave-full.wcfg
} wave_error]} {
    puts $wave_log "WCFG_CAPTURE_ERROR=$wave_error"
} else {
    puts $wave_log "WCFG_CAPTURED=wave-full.wcfg"
    puts $wave_log "WAVE_OBJECTS_ADDED=[join $wave_added ,]"
}
close $wave_log
