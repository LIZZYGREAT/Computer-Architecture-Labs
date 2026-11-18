
set wave_log [open C:/Users/lenovo/Desktop/Projects/FPGA/results/lab13-lab19/lab19/r2l19wbs01/wave-config-hook.log w]
if {[catch {
    set wave_config [current_wave_config]
    if {[string length $wave_config] == 0} { create_wave_config }
    add_wave /
    set wave_added [list]
    foreach wave_object {/tb_lab19_dcache_writeback_scoreboard/u_dcache/state /tb_lab19_dcache_writeback_scoreboard/u_dcache/req_addr /tb_lab19_dcache_writeback_scoreboard/u_dcache/victim_way /tb_lab19_dcache_writeback_scoreboard/u_dcache/maint_index /tb_lab19_dcache_writeback_scoreboard/u_dcache/maint_way /tb_lab19_dcache_writeback_scoreboard/cpu_req /tb_lab19_dcache_writeback_scoreboard/cpu_addr /tb_lab19_dcache_writeback_scoreboard/cpu_data_ok /tb_lab19_dcache_writeback_scoreboard/refill_addr /tb_lab19_dcache_writeback_scoreboard/refill_data_valid /tb_lab19_dcache_writeback_scoreboard/refill_data /tb_lab19_dcache_writeback_scoreboard/maint_req /tb_lab19_dcache_writeback_scoreboard/maint_done /tb_lab19_dcache_writeback_scoreboard/awaddr /tb_lab19_dcache_writeback_scoreboard/awvalid /tb_lab19_dcache_writeback_scoreboard/awready /tb_lab19_dcache_writeback_scoreboard/wdata /tb_lab19_dcache_writeback_scoreboard/wstrb /tb_lab19_dcache_writeback_scoreboard/wvalid /tb_lab19_dcache_writeback_scoreboard/wready /tb_lab19_dcache_writeback_scoreboard/wlast /tb_lab19_dcache_writeback_scoreboard/bvalid /tb_lab19_dcache_writeback_scoreboard/bready} {
        set wave_matches [get_objects -quiet $wave_object]
        if {[llength $wave_matches] > 0} {
            add_wave $wave_matches
            lappend wave_added $wave_object
        }
    }
    save_wave_config C:/Users/lenovo/Desktop/Projects/FPGA/results/lab13-lab19/lab19/r2l19wbs01/wave-full.wcfg
} wave_error]} {
    puts $wave_log "WCFG_CAPTURE_ERROR=$wave_error"
} else {
    puts $wave_log "WCFG_CAPTURED=wave-full.wcfg"
    puts $wave_log "WAVE_OBJECTS_ADDED=[join $wave_added ,]"
}
close $wave_log
