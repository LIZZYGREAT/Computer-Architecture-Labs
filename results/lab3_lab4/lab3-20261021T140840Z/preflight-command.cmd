@echo off
cd /d "D:\Verilog\2025.2\Vivado\bin"
call "D:\Verilog\2025.2\Vivado\bin\vivado.bat" "-mode" "batch" "-source" "C:\Users\lenovo\Desktop\Projects\FPGA\lab\scripts\check_project.tcl" "-log" "C:\Users\lenovo\Desktop\Projects\FPGA\lab\results\lab3_lab4\lab3-20261021T140840Z\preflight-vivado.log" "-journal" "C:\Users\lenovo\Desktop\Projects\FPGA\lab\results\lab3_lab4\lab3-20261021T140840Z\preflight-vivado.jou" "-tclargs" "C:\Users\lenovo\Desktop\Projects\FPGA\lab\lab3\CPU_CDE\mycpu_verify\run_vivado\mycpu_prj1\mycpu_prj1.xpr" "C:\Users\lenovo\Desktop\Projects\FPGA\lab\results\lab3_lab4\lab3-20261021T140840Z"
exit /b %ERRORLEVEL%
