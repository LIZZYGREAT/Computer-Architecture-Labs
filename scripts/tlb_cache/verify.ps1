[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('lab13', 'lab14', 'lab16', 'lab17', 'lab18')]
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
if ($branch -ne 'lab12-lab19') {
    throw "Run on lab12-lab19; current worktree branch is '$branch'."
}

$runDir = Join-Path $repoRoot (Join-Path 'results\lab13_19' (Join-Path $Case $RunId))
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
        if ($Suite -eq 'directed') {
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
            throw "Lab18 supports Suite 'directed', 'arbitration', 'mem-exception', or 'functional'."
        }
        if ($CaptureWaveform -and $Suite -ne 'directed') {
            Write-Host 'Lab18 functional runs retain the compact DCache directed waveform.'
        }
    }
}

$stdoutPath = Join-Path $runDir 'launcher.stdout.log'
$stderrPath = Join-Path $runDir 'launcher.stderr.log'
$arguments = @('-mode', 'batch', '-source', $tclScript, '-tclargs') + $tclArgs
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
if ($process.ExitCode -ne 0) {
    $preflightLines = @(Get-Content -LiteralPath $preflightPath | ForEach-Object {
        if ($_ -eq 'PROJECT_PREFLIGHT_STATUS=PENDING') { 'PROJECT_PREFLIGHT_STATUS=FAIL' } else { $_ }
    })
    $preflightLines += "VIVADO_EXIT_CODE=$($process.ExitCode)"
    [IO.File]::WriteAllLines($preflightPath, $preflightLines, [Text.UTF8Encoding]::new($false))
    throw "Vivado exited with code $($process.ExitCode). Inspect $stdoutPath and the run directory."
}

$resultPath = Join-Path $runDir 'result.txt'
if (-not (Test-Path -LiteralPath $resultPath) -or
    -not (Select-String -LiteralPath $resultPath -Pattern '^STATUS=PASS$' -Quiet)) {
    $preflightLines = @(Get-Content -LiteralPath $preflightPath | ForEach-Object {
        if ($_ -eq 'PROJECT_PREFLIGHT_STATUS=PENDING') { 'PROJECT_PREFLIGHT_STATUS=FAIL' } else { $_ }
    })
    $preflightLines += 'RESULT_STATUS=NOT_PASS'
    [IO.File]::WriteAllLines($preflightPath, $preflightLines, [Text.UTF8Encoding]::new($false))
    throw "Vivado did not produce a PASS result file: $resultPath"
}

$preflightLines = @(Get-Content -LiteralPath $preflightPath | ForEach-Object {
    if ($_ -eq 'PROJECT_PREFLIGHT_STATUS=PENDING') { 'PROJECT_PREFLIGHT_STATUS=PASS' } else { $_ }
})
$projectLine = (Select-String -LiteralPath $resultPath -Pattern '^PROJECT_XPR=' | Select-Object -First 1).Line
if ($projectLine) { $preflightLines += $projectLine }
[IO.File]::WriteAllLines($preflightPath, $preflightLines, [Text.UTF8Encoding]::new($false))

if (Test-Path -LiteralPath $stdoutPath) {
    $launcherText = Get-Content -LiteralPath $stdoutPath -Raw
    if ($launcherText -match 'Simulation CPU Usage:\s*([0-9]+) ms') {
        Add-Content -LiteralPath $resultPath -Value "SIMULATOR_CPU_MS=$($Matches[1])" -Encoding utf8
    }
    Remove-Item -LiteralPath $stdoutPath
}

$manifestArgs = @((Join-Path $PSScriptRoot 'capture_run_manifest.py'), '--repo-root', $repoRoot, '--run-dir', $runDir)
foreach ($inputFile in $inputFiles) {
    $manifestArgs += @('--input-file', $inputFile)
}
& python @manifestArgs
if ($LASTEXITCODE -ne 0) {
    throw "Source/input integrity capture failed; inspect $runDir\source-integrity.txt"
}
if ((Test-Path -LiteralPath $stderrPath) -and (Get-Item -LiteralPath $stderrPath).Length -eq 0) {
    Remove-Item -LiteralPath $stderrPath
}

Write-Host "RUN_ID=$RunId"
Write-Host "RUN_DIR=$runDir"
Get-Content -LiteralPath $resultPath
