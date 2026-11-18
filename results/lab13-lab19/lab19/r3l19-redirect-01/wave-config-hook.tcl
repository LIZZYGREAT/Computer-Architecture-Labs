
set wave_log [open C:/Users/lenovo/Desktop/Projects/FPGA/results/lab13-lab19/lab19/r3l19-redirect-01/wave-config-hook.log w]
if {[catch {
    set wave_config [current_wave_config]
    if {[string length $wave_config] == 0} { create_wave_config }
    add_wave /
    set wave_added [list]
    foreach wave_object {/tb_lab19_if_redirect_directed/dut/state /tb_lab19_if_redirect_directed/dut/request_pc /tb_lab19_if_redirect_directed/dut/stale_response /tb_lab19_if_redirect_directed/dut/restart_pc /tb_lab19_if_redirect_directed/dut/redirect_valid /tb_lab19_if_redirect_directed/dut/redirect_pc /tb_lab19_if_redirect_directed/dut/delay_slot_pending /tb_lab19_if_redirect_directed/dut/branch_target_pending /tb_lab19_if_redirect_directed/cache_redirect /tb_lab19_if_redirect_directed/tlb_redirect /tb_lab19_if_redirect_directed/inst_sram_addr_ok /tb_lab19_if_redirect_directed/inst_sram_data_ok /tb_lab19_if_redirect_directed/fs_to_ds_valid} {
        set wave_matches [get_objects -quiet $wave_object]
        if {[llength $wave_matches] > 0} {
            add_wave $wave_matches
            lappend wave_added $wave_object
        }
    }
    save_wave_config C:/Users/lenovo/Desktop/Projects/FPGA/results/lab13-lab19/lab19/r3l19-redirect-01/wave-full.wcfg
} wave_error]} {
    puts $wave_log "WCFG_CAPTURE_ERROR=$wave_error"
} else {
    puts $wave_log "WCFG_CAPTURED=wave-full.wcfg"
    puts $wave_log "WAVE_OBJECTS_ADDED=[join $wave_added ,]"
}
close $wave_log
