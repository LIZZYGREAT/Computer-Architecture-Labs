[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^r3l19-synthesis-[0-9]{2}$')]
    [string]$RunId,

    [string]$VivadoBin = 'D:\Verilog\2025.2\Vivado\bin'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$runDir = Join-Path $repoRoot (Join-Path 'results\lab13-lab19\lab19' $RunId)
$vivado = Join-Path $VivadoBin 'vivado.bat'
$tclScript = Join-Path $PSScriptRoot 'run_lab19_synthesis.tcl'
$inputCoe = Join-Path $repoRoot 'lab19\cache_func\obj\inst_ram.coe'

if (-not (Test-Path -LiteralPath $vivado -PathType Leaf)) { throw "Vivado was not found: $vivado" }
if (-not (Test-Path -LiteralPath $inputCoe -PathType Leaf)) { throw "Synthesis COE was not found: $inputCoe" }
if (Test-Path -LiteralPath $runDir) { throw "Run directory already exists; refusing to overwrite: $runDir" }

$branch = (& git -C $repoRoot branch --show-current).Trim()
if ($branch -ne 'lab13-lab19') { throw "Expected branch lab13-lab19; found $branch" }
$trackedDiff = & git -C $repoRoot diff --quiet HEAD --
if ($LASTEXITCODE -ne 0) { throw 'Tracked worktree changes must be committed before the synthesis run.' }
$stagedDiff = & git -C $repoRoot diff --cached --quiet
if ($LASTEXITCODE -ne 0) { throw 'Staged worktree changes must be committed before the synthesis run.' }

New-Item -ItemType Directory -Path $runDir | Out-Null
$arguments = @(
    '-mode', 'batch',
    '-log', (Join-Path $runDir 'vivado.log'),
    '-journal', (Join-Path $runDir 'vivado.jou'),
    '-source', $tclScript,
    '-tclargs', $repoRoot, $runDir
)
$commandLines = @(
    "RUN_ID=$RunId",
    'CASE=lab19',
    'SUITE=synthesis',
    "GIT_HEAD=$((& git -C $repoRoot rev-parse HEAD).Trim())",
    "VIVADO=$vivado",
    "TCL_SCRIPT=$tclScript",
    "INPUT_COE=$inputCoe",
    'MODE=batch',
    'ARGUMENTS_BEGIN'
)
for ($index = 0; $index -lt $arguments.Count; $index++) { $commandLines += "ARG[$index]=$($arguments[$index])" }
$commandLines += 'ARGUMENTS_END'
[IO.File]::WriteAllLines((Join-Path $runDir 'command.txt'), $commandLines, [Text.UTF8Encoding]::new($false))

$preflight = @(
    'INPUT_CHECK_STATUS=PASS',
    'VIVADO_CHECK_STATUS=PASS',
    "INPUT_COE=$inputCoe",
    "RUN_SCRIPT=$tclScript",
    "BRANCH=$branch",
    "GIT_HEAD=$((& git -C $repoRoot rev-parse HEAD).Trim())",
    'TRACKED_WORKTREE_STATUS=CLEAN',
    'PROJECT_PREFLIGHT_STATUS=PENDING'
)
[IO.File]::WriteAllLines((Join-Path $runDir 'preflight.txt'), $preflight, [Text.UTF8Encoding]::new($false))

$stdoutPath = Join-Path $runDir 'launcher.log'
$stderrPath = Join-Path $runDir 'launcher.stderr.log'
$process = Start-Process -FilePath $vivado -ArgumentList $arguments `
    -WorkingDirectory $VivadoBin -Wait -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath

$manifestArgs = @(
    (Join-Path $PSScriptRoot 'capture_run_manifest.py'),
    '--repo-root', $repoRoot,
    '--run-dir', $runDir,
    '--input-file', $inputCoe
)
& python @manifestArgs
$manifestExit = $LASTEXITCODE
$sourceIntegrity = 'FAIL'
if ($manifestExit -eq 0 -and (Select-String -LiteralPath (Join-Path $runDir 'source-integrity.txt') -Pattern '^SOURCE_INTEGRITY=PASS$' -Quiet)) {
    $sourceIntegrity = 'PASS'
}

$logText = if (Test-Path -LiteralPath (Join-Path $runDir 'vivado.log')) { Get-Content -LiteralPath (Join-Path $runDir 'vivado.log') -Raw } else { '' }
$synthStatus = 'FAIL'
if ($logText -match '(?m)^SYNTH_STATUS=([^\r\n]+)$' -and $Matches[1] -like '*Complete*' -and
    $logText -match '(?m)^SYNTH_PROGRESS=100%$') { $synthStatus = 'PASS' }
$timingStatus = 'TIMING_NOT_CLOSED'
$preflightStatus = if ($process.ExitCode -eq 0 -and $synthStatus -eq 'PASS') { 'PASS' } else { 'FAIL' }
$preflight[-1] = "PROJECT_PREFLIGHT_STATUS=$preflightStatus"
[IO.File]::WriteAllLines((Join-Path $runDir 'preflight.txt'), $preflight, [Text.UTF8Encoding]::new($false))

$status = if ($process.ExitCode -eq 0 -and $synthStatus -eq 'PASS' -and $sourceIntegrity -eq 'PASS') { 'PASS' } else { 'FAIL' }
$result = @(
    "RUN_ID=$RunId",
    'CASE=lab19',
    'SUITE=synthesis',
    "STATUS=$status",
    "SYNTHESIS_STATUS=$synthStatus",
    "TIMING_STATUS=$timingStatus",
    'PLACE_ROUTE_STATUS=NOT_RUN',
    "VIVADO_EXIT_CODE=$($process.ExitCode)",
    "SOURCE_INTEGRITY=$sourceIntegrity",
    'PROGRAM_IMAGE=lab19/cache_func/obj/inst_ram.coe',
    "GIT_HEAD=$((& git -C $repoRoot rev-parse HEAD).Trim())",
    'REPORT_UTILIZATION=utilization.rpt',
    'REPORT_TIMING=timing-summary.rpt',
    'REPORT_CHECK_TIMING=check-timing.rpt',
    'REPORT_CLOCKS=clocks.rpt',
    'REPORT_IP_STATUS=ip-status.rpt',
    'EXTERNAL_IO_DELAYS=NOT_CONSTRAINED_UNLESS_REPORTS_PROVE_OTHERWISE'
)
[IO.File]::WriteAllLines((Join-Path $runDir 'result.txt'), $result, [Text.UTF8Encoding]::new($false))

& python (Join-Path $PSScriptRoot 'summarize_synthesis.py') --run-dir $runDir --repo-root $repoRoot --vivado-exit-code $process.ExitCode
if ($LASTEXITCODE -ne 0) { throw "Synthesis summary found a failed acceptance gate; inspect $runDir" }
if ($process.ExitCode -ne 0 -or $status -ne 'PASS') {
    throw "Lab19 synthesis run failed; inspect $runDir"
}
