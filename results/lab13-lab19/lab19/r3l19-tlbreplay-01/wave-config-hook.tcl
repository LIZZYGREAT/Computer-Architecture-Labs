
set wave_log [open C:/Users/lenovo/Desktop/Projects/FPGA/results/lab13-lab19/lab19/r3l19-tlbreplay-01/wave-config-hook.log w]
if {[catch {
    set wave_config [current_wave_config]
    if {[string length $wave_config] == 0} { create_wave_config }
    add_wave /
    set wave_added [list]
    foreach wave_object {/tb_lab19_tlb_redirect_contract/dut/tlb_write_enable /tb_lab19_tlb_redirect_contract/dut/pipeline_flush /tb_lab19_tlb_redirect_contract/dut/if_stage/state /tb_lab19_tlb_redirect_contract/dut/if_stage/request_pc /tb_lab19_tlb_redirect_contract/dut/if_stage/stale_response /tb_lab19_tlb_redirect_contract/dut/if_stage/restart_pc /tb_lab19_tlb_redirect_contract/dut/u_tlb/entry_pfn0 /tb_lab19_tlb_redirect_contract/dut/inst_sram_addr /tb_lab19_tlb_redirect_contract/araddr /tb_lab19_tlb_redirect_contract/arvalid /tb_lab19_tlb_redirect_contract/rvalid /tb_lab19_tlb_redirect_contract/rlast} {
        set wave_matches [get_objects -quiet $wave_object]
        if {[llength $wave_matches] > 0} {
            add_wave $wave_matches
            lappend wave_added $wave_object
        }
    }
    save_wave_config C:/Users/lenovo/Desktop/Projects/FPGA/results/lab13-lab19/lab19/r3l19-tlbreplay-01/wave-full.wcfg
} wave_error]} {
    puts $wave_log "WCFG_CAPTURE_ERROR=$wave_error"
} else {
    puts $wave_log "WCFG_CAPTURED=wave-full.wcfg"
    puts $wave_log "WAVE_OBJECTS_ADDED=[join $wave_added ,]"
}
close $wave_log
