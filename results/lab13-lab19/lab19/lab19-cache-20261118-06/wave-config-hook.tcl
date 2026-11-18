
set run_dir [file normalize [file dirname [info script]]]
set wave_log [open [file join $run_dir wave-config-hook.log] w]
if {[catch {
    set wave_config [current_wave_config]
    if {[string length $wave_config] == 0} { create_wave_config }
    set wave_added [list]
    foreach wave_object {/tb_lab19_cache/clk /tb_lab19_cache/resetn /tb_lab19_cache/soc_lite/u_cpu/cache_maint_op /tb_lab19_cache/soc_lite/u_cpu/cache_maint_vaddr /tb_lab19_cache/soc_lite/u_cpu/cache_maint_commit /tb_lab19_cache/soc_lite/u_cpu/icache_maint_done /tb_lab19_cache/soc_lite/u_cpu/dcache_maint_done /tb_lab19_cache/soc_lite/u_cpu/u_icache/state /tb_lab19_cache/soc_lite/u_cpu/u_icache/stat_miss /tb_lab19_cache/soc_lite/u_cpu/u_icache/stat_refill /tb_lab19_cache/soc_lite/u_cpu/u_dcache/state /tb_lab19_cache/soc_lite/u_cpu/u_dcache/stat_writeback /tb_lab19_cache/soc_lite/u_cpu/u_cache_axi3_bridge/rd_state /tb_lab19_cache/soc_lite/u_cpu/u_cache_axi3_bridge/wr_state} {
        set wave_matches [get_objects -quiet $wave_object]
        if {[llength $wave_matches] > 0} {
            add_wave $wave_matches
            lappend wave_added $wave_object
        }
    }
    save_wave_config [file join $run_dir wave-full.wcfg]
} wave_error]} {
    puts $wave_log "WCFG_CAPTURE_ERROR=$wave_error"
} else {
    puts $wave_log "WCFG_CAPTURED=wave-full.wcfg"
    puts $wave_log "WAVE_OBJECTS_ADDED=[join $wave_added ,]"
}
close $wave_log
