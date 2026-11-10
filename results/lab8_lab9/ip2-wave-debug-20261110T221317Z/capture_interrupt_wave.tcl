open_vcd C:/Users/lenovo/Desktop/Projects/FPGA/lab/results/lab8_lab9/ip2-wave-debug-20261110T221317Z/interrupt-ip2-capture.vcd
log_vcd /interrupt_tb/clk
log_vcd /interrupt_tb/resetn
log_vcd /interrupt_tb/hw_int
log_vcd /interrupt_tb/dut/cp0_reg/cause_ip
log_vcd /interrupt_tb/dut/cp0_reg/status_ie
log_vcd /interrupt_tb/dut/cp0_reg/status_im
log_vcd /interrupt_tb/dut/cp0_reg/status_exl
log_vcd /interrupt_tb/dut/cp0_reg/interrupt_pending
log_vcd /interrupt_tb/dut/exe_stage/es_pc
log_vcd /interrupt_tb/dut/exe_stage/es_valid
log_vcd /interrupt_tb/dut/mem_stage/ms_pc
log_vcd /interrupt_tb/dut/mem_stage/ms_exception_valid
log_vcd /interrupt_tb/dut/mem_stage/ms_exception_code
log_vcd /interrupt_tb/dut/trap_commit
log_vcd /interrupt_tb/dut/trap_code
log_vcd /interrupt_tb/dut/trap_pc
log_vcd /interrupt_tb/dut/cp0_epc
log_vcd /interrupt_tb/dut/eret_commit
log_vcd /interrupt_tb/dut/pipeline_flush
log_vcd /interrupt_tb/debug_wb_pc
log_vcd /interrupt_tb/debug_wb_rf_wen
log_vcd /interrupt_tb/data_sram_wen
log_wave -r /
run 100us
close_vcd
