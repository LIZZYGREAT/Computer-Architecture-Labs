[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('lab3', 'lab4', 'lab6', 'lab7')]
    [string]$Case,
    [string]$TraceOutput,
    [string]$VivadoBin = 'D:\Verilog\2025.2\Vivado\bin',
    [long]$MaxSimulationNs = 0,
    [int]$TimeoutSeconds = 1800
)

$ErrorActionPreference = 'Stop'
$labRoot = Split-Path -Parent $PSScriptRoot
$caseConfigPath = Join-Path $PSScriptRoot 'cases.json'
$allCaseSettings = Get-Content -LiteralPath $caseConfigPath -Raw | ConvertFrom-Json
$caseSettings = $allCaseSettings.$Case
if (-not $caseSettings) { throw "Case configuration is missing for $Case." }
if ($MaxSimulationNs -eq 0) { $MaxSimulationNs = [long]$caseSettings.DefaultMaxSimulationNs }
if ($MaxSimulationNs -le 0 -or $TimeoutSeconds -le 0) {
    throw 'Simulation time and host timeout must be positive.'
}

$stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
$runId = "reference-$Case-$stamp"
$resultDir = Join-Path (Join-Path $labRoot $caseSettings.ResultRoot) $runId
New-Item -ItemType Directory -Path $resultDir -Force | Out-Null
$referenceSourceRoot = Join-Path $labRoot 'lab3\CPU_CDE\cpu132_gettrace'
$workRoot = Join-Path $labRoot "results\lab6_lab7\reference-work\$runId\CPU_CDE\cpu132_gettrace"
$xpr = Join-Path $workRoot 'run_vivado\cpu132_gettrace\cpu132_gettrace.xpr'
$coe = Join-Path $labRoot $caseSettings.InstructionCoe
$mif = Join-Path $labRoot $caseSettings.InstructionMif
$instRamXci = Join-Path $labRoot 'lab3\CPU_CDE\mycpu_verify\rtl\xilinx_ip\inst_ram\inst_ram.xci'
$imageChecker = Join-Path $PSScriptRoot 'check_instruction_image.py'
$imageReport = Join-Path $resultDir 'instruction-image-check.txt'
$imageOutput = & python $imageChecker --coe $coe --mif $mif --xci $instRamXci 2>&1
$imageCode = $LASTEXITCODE
$imageOutput | Set-Content -LiteralPath $imageReport -Encoding UTF8
if ($imageCode -ne 0 -or -not ($imageOutput -match 'IMAGE_MATCH=PASS')) {
    Write-Output "ENVIRONMENT_ERROR: instruction COE/MIF consistency check failed. See $imageReport."
    Write-Output "LOG=$resultDir"
    exit 2
}

if (-not $TraceOutput) {
    $traceOutput = Join-Path $labRoot $caseSettings.ReferenceTrace
} elseif ([IO.Path]::IsPathRooted($TraceOutput)) {
    $traceOutput = $TraceOutput
} else {
    $traceOutput = Join-Path $labRoot $TraceOutput
}
New-Item -ItemType Directory -Path (Split-Path -Parent $traceOutput) -Force | Out-Null

# Create a minimal independent reference project. Its XCI keeps the original
# relative COE path, which resolves to the selected case image in this copy.
$cpuCdeRoot = Split-Path -Parent $workRoot
New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
foreach ($relativeDirectory in @('rtl', 'testbench', 'run_vivado')) {
    $sourceDirectory = Join-Path $referenceSourceRoot $relativeDirectory
    if (-not (Test-Path -LiteralPath $sourceDirectory)) {
        throw "Reference source directory is missing: $sourceDirectory"
    }
    Copy-Item -LiteralPath $sourceDirectory -Destination $workRoot -Recurse
}
$referenceObj = Join-Path $cpuCdeRoot 'soft\func_lab3\obj'
New-Item -ItemType Directory -Path $referenceObj -Force | Out-Null
Copy-Item -LiteralPath $coe -Destination (Join-Path $referenceObj 'inst_ram.coe')
Copy-Item -LiteralPath $mif -Destination (Join-Path $referenceObj 'inst_ram.mif')
if (-not (Test-Path -LiteralPath $xpr)) { throw "Copied reference project was not found: $xpr" }

$vivado = Join-Path $VivadoBin 'vivado.bat'
if (-not (Test-Path -LiteralPath $vivado)) { throw "Vivado batch launcher was not found: $vivado" }
$vivadoBinFull = (Resolve-Path -LiteralPath $VivadoBin).Path
$dutRoot = Join-Path $labRoot 'lab3\CPU_CDE\mycpu_verify'
$instRamSim = Join-Path $dutRoot 'rtl\xilinx_ip\inst_ram\sim\inst_ram.v'
$dataRamSim = Join-Path $dutRoot 'rtl\xilinx_ip\data_ram\sim\data_ram.v'
$vivadoRoot = Split-Path -Parent $vivadoBinFull
$blkMemGenSim = Join-Path $vivadoRoot 'data\ip\xilinx\blk_mem_gen_v8_4\simulation\blk_mem_gen_v8_4.v'
foreach ($file in @($instRamSim, $dataRamSim, $blkMemGenSim)) {
    if (-not (Test-Path -LiteralPath $file)) { throw "Reference simulation model is missing: $file" }
}

