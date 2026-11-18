[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('lab13', 'lab14', 'lab16', 'lab17', 'lab18', 'lab19')]
    [string]$Case,

    [Parameter(Mandatory = $true)]
    [string]$Suite,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,80}$')]
    [string]$RunId,

    [switch]$CaptureWaveform,

    [string]$VivadoBin = 'D:\Verilog\2025.2\Vivado\bin'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$branch = (& git -C $repoRoot branch --show-current).Trim()
$allowedBranches = @('lab12-lab19', 'lab13-lab19')
if ($branch -notin $allowedBranches) {
    throw "Run on lab12-lab19 or lab13-lab19; current worktree branch is '$branch'."
}

$runDir = Join-Path $repoRoot (Join-Path 'results\lab13-lab19' (Join-Path $Case $RunId))
if (Test-Path -LiteralPath $runDir) {
    throw "Run ID already exists; choose a fresh RunId: $runDir"
}
New-Item -ItemType Directory -Path $runDir | Out-Null

$vivado = Join-Path $VivadoBin 'vivado.bat'
if (-not (Test-Path -LiteralPath $vivado)) {
    throw "Vivado batch launcher not found: $vivado"
}

$tclScript = $null
$tclArgs = @()
$inputFiles = @()
switch ($Case) {
    'lab13' {
        if ($Suite -ne 'unit') { throw "Lab13 supports Suite 'unit'." }
        $tclScript = Join-Path $PSScriptRoot 'run_unit.tcl'
        $tclArgs = @('lab13', 'official', $repoRoot, $runDir)
    }
    'lab14' {
        if ($Suite -eq 'directed') {
            $tclScript = Join-Path $PSScriptRoot 'run_unit.tcl'
            $tclArgs = @('lab14_translate', 'directed', $repoRoot, $runDir)
        } elseif ($Suite -eq 'functional') {
            $tclScript = Join-Path $PSScriptRoot 'run_soc.tcl'
            $tclArgs = @($repoRoot, $runDir, 'lab14')
            $inputFiles = @((Join-Path $repoRoot 'lab14/tlb_func/obj/inst_ram.coe'))
        } else {
            throw "Lab14 supports Suite 'directed' or 'functional'."
        }
    }
    'lab16' {
        if ($Suite -eq 'unit') {
            $tclScript = Join-Path $PSScriptRoot 'run_unit.tcl'
            $tclArgs = @('lab16', 'official', $repoRoot, $runDir)
        } elseif ($Suite -eq 'directed') {
            $tclScript = Join-Path $PSScriptRoot 'run_unit.tcl'
            $tclArgs = @('lab16', 'directed', $repoRoot, $runDir)
        } else {
            throw "Lab16 supports Suite 'unit' or 'directed'."
        }
    }
    'lab17' {
        $inputFiles = @((Join-Path $repoRoot 'lab17/func_all94/obj/inst_ram.coe'))
        if ($Suite -eq 'directed') {
            $tclScript = Join-Path $PSScriptRoot 'run_unit.tcl'
            $tclArgs = @('lab17', 'directed', $repoRoot, $runDir)
        } elseif ($Suite -eq 'functional') {
            $tclScript = Join-Path $PSScriptRoot 'run_soc.tcl'
            $tclArgs = @($repoRoot, $runDir, 'lab17')
        } elseif ($Suite -eq 'baseline') {
            $tclScript = Join-Path $PSScriptRoot 'run_soc.tcl'
            $tclArgs = @($repoRoot, $runDir, 'lab17_baseline')
        } else {
            throw "Lab17 supports Suite 'directed', 'functional', or 'baseline'."
        }
        if ($CaptureWaveform -and $Suite -ne 'directed') {
            Write-Host 'Lab17 full functional runs use the ordered transaction log; the compact directed run retains the waveform.'
        }
    }
    'lab18' {
        $inputFiles = @()
        if ($Suite -eq 'fault') {
            $tclScript = Join-Path $PSScriptRoot 'run_unit.tcl'
            $tclArgs = @('lab18_fault', 'directed', $repoRoot, $runDir)
        } elseif ($Suite -eq 'directed') {
            $tclScript = Join-Path $PSScriptRoot 'run_unit.tcl'
            $tclArgs = @('lab18', 'directed', $repoRoot, $runDir)
        } elseif ($Suite -eq 'arbitration') {
            $tclScript = Join-Path $PSScriptRoot 'run_unit.tcl'
            $tclArgs = @('lab18_arb', 'directed', $repoRoot, $runDir)
        } elseif ($Suite -eq 'mem-exception') {
            $tclScript = Join-Path $PSScriptRoot 'run_unit.tcl'
            $tclArgs = @('lab18_mem', 'directed', $repoRoot, $runDir)
        } elseif ($Suite -eq 'functional') {
            $tclScript = Join-Path $PSScriptRoot 'run_soc.tcl'
            $tclArgs = @($repoRoot, $runDir, 'lab18')
            $inputFiles = @((Join-Path $repoRoot 'lab17/func_all94/obj/inst_ram.coe'))
        } else {
            throw "Lab18 supports Suite 'fault', 'directed', 'arbitration', 'mem-exception', or 'functional'."
        }
        if ($CaptureWaveform -and $Suite -ne 'directed') {
            Write-Host 'Lab18 functional runs retain the compact DCache directed waveform.'
        }
    }
    'lab19' {
        if ($Suite -eq 'tlb-replay') {
            $tclScript = Join-Path $PSScriptRoot 'run_unit.tcl'
            $tclArgs = @('lab19_tlb_redirect', 'directed', $repoRoot, $runDir)
        } elseif ($Suite -eq 'redirect') {
            $tclScript = Join-Path $PSScriptRoot 'run_unit.tcl'
            $tclArgs = @('lab19_if_redirect', 'directed', $repoRoot, $runDir)
        } elseif ($Suite -eq 'index-contract') {
            $tclScript = Join-Path $PSScriptRoot 'run_unit.tcl'
            $tclArgs = @('lab19_index_contract', 'directed', $repoRoot, $runDir)
        } elseif ($Suite -eq 'writeback-scoreboard') {
            $tclScript = Join-Path $PSScriptRoot 'run_unit.tcl'
            $tclArgs = @('lab19_writeback_scoreboard', 'directed', $repoRoot, $runDir)
        } elseif ($Suite -eq 'directed') {
            $tclScript = Join-Path $PSScriptRoot 'run_unit.tcl'
            $tclArgs = @('lab19_maint', 'directed', $repoRoot, $runDir)
        } elseif ($Suite -eq 'cache') {
            $tclScript = Join-Path $PSScriptRoot 'run_soc.tcl'
            $tclArgs = @($repoRoot, $runDir, 'lab19')
            $inputFiles = @((Join-Path $repoRoot 'lab19/cache_func/obj/inst_ram.coe'))
        } elseif ($Suite -eq 'dhrystone') {
            $tclScript = Join-Path $PSScriptRoot 'run_soc.tcl'
            $tclArgs = @($repoRoot, $runDir, 'dhrystone')
            $inputFiles = @((Join-Path $repoRoot 'lab19/perf_func/obj/dhrystone/axi_ram.coe'))
        } elseif ($Suite -eq 'coremark') {
            $tclScript = Join-Path $PSScriptRoot 'run_soc.tcl'
            $tclArgs = @($repoRoot, $runDir, 'coremark')
            $inputFiles = @((Join-Path $repoRoot 'lab19/perf_func/obj/coremark/axi_ram.coe'))
        } else {
            throw "Lab19 supports Suite 'tlb-replay', 'redirect', 'index-contract', 'writeback-scoreboard', 'directed', 'cache', 'dhrystone', or 'coremark'."
        }
        if ($CaptureWaveform -and $Suite -ne 'cache') {
            Write-Host 'Lab19 performance images are long runs; waveform capture is retained for the compact seven-test CACHE run only.'
        }
    }
}

