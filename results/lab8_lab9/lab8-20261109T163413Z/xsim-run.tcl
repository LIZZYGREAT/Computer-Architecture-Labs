file copy -force C:/Users/lenovo/Desktop/Projects/FPGA/lab/lab8/func_lab8/obj/inst_ram.mif C:/Users/lenovo/Desktop/Projects/FPGA/lab/lab3/CPU_CDE/mycpu_verify/run_vivado/mycpu_prj1/mycpu_prj1.sim/sim_1/behav/xsim/inst_ram.mif
puts STAGED_INSTRUCTION_MIF=C:/Users/lenovo/Desktop/Projects/FPGA/lab/lab3/CPU_CDE/mycpu_verify/run_vivado/mycpu_prj1/mycpu_prj1.sim/sim_1/behav/xsim/inst_ram.mif
log_wave -r /
run 100000000 ns
quit