$tclFile = Join-Path $PSScriptRoot 'generate_reference_trace.tcl'
$vivadoLog = Join-Path $resultDir 'reference-vivado.log'
$journal = Join-Path $resultDir 'reference-vivado.jou'
$stdout = Join-Path $resultDir 'reference-console.log'
$stderr = Join-Path $resultDir 'reference-console.err'
$commandFile = Join-Path $resultDir 'reference-command.cmd'
$tclArgs = @($xpr, $coe, $mif, $traceOutput, $resultDir, $instRamSim, $dataRamSim,
    $blkMemGenSim, [string]$caseSettings.ExpectedFunctionalPoints, [string]$MaxSimulationNs)
$allArgs = @('-mode', 'batch', '-source', $tclFile, '-log', $vivadoLog,
    '-journal', $journal, '-tclargs') + $tclArgs
$quotedArgs = ($allArgs | ForEach-Object { '"' + ([string]$_).Replace('"', '""') + '"' }) -join ' '
@('@echo off', "cd /d `"$vivadoBinFull`"", "call `"$vivado`" $quotedArgs", 'exit /b %ERRORLEVEL%') |
    Set-Content -LiteralPath $commandFile -Encoding ASCII

$process = Start-Process -FilePath (Join-Path $env:WINDIR 'System32\cmd.exe') `
    -ArgumentList @('/d', '/c', ('"' + $commandFile + '"')) `
    -WorkingDirectory $vivadoBinFull -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput $stdout -RedirectStandardError $stderr
if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
    try { $process.Kill($true) } catch { }
    "STATUS=ENVIRONMENT_ERROR`nREASON=reference simulation exceeded host timeout $TimeoutSeconds seconds" |
        Set-Content -LiteralPath (Join-Path $resultDir 'reference-status.txt') -Encoding UTF8
    Write-Output "ENVIRONMENT_ERROR: reference simulation exceeded $TimeoutSeconds seconds. See $resultDir."
    exit 2
}
$process.WaitForExit()
$process.Refresh()
$hostProcessExitCode = if ($process.HasExited -and $null -ne $process.ExitCode) {
    [string]$process.ExitCode
} else {
    'NOT_REPORTED'
}
if (Test-Path -LiteralPath $vivadoLog) {
    Get-Content -LiteralPath $vivadoLog -Raw | Set-Content -LiteralPath (Join-Path $resultDir 'reference-vivado-copy.log') -Encoding UTF8
}

$resultFile = Join-Path $resultDir 'reference-result.txt'
$resultText = if (Test-Path -LiteralPath $resultFile) { Get-Content -LiteralPath $resultFile -Raw } else { '' }
"HOST_PROCESS_EXIT_CODE=$hostProcessExitCode" |
    Set-Content -LiteralPath (Join-Path $resultDir 'reference-host-process.txt') -Encoding UTF8
if ($resultText -notmatch '(?m)^STATUS=PASS\r?$') {
    Write-Output "ENVIRONMENT_ERROR: independent reference generation failed. See $resultDir."
    Write-Output "LOG=$resultDir"
    exit 1
}

$traceHash = (Get-FileHash -LiteralPath $traceOutput -Algorithm SHA256).Hash
$commit = (git -C $labRoot rev-parse HEAD 2>$null | Select-Object -First 1)
@("CASE=$Case", "SOURCE_COMMIT=$commit", "TRACE_OUTPUT=$traceOutput", "TRACE_SHA256=$traceHash",
    "EXPECTED_FUNCTIONAL_POINTS=$($caseSettings.ExpectedFunctionalPoints)", "MAX_SIMULATION_NS=$MaxSimulationNs",
    "TIMEOUT_SECONDS=$TimeoutSeconds", "HOST_PROCESS_EXIT_CODE=$hostProcessExitCode",
    "REFERENCE_WORK_TREE=$workRoot") |
    Set-Content -LiteralPath (Join-Path $resultDir 'reference-manifest.txt') -Encoding UTF8
Write-Output "STATUS=PASS"
Write-Output "CASE=$Case"
Write-Output "TRACE=$traceOutput SHA256=$traceHash"
Write-Output "VIVADO_PROCESS_EXIT_CODE=$hostProcessExitCode (TCL_STATUS=$($resultText -match '(?m)^STATUS=PASS\r?$'))"
Write-Output "LOG=$resultDir"
