# Create Lab9 exception and interrupt WCFGs from one validated static WDB.
# Arguments: <lab9-wdb> <output-directory>

if {[llength $argv] != 2} {
    error "usage: create_lab9_exception_irq_configs.tcl <lab9-wdb> <output-directory>"
}

set wdb [file normalize [lindex $argv 0]]
set output_dir [file normalize [lindex $argv 1]]
if {![file isfile $wdb]} { error "Lab9 WDB is missing: $wdb" }
if {![file isdirectory $output_dir]} { error "WCFG output directory is missing: $output_dir" }
open_wave_database -noautoloadwcfg $wdb
if {[llength [get_scopes -r /]] == 0} { error "Lab9 WDB contains no HDL scopes" }

proc find_wave_object {relative_path} {
    set leaf_name [file tail $relative_path]
    set candidates [get_objects -r -quiet "*$leaf_name"]
    set suffix "/$relative_path"
    set matches {}
    foreach candidate $candidates {
        if {[string match "*$suffix" $candidate]} { lappend matches $candidate }
    }
    if {[llength $matches] != 1} {
        error "expected one HDL object ending in '$suffix', found [llength $matches]"
    }
    return [lindex $matches 0]
}

proc create_profile {output_dir name signal_specs} {
    set wcfg [file join $output_dir "$name.wcfg"]
    if {[file exists $wcfg]} {
        puts "WCFG_ALREADY_EXISTS=$wcfg"
        return
    }
    create_wave_config $name
    set count 0
    foreach spec $signal_specs {
        set fields [split $spec ~]
        if {[llength $fields] != 2} { error "invalid signal spec '$spec'" }
        lassign $fields relative_path radix
        if {$radix ni {bin hex dec unsigned}} { error "invalid radix in '$spec'" }
        set object [find_wave_object $relative_path]
        add_wave -radix $radix $object
        puts "WCFG_SIGNAL=$object"
        incr count
    }
    save_wave_config $wcfg
    if {![file isfile $wcfg] || [file size $wcfg] == 0} { error "failed to save WCFG: $wcfg" }
    puts "WCFG=$wcfg"
    puts "WCFG_WAVE_COUNT=$count"
}

set clock soc_lite/cpu/clk~bin
set basics [list $clock \
    soc_lite/cpu/id_stage/ds_pc~hex \
    soc_lite/cpu/id_stage/ds_inst~hex \
    soc_lite/cpu/id_stage/ds_valid~bin \
    soc_lite/cpu/exe_stage/es_pc~hex \
    soc_lite/cpu/exe_stage/es_valid~bin \
    soc_lite/cpu/exe_stage/es_exception_valid~bin \
    soc_lite/cpu/exe_stage/es_exception_code~hex \
    soc_lite/cpu/mem_stage/ms_pc~hex \
    soc_lite/cpu/mem_stage/ms_exception_valid~bin \
    soc_lite/cpu/mem_stage/ms_exception_code~hex \
    soc_lite/cpu/mem_stage/ms_is_delay_slot~bin \
    soc_lite/cpu/trap_commit~bin \
    soc_lite/cpu/trap_code~hex \
    soc_lite/cpu/trap_pc~hex \
    soc_lite/cpu/cp0_reg/epc~hex \
    soc_lite/cpu/cp0_reg/cause_exc_code~hex \
    soc_lite/cpu/cp0_reg/cause_bd~bin \
    soc_lite/cpu/cp0_reg/status_exl~bin \
    soc_lite/cpu/eret_commit~bin \
    soc_lite/cpu/pipeline_flush~bin]

create_profile $output_dir 02_break $basics

set overflow [concat $basics [list \
    soc_lite/cpu/exe_stage/es_overflow_check_add~bin \
    soc_lite/cpu/exe_stage/es_add_overflow~bin \
    soc_lite/cpu/exe_stage/es_alu_src1~hex \
    soc_lite/cpu/exe_stage/es_alu_src2~hex \
    soc_lite/cpu/exe_stage/es_alu_result~hex \
    soc_lite/debug_wb_pc~hex \
    soc_lite/debug_wb_rf_wen~hex \
    soc_lite/debug_wb_rf_wnum~hex \
    soc_lite/debug_wb_rf_wdata~hex]]
create_profile $output_dir 03_overflow $overflow

set load_adel [concat $basics [list \
    soc_lite/cpu/exe_stage/es_exception_bad_vaddr~hex \
    soc_lite/cpu/exe_stage/es_alu_result~hex \
    soc_lite/cpu/exe_stage/data_sram_en~bin \
    soc_lite/cpu/exe_stage/data_sram_wen~hex \
    soc_lite/cpu/mem_stage/ms_bad_vaddr~hex \
    soc_lite/cpu/cp0_reg/bad_vaddr~hex]]