$stdoutPath = Join-Path $runDir 'launcher.stdout.log'
$stderrPath = Join-Path $runDir 'launcher.stderr.log'
$arguments = @(
    '-mode', 'batch',
    '-log', (Join-Path $runDir 'vivado.log'),
    '-journal', (Join-Path $runDir 'vivado.jou'),
    '-source', $tclScript,
    '-tclargs'
) + $tclArgs
$commandLines = @(
    "RUN_ID=$RunId",
    "CASE=$Case",
    "SUITE=$Suite",
    "VIVADO=$vivado",
    "TCL_SCRIPT=$tclScript",
    'ARGUMENTS_BEGIN'
)
for ($index = 0; $index -lt $arguments.Count; $index++) {
    $commandLines += "ARG[$index]=$($arguments[$index])"
}
$commandLines += 'ARGUMENTS_END'
[IO.File]::WriteAllLines((Join-Path $runDir 'command.txt'), $commandLines, [Text.UTF8Encoding]::new($false))

$preflightLines = @('INPUT_CHECK_STATUS=PASS')
$preflightLines += 'VIVADO_CHECK_STATUS=PASS'
for ($index = 0; $index -lt $inputFiles.Count; $index++) {
    $inputPath = $inputFiles[$index]
    if (-not (Test-Path -LiteralPath $inputPath -PathType Leaf)) {
        $preflightLines[0] = 'INPUT_CHECK_STATUS=FAIL'
        $preflightLines += "MISSING_INPUT=$inputPath"
    } else {
        $preflightLines += "INPUT[$index]=$inputPath"
    }
}
$preflightLines += 'PROJECT_PREFLIGHT_STATUS=PENDING'
$preflightPath = Join-Path $runDir 'preflight.txt'
[IO.File]::WriteAllLines($preflightPath, $preflightLines, [Text.UTF8Encoding]::new($false))
if ($preflightLines[0] -ne 'INPUT_CHECK_STATUS=PASS') {
    throw "Input preflight failed; inspect $preflightPath."
}

