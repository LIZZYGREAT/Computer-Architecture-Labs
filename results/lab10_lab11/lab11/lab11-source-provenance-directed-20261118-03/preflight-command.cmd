@echo off
cd /d "D:\Verilog\2025.2\Vivado\bin"
call "D:\Verilog\2025.2\Vivado\bin\vivado.bat" "-mode" "batch" "-source" "C:\Users\lenovo\Desktop\Projects\FPGA\lab\scripts\check_bus_project.tcl" "-log" "C:\Users\lenovo\Desktop\Projects\FPGA\lab\results\lab10_lab11\lab11\lab11-source-provenance-directed-20261118-03\preflight-vivado.log" "-journal" "C:\Users\lenovo\Desktop\Projects\FPGA\lab\results\lab10_lab11\lab11\lab11-source-provenance-directed-20261118-03\preflight-vivado.jou" "-tclargs" "lab11" "C:\Users\lenovo\Desktop\Projects\FPGA\lab\lab11\CPU_CDE_AXI\mycpu_axi_verify\run_vivado\mycpu_prj1\mycpu_lab11_bus.xpr" "C:\Users\lenovo\Desktop\Projects\FPGA\lab\results\lab10_lab11\lab11\lab11-source-provenance-directed-20261118-03\preflight"
exit /b %ERRORLEVEL%
