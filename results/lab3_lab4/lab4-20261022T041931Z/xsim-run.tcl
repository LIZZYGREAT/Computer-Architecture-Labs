file copy -force C:/Users/lenovo/Desktop/Projects/FPGA/lab/results/lab3_lab4/hazard-directed/image/hazard_inst_ram.mif C:/Users/lenovo/Desktop/Projects/FPGA/lab/lab3/CPU_CDE/mycpu_verify/run_vivado/mycpu_prj1/mycpu_prj1.sim/sim_1/behav/xsim/inst_ram.mif
puts STAGED_INSTRUCTION_MIF=C:/Users/lenovo/Desktop/Projects/FPGA/lab/lab3/CPU_CDE/mycpu_verify/run_vivado/mycpu_prj1/mycpu_prj1.sim/sim_1/behav/xsim/inst_ram.mif
log_wave -r /tb_top
run 5000000 ns
quit
