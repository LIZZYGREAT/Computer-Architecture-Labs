
set wave_log [open C:/Users/lenovo/Desktop/Projects/FPGA/results/lab13-lab19/lab19/r2l19contract03/wave-config-hook.log w]
if {[catch {
    set wave_config [current_wave_config]
    if {[string length $wave_config] == 0} { create_wave_config }
    add_wave /
    set wave_added [list]
    foreach wave_object {/tb_lab19_index_maint_contract/dut/cache_maint_req /tb_lab19_index_maint_contract/dut/cache_maint_op /tb_lab19_index_maint_contract/dut/cache_maint_vaddr /tb_lab19_index_maint_contract/dut/cache_maint_translation_ok /tb_lab19_index_maint_contract/dut/cache_maint_addr_ok /tb_lab19_index_maint_contract/dut/cache_maint_done /tb_lab19_index_maint_contract/dut/cache_maint_unsupported /tb_lab19_index_maint_contract/dut/u_icache/state /tb_lab19_index_maint_contract/dut/u_dcache/state /tb_lab19_index_maint_contract/dut/awaddr /tb_lab19_index_maint_contract/dut/awvalid /tb_lab19_index_maint_contract/dut/wdata /tb_lab19_index_maint_contract/dut/wvalid /tb_lab19_index_maint_contract/dut/wlast /tb_lab19_index_maint_contract/dut/bvalid /tb_lab19_index_maint_contract/dut/bready} {
        set wave_matches [get_objects -quiet $wave_object]
        if {[llength $wave_matches] > 0} {
            add_wave $wave_matches
            lappend wave_added $wave_object
        }
    }
    save_wave_config C:/Users/lenovo/Desktop/Projects/FPGA/results/lab13-lab19/lab19/r2l19contract03/wave-full.wcfg
} wave_error]} {
    puts $wave_log "WCFG_CAPTURE_ERROR=$wave_error"
} else {
    puts $wave_log "WCFG_CAPTURED=wave-full.wcfg"
    puts $wave_log "WAVE_OBJECTS_ADDED=[join $wave_added ,]"
}
close $wave_log