$process = Start-Process -FilePath $vivado -ArgumentList $arguments `
    -WorkingDirectory $VivadoBin -Wait -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
$resultPath = Join-Path $runDir 'result.txt'
$simulationResultPath = Join-Path $runDir 'sim-result.txt'
if (Test-Path -LiteralPath $resultPath) {
    Move-Item -LiteralPath $resultPath -Destination $simulationResultPath
} else {
    [IO.File]::WriteAllLines($simulationResultPath, @(
        "RUN_ID=$RunId", "CASE=$Case", "SUITE=$Suite", 'STATUS=INCOMPLETE',
        "VIVADO_EXIT_CODE=$($process.ExitCode)", 'REASON=SIMULATION_RESULT_MISSING'
    ), [Text.UTF8Encoding]::new($false))
}

$simulatorCpuMs = $null
if (Test-Path -LiteralPath $stdoutPath) {
    $launcherText = Get-Content -LiteralPath $stdoutPath -Raw
    if ($launcherText -match 'Simulation CPU Usage:\s*([0-9]+) ms') {
        $simulatorCpuMs = $Matches[1]
    }
}

$rawSimulationPassed = (Test-Path -LiteralPath $simulationResultPath) -and
    (Select-String -LiteralPath $simulationResultPath -Pattern '^STATUS=PASS$' -Quiet)
$projectLine = (Select-String -LiteralPath $simulationResultPath -Pattern '^PROJECT_XPR=' | Select-Object -First 1).Line
$preflightLines = @(Get-Content -LiteralPath $preflightPath | ForEach-Object {
    if ($_ -eq 'PROJECT_PREFLIGHT_STATUS=PENDING') {
        if ($process.ExitCode -eq 0 -and $rawSimulationPassed) { 'PROJECT_PREFLIGHT_STATUS=PASS' }
        else { 'PROJECT_PREFLIGHT_STATUS=FAIL' }
    } else { $_ }
})
if ($projectLine) { $preflightLines += $projectLine }
if ($process.ExitCode -ne 0) { $preflightLines += "VIVADO_EXIT_CODE=$($process.ExitCode)" }
[IO.File]::WriteAllLines($preflightPath, $preflightLines, [Text.UTF8Encoding]::new($false))

$manifestArgs = @((Join-Path $PSScriptRoot 'capture_run_manifest.py'), '--repo-root', $repoRoot, '--run-dir', $runDir)
foreach ($inputFile in $inputFiles) {
    $manifestArgs += @('--input-file', $inputFile)
}
& python @manifestArgs
$sourceIntegrity = 'FAIL'
if ($LASTEXITCODE -eq 0 -and
    (Test-Path -LiteralPath (Join-Path $runDir 'source-integrity.txt')) -and
    (Select-String -LiteralPath (Join-Path $runDir 'source-integrity.txt') -Pattern '^SOURCE_INTEGRITY=PASS$' -Quiet)) {
    $sourceIntegrity = 'PASS'
}

$finalizeArgs = @(
    (Join-Path $PSScriptRoot 'finalize_run_result.py'),
    '--run-dir', $runDir,
    '--simulation-result', $simulationResultPath,
    '--source-integrity', $sourceIntegrity,
    '--vivado-exit-code', [string]$process.ExitCode
)
if ($null -ne $simulatorCpuMs) { $finalizeArgs += @('--simulator-cpu-ms', $simulatorCpuMs) }
& python @finalizeArgs
$finalizeExitCode = $LASTEXITCODE

if ((Test-Path -LiteralPath $stderrPath) -and (Get-Item -LiteralPath $stderrPath).Length -eq 0) {
    Remove-Item -LiteralPath $stderrPath
}
if (Test-Path -LiteralPath $stdoutPath) { Remove-Item -LiteralPath $stdoutPath }
if ($process.ExitCode -ne 0) {
    throw "Vivado exited with code $($process.ExitCode). The authoritative result is INCOMPLETE; inspect the run directory."
}
if (-not $rawSimulationPassed) {
    throw "Vivado did not produce a simulation PASS. The authoritative result is INCOMPLETE; inspect $simulationResultPath."
}
if ($sourceIntegrity -ne 'PASS' -or $finalizeExitCode -ne 0) {
    throw "Source/input integrity capture failed. The authoritative result is INCOMPLETE; inspect $runDir\source-integrity.txt."
}

Write-Host "RUN_ID=$RunId"
Write-Host "RUN_DIR=$runDir"
Get-Content -LiteralPath (Join-Path $runDir 'result.txt')
