
set run_dir [file normalize [file dirname [info script]]]
set wave_log [open [file join $run_dir wave-config-hook.log] w]
if {[catch {
    set wave_config [current_wave_config]
    if {[string length $wave_config] == 0} { create_wave_config }
    add_wave /
    set wave_added [list]
    foreach wave_object {/tb_lab19_maint_directed/u_icache/state /tb_lab19_maint_directed/u_icache/valid_way2 /tb_lab19_maint_directed/u_icache/valid_way3 /tb_lab19_maint_directed/u_icache/tag_way2 /tb_lab19_maint_directed/u_icache/tag_way3 /tb_lab19_maint_directed/u_dcache/state /tb_lab19_maint_directed/u_dcache/valid_way2 /tb_lab19_maint_directed/u_dcache/valid_way3 /tb_lab19_maint_directed/u_dcache/dirty_way2 /tb_lab19_maint_directed/u_dcache/dirty_way3 /tb_lab19_maint_directed/u_dcache/maint_selected_dirty} {
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
