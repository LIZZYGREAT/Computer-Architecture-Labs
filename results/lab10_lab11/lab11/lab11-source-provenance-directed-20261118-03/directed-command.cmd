@echo off
cd /d "D:\Verilog\2025.2\Vivado\bin"
call "D:\Verilog\2025.2\Vivado\bin\vivado.bat" "-mode" "batch" "-source" "C:\Users\lenovo\Desktop\Projects\FPGA\lab\scripts\run_lab11_axi3_directed.tcl" "-log" "C:\Users\lenovo\Desktop\Projects\FPGA\lab\results\lab10_lab11\lab11\lab11-source-provenance-directed-20261118-03\directed-vivado.log" "-journal" "C:\Users\lenovo\Desktop\Projects\FPGA\lab\results\lab10_lab11\lab11\lab11-source-provenance-directed-20261118-03\directed-vivado.jou" "-tclargs" "C:\Users\lenovo\Desktop\Projects\FPGA\lab\results\lab10_lab11\lab11\lab11-source-provenance-directed-20261118-03\project\lab11_axi3_directed.xpr" "C:\Users\lenovo\Desktop\Projects\FPGA\lab\results\lab10_lab11\lab11\lab11-source-provenance-directed-20261118-03"
exit /b %ERRORLEVEL%