create_profile $output_dir 04_load_adel $load_adel

set store_ades [concat $basics [list \
    soc_lite/cpu/exe_stage/es_exception_bad_vaddr~hex \
    soc_lite/cpu/exe_stage/es_alu_result~hex \
    soc_lite/cpu/exe_stage/es_store_wen~hex \
    soc_lite/cpu/exe_stage/es_store_data~hex \
    soc_lite/cpu/exe_stage/data_sram_en~bin \
    soc_lite/cpu/exe_stage/data_sram_wen~hex \
    soc_lite/cpu/exe_stage/data_sram_wdata~hex \
    soc_lite/cpu/mem_stage/ms_bad_vaddr~hex \
    soc_lite/cpu/cp0_reg/bad_vaddr~hex]]
create_profile $output_dir 05_store_ades $store_ades

set fetch_adel [concat [list $clock \
    soc_lite/cpu/if_stage/fs_pc~hex \
    soc_lite/cpu/if_stage/fs_exception_valid~bin \
    soc_lite/cpu/if_stage/fs_exception_code~hex \
    soc_lite/cpu/id_stage/ds_pc~hex \
    soc_lite/cpu/id_stage/ds_inst~hex \
    soc_lite/cpu/id_stage/ds_fetch_exception_valid~bin \
    soc_lite/cpu/id_stage/ds_exception_code~hex \
    soc_lite/cpu/id_stage/ds_bad_vaddr~hex] [lrange $basics 4 end]]
create_profile $output_dir 06_fetch_adel $fetch_adel

set delay_slot [concat $basics [list \
    soc_lite/cpu/id_stage/ds_delay_slot~bin \
    soc_lite/cpu/id_stage/is_delay_slot~bin \
    soc_lite/cpu/exe_stage/es_is_delay_slot~bin \
    soc_lite/cpu/cp0_reg/bad_vaddr~hex]]
create_profile $output_dir 07_delay_slot $delay_slot

set timer_irq [concat [list $clock \
    soc_lite/cpu/cp0_reg/count~hex \
    soc_lite/cpu/cp0_reg/compare~hex \
    soc_lite/cpu/cp0_reg/count_add_en~bin \
    soc_lite/cpu/cp0_reg/cp0_write_compare~bin \
    soc_lite/cpu/cp0_reg/timer_pending~bin \
    soc_lite/cpu/cp0_reg/cause_ip~hex \
    soc_lite/cpu/cp0_reg/status_ie~bin \
    soc_lite/cpu/cp0_reg/status_im~hex \
    soc_lite/cpu/cp0_reg/status_exl~bin \
    soc_lite/cpu/cp0_reg/interrupt_pending~bin \
    soc_lite/cpu/id_stage/ds_interrupt_exception~bin \
    soc_lite/cpu/id_stage/exception_code~hex \
    soc_lite/cpu/trap_commit~bin \
    soc_lite/cpu/trap_code~hex \
    soc_lite/cpu/trap_pc~hex \
    soc_lite/cpu/cp0_reg/epc~hex \
    soc_lite/cpu/eret_commit~bin \
    soc_lite/cpu/pipeline_flush~bin \
    soc_lite/cpu/mem_stage/ms_is_delay_slot~bin]]
create_profile $output_dir 08_timer_irq $timer_irq

set soft_irq [concat [list $clock \
    soc_lite/cpu/cp0_reg/cause_sw_ip~hex \
    soc_lite/cpu/cp0_reg/cause_ip~hex \
    soc_lite/cpu/cp0_reg/cp0_write_cause~bin \
    soc_lite/cpu/cp0_reg/status_ie~bin \
    soc_lite/cpu/cp0_reg/status_im~hex \
    soc_lite/cpu/cp0_reg/status_exl~bin \
    soc_lite/cpu/cp0_reg/interrupt_pending~bin \
    soc_lite/cpu/id_stage/ds_interrupt_exception~bin \
    soc_lite/cpu/id_stage/exception_code~hex \
    soc_lite/cpu/trap_commit~bin \
    soc_lite/cpu/trap_code~hex \
    soc_lite/cpu/trap_pc~hex \
    soc_lite/cpu/cp0_reg/epc~hex \
    soc_lite/cpu/eret_commit~bin \
    soc_lite/cpu/pipeline_flush~bin]]
create_profile $output_dir 09_software_irq $soft_irq

puts "LAB9_WAVE_CONFIGS_COMPLETE=1"
