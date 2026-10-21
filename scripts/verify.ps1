[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('lab3', 'lab4', 'lab6', 'lab7')]
    [string]$Case,
    [ValidateSet('blocking', 'forwarding')]
    [string]$PipelineMode = 'forwarding',
    [string]$ReferenceTrace,
    [string]$InstMif,
    [int]$ExpectedPointOverride = -1,
    [string]$Xpr,
    [string]$VivadoBin = 'D:\Verilog\2025.2\Vivado\bin',
    [long]$MaxSimulationNs = 0,
    [int]$TimeoutSeconds = 1800,
    [switch]$HazardDirected,
    [switch]$CaptureWaveform,
    [switch]$PreflightOnly
)

$ErrorActionPreference = 'Stop'
$labRoot = Split-Path -Parent $PSScriptRoot
$caseConfigPath = Join-Path $PSScriptRoot 'cases.json'
if (-not (Test-Path -LiteralPath $caseConfigPath)) {
    Write-Output "ENVIRONMENT_ERROR: case configuration is missing: $caseConfigPath"
    exit 2
}
$allCaseSettings = Get-Content -LiteralPath $caseConfigPath -Raw | ConvertFrom-Json
$caseSettings = $allCaseSettings.$Case
if (-not $caseSettings) {
    Write-Output "ENVIRONMENT_ERROR: case configuration is missing for $Case."
    exit 2
}
if ($MaxSimulationNs -eq 0) { $MaxSimulationNs = [long]$caseSettings.DefaultMaxSimulationNs }
if ($MaxSimulationNs -le 0 -or $TimeoutSeconds -le 0 -or $ExpectedPointOverride -lt -1) {
    Write-Output 'ENVIRONMENT_ERROR: simulation time and host timeout must be positive.'
    exit 2
}
if (-not $Xpr) {
    $Xpr = Join-Path $labRoot 'lab3\CPU_CDE\mycpu_verify\run_vivado\mycpu_prj1\mycpu_prj1.xpr'
}
$Xpr = (Resolve-Path -LiteralPath $Xpr).Path
$Vivado = Join-Path $VivadoBin 'vivado.bat'
if (-not (Test-Path -LiteralPath $Vivado)) {
    $Vivado = Join-Path $VivadoBin 'vivado'
}
if (-not (Test-Path -LiteralPath $Vivado)) {
    Write-Output 'ENVIRONMENT_ERROR: Vivado executable was not found.'
    exit 2
}

$stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
$runId = "$Case-$stamp"
$resultRoot = Join-Path $labRoot $caseSettings.ResultRoot
$resultDir = Join-Path $resultRoot $runId
New-Item -ItemType Directory -Path $resultDir -Force | Out-Null
$vivadoBinFull = (Resolve-Path -LiteralPath $VivadoBin).Path
$projectDir = Split-Path -Parent $Xpr
$projectName = [IO.Path]::GetFileNameWithoutExtension($Xpr)
$xsimLog = Join-Path $projectDir "$projectName.sim\sim_1\behav\xsim\xsim.log"
$instCoe = Join-Path $labRoot $caseSettings.InstructionCoe
$caseMif = Join-Path $labRoot $caseSettings.InstructionMif
if ($InstMif) {
    $instMif = (Resolve-Path -LiteralPath $InstMif).Path
} else {
    $instMif = $caseMif
}
if ($ReferenceTrace) {
    if (Test-Path -LiteralPath $ReferenceTrace) {
        $traceFile = (Resolve-Path -LiteralPath $ReferenceTrace).Path
    } else {
        $traceFile = $ReferenceTrace
    }
} else {
    $traceFile = Join-Path $labRoot $caseSettings.ReferenceTrace
}
$expectedFunctionalPoints = if ($ExpectedPointOverride -ge 0) {
    $ExpectedPointOverride
} else {
    [int]$caseSettings.ExpectedFunctionalPoints
}
$instRamXci = Join-Path $labRoot 'lab3\CPU_CDE\mycpu_verify\rtl\xilinx_ip\inst_ram\inst_ram.xci'
$preflightTcl = Join-Path $PSScriptRoot 'check_project.tcl'
$simTcl = Join-Path $PSScriptRoot 'run_behavioral_sim.tcl'

function Quote-CmdArg([string]$Value) {
    '"' + $Value.Replace('"', '""') + '"'
}

function Invoke-VivadoBatch([string]$Name, [string]$TclFile, [string[]]$TclArgs) {
    $vivadoLog = Join-Path $resultDir "$Name-vivado.log"
    $journal = Join-Path $resultDir "$Name-vivado.jou"
    $stdout = Join-Path $resultDir "$Name-console.log"
    $stderr = Join-Path $resultDir "$Name-console.err"
    $commandFile = Join-Path $resultDir "$Name-command.cmd"
    $allArgs = @('-mode', 'batch', '-source', $TclFile, '-log', $vivadoLog, '-journal', $journal, '-tclargs') + $TclArgs
    $quoted = ($allArgs | ForEach-Object { Quote-CmdArg ([string]$_) }) -join ' '
    @('@echo off', "cd /d $(Quote-CmdArg $vivadoBinFull)", "call $(Quote-CmdArg $Vivado) $quoted", 'exit /b %ERRORLEVEL%') |
        Set-Content -LiteralPath $commandFile -Encoding ASCII

    $process = Start-Process -FilePath (Join-Path $env:WINDIR 'System32\cmd.exe') `
        -ArgumentList @('/d', '/c', (Quote-CmdArg $commandFile)) `
        -WorkingDirectory $vivadoBinFull -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $process.Kill($true) } catch { }
        Write-Output "ENVIRONMENT_ERROR: $Name exceeded the $TimeoutSeconds second host timeout."
        return 124
    }
    $process.WaitForExit()
    if (Test-Path -LiteralPath $vivadoLog) {
        Get-Content -LiteralPath $vivadoLog -Raw | Set-Content -LiteralPath (Join-Path $resultDir "$Name-vivado-copy.log") -Encoding UTF8
    }
    return [int]$process.ExitCode
}

Write-Output "RUN_ID=$runId"
Write-Output "XPR=$Xpr"
Write-Output "RESULT_DIR=$resultDir"
Write-Output "CASE=$Case"
Write-Output "PIPELINE_MODE=$PipelineMode"
Write-Output "HAZARD_DIRECTED=$([bool]$HazardDirected)"
Write-Output "CAPTURE_WAVEFORM=$([bool]$CaptureWaveform)"
Write-Output "EXPECTED_FUNCTIONAL_POINTS=$expectedFunctionalPoints"
Write-Output "MAX_SIMULATION_NS=$MaxSimulationNs"
Write-Output "TIMEOUT_SECONDS=$TimeoutSeconds"
Write-Output "VIVADO=$Vivado"
$preflightCode = Invoke-VivadoBatch 'preflight' $preflightTcl @($Xpr, $resultDir)
if ($preflightCode -ne 0) {
    Write-Output "ENVIRONMENT_ERROR: project preflight exited with code $preflightCode. See $resultDir."
    exit 2
}

$preflightLog = Join-Path $resultDir 'preflight-vivado.log'
$preflightText = ''
foreach ($path in @($preflightLog, (Join-Path $resultDir 'preflight-console.log'), (Join-Path $resultDir 'preflight-console.err'))) {
    if (Test-Path -LiteralPath $path) { $preflightText += Get-Content -LiteralPath $path -Raw }
}
if ($preflightText -notmatch 'PREFLIGHT=PASS') {
    Write-Output "ENVIRONMENT_ERROR: preflight PASS marker is missing. See $resultDir."
    exit 2
}
if ($PreflightOnly) {
    Write-Output 'PREFLIGHT=PASS'
    Write-Output "LOG=$resultDir"
    exit 0
}

if (-not $traceFile -or -not (Test-Path -LiteralPath $traceFile) -or (Get-Item -LiteralPath $traceFile).Length -eq 0) {
    $message = if ($Case -eq 'lab4') {
        'an independent Lab4 reference trace is required; generate it with the reference CPU using the Lab4 instruction image, then pass -ReferenceTrace.'
    } else {
        "the Lab3 reference trace is missing or empty: $traceFile"
    }
    "STATUS=ENVIRONMENT_ERROR`nREASON=$message`nCASE=$Case`nPIPELINE_MODE=$PipelineMode" |
        Set-Content -LiteralPath (Join-Path $resultDir 'result.txt') -Encoding UTF8
    Write-Output "ENVIRONMENT_ERROR: $message"
    Write-Output "LOG=$resultDir"
    exit 2
}
$traceHash = (Get-FileHash -LiteralPath $traceFile -Algorithm SHA256).Hash
if (-not (Test-Path -LiteralPath $instMif)) {
    "STATUS=ENVIRONMENT_ERROR`nREASON=instruction image not found: $instMif`nCASE=$Case`nPIPELINE_MODE=$PipelineMode" |
        Set-Content -LiteralPath (Join-Path $resultDir 'result.txt') -Encoding UTF8
    Write-Output "ENVIRONMENT_ERROR: simulation instruction image not found: $instMif"
    Write-Output "LOG=$resultDir"
    exit 2
}
$imageHash = (Get-FileHash -LiteralPath $instMif -Algorithm SHA256).Hash
$coeHash = ''
$imageCheckPassed = $false
$imageCheckFile = Join-Path $resultDir 'instruction-image-check.txt'
if ($InstMif) {
    @("IMAGE_MATCH=OVERRIDE_NOT_CHECKED", "INST_MIF_SHA256=$imageHash") |
        Set-Content -LiteralPath $imageCheckFile -Encoding UTF8
} else {
    if (-not (Test-Path -LiteralPath $instCoe)) {
        Write-Output "ENVIRONMENT_ERROR: instruction COE file is missing: $instCoe"
        exit 2
    }
    $coeHash = (Get-FileHash -LiteralPath $instCoe -Algorithm SHA256).Hash
    $imageChecker = Join-Path $PSScriptRoot 'check_instruction_image.py'
    $imageCheckOutput = & python $imageChecker --coe $instCoe --mif $instMif --xci $instRamXci 2>&1
    $imageCheckCode = $LASTEXITCODE
    $imageCheckOutput | Set-Content -LiteralPath $imageCheckFile -Encoding UTF8
    $imageCheckPassed = ($imageCheckCode -eq 0) -and ($imageCheckOutput -match 'IMAGE_MATCH=PASS')
    if (-not $imageCheckPassed) {
        Write-Output "ENVIRONMENT_ERROR: instruction COE/MIF consistency check failed. See $imageCheckFile."
        Write-Output "LOG=$resultDir"
        exit 2
    }
}
Write-Output "TRACE=$traceFile SHA256=$traceHash"
Write-Output "INST_MIF=$instMif SHA256=$imageHash"
if ($coeHash) { Write-Output "INST_COE=$instCoe SHA256=$coeHash" }

$startedAt = [DateTime]::UtcNow
$simExpectedFunctionalPoints = if ($HazardDirected) { 0 } else { $expectedFunctionalPoints }
$simCaptureWaveform = if ($CaptureWaveform) { '1' } else { '0' }
$simArgs = @($Xpr, $Case, [string]$MaxSimulationNs, $PipelineMode, $traceFile, $instMif, $resultDir,
    [string]$simExpectedFunctionalPoints, $simCaptureWaveform)
$simCode = Invoke-VivadoBatch 'simulation' $simTcl $simArgs
$simWorkingDir = Split-Path -Parent $xsimLog
$waveformPath = ''
$waveformHash = ''
$waveformCaptured = $false
if ($CaptureWaveform) {
    $sourceWdb = Join-Path $simWorkingDir 'tb_top_behav.wdb'
    if ((Test-Path -LiteralPath $sourceWdb) -and
        (Get-Item -LiteralPath $sourceWdb).LastWriteTimeUtc -ge $startedAt.AddSeconds(-2)) {
        $waveformPath = Join-Path $resultDir 'hazard-directed-forwarding.wdb'
        Copy-Item -LiteralPath $sourceWdb -Destination $waveformPath -Force
        $waveformHash = (Get-FileHash -LiteralPath $waveformPath -Algorithm SHA256).Hash
        $waveformCaptured = $true
    }
}
$xsimLogFresh = $false
if ((Test-Path -LiteralPath $xsimLog) -and (Get-Item -LiteralPath $xsimLog).LastWriteTimeUtc -ge $startedAt.AddSeconds(-2)) {
    Copy-Item -LiteralPath $xsimLog -Destination (Join-Path $resultDir 'xsim.log') -Force
    $xsimLogFresh = $true
}
$stageLogs = @{}
foreach ($name in @('xvlog.log', 'xvhdl.log', 'compile.log', 'elaborate.log', 'simulate.log')) {
    $sourceLog = Join-Path $simWorkingDir $name
    $fresh = (Test-Path -LiteralPath $sourceLog) -and
        (Get-Item -LiteralPath $sourceLog).LastWriteTimeUtc -ge $startedAt.AddSeconds(-2)
    $stageLogs[$name] = $fresh
    if ($fresh) {
        $destinationName = if ($name -eq 'simulate.log') { 'xsim-simulate-stage.log' } else { "xsim-$name" }
        Copy-Item -LiteralPath $sourceLog -Destination (Join-Path $resultDir $destinationName) -Force
    }
}
$xsimSources = Join-Path $projectDir "$projectName.sim\sim_1\behav\xsim\tb_top_vlog.prj"
$compileSourcesFresh = $false
if ((Test-Path -LiteralPath $xsimSources) -and (Get-Item -LiteralPath $xsimSources).LastWriteTimeUtc -ge $startedAt.AddSeconds(-2)) {
    Copy-Item -LiteralPath $xsimSources -Destination (Join-Path $resultDir 'xsim-sources.prj') -Force
    $sourceManifest = Get-Content -Raw -LiteralPath $xsimSources
    $compileSourcesFresh = $sourceManifest -match 'mycpu_tb\.v' -and $sourceManifest -match 'soc_lite_top\.v'
}
$simInstMif = Join-Path $projectDir "$projectName.sim\sim_1\behav\xsim\inst_ram.mif"
$simImageHash = ''
$simImageMatches = $false
if (Test-Path -LiteralPath $simInstMif) {
    Copy-Item -LiteralPath $simInstMif -Destination (Join-Path $resultDir 'sim-inst_ram.mif') -Force
    $simImageHash = (Get-FileHash -LiteralPath $simInstMif -Algorithm SHA256).Hash
    $simImageMatches = $simImageHash -eq $imageHash
}
$logFiles = @(
    (Join-Path $resultDir 'simulation-vivado.log'),
    (Join-Path $resultDir 'simulation-console.log'),
    (Join-Path $resultDir 'simulation-console.err'),
    (Join-Path $resultDir 'xsim.log'),
    (Join-Path $resultDir 'xsim-compile.log'),
    (Join-Path $resultDir 'xsim-xvlog.log'),
    (Join-Path $resultDir 'xsim-elaborate.log'),
    (Join-Path $resultDir 'xsim-simulate-stage.log')
) | Where-Object { Test-Path -LiteralPath $_ }
$logText = ($logFiles | ForEach-Object { Get-Content -LiteralPath $_ -Raw }) -join "`n"
$logText | Set-Content -LiteralPath (Join-Path $resultDir 'combined.log') -Encoding UTF8

$endMarker = $logText -match 'Test end!'
$passMarker = $logText -match '----PASS!!!'
$traceOpened = $logText -match 'TRACE_REF_OPEN_OK'
$traceOpenFailed = $logText -match 'TRACE_REF_OPEN_FAIL'
$errors = $logText -match 'Error!!!|Error\s*\([^\r\n]*\)!!!|Fail!!!|TRACE_MISMATCH|TRACE_REMAINING_RECORDS|TRACE_TAIL_READ_FAIL|FUNCTIONAL_POINT_COUNT_MISMATCH'
$pointPasses = ([regex]::Matches($logText, 'Functional Test Point PASS!!!')).Count
$functionalPointCountMatch = [regex]::Match($logText, 'FUNCTIONAL_POINT_PASSES=(\d+)')
$finishAtEnd = $logText -match 'debug_wb_pc\s*=\s*0xbfc00100|Test end!'
$cyclesMatch = [regex]::Match($logText, 'PIPELINE_CYCLES=(\d+)')
$stallsMatch = [regex]::Match($logText, 'PIPELINE_STALL_CYCLES=(\d+)')
$forwardExMatch = [regex]::Match($logText, 'FORWARD_EX_USES=(\d+)')
$forwardMemMatch = [regex]::Match($logText, 'FORWARD_MEM_USES=(\d+)')
$forwardWbMatch = [regex]::Match($logText, 'FORWARD_WB_USES=(\d+)')
$zeroRegWritebackMatch = [regex]::Match($logText, 'ZERO_REG_WRITEBACK_ATTEMPTS=(\d+)')
$cycles = if ($cyclesMatch.Success) { [long]$cyclesMatch.Groups[1].Value } else { 0 }
$stallCycles = if ($stallsMatch.Success) { [long]$stallsMatch.Groups[1].Value } else { 0 }
$forwardEx = if ($forwardExMatch.Success) { [long]$forwardExMatch.Groups[1].Value } else { 0 }
$forwardMem = if ($forwardMemMatch.Success) { [long]$forwardMemMatch.Groups[1].Value } else { 0 }
$forwardWb = if ($forwardWbMatch.Success) { [long]$forwardWbMatch.Groups[1].Value } else { 0 }
$forwardUses = $forwardEx + $forwardMem + $forwardWb
$zeroRegWritebackAttempts = if ($zeroRegWritebackMatch.Success) { [long]$zeroRegWritebackMatch.Groups[1].Value } else { -1 }
$reportedFunctionalPointPasses = if ($functionalPointCountMatch.Success) { [int]$functionalPointCountMatch.Groups[1].Value } else { -1 }
$zeroRegWritebackPass = $zeroRegWritebackMatch.Success -and $zeroRegWritebackAttempts -eq 0
$hazardMetrics = @{}
foreach ($metric in @(
    'HAZARD_LOAD_USE_STALLS',
    'HAZARD_STORE_BASE_FORWARDS',
    'HAZARD_STORE_DATA_FORWARDS',
    'HAZARD_BRANCH_FORWARDS',
    'HAZARD_JR_FORWARDS',
    'HAZARD_PRIORITY_EX_USES',
    'HAZARD_ZERO_DEST_WRITES'
)) {
    $match = [regex]::Match($logText, "$metric=(\d+)")
    $hazardMetrics[$metric] = if ($match.Success) { [long]$match.Groups[1].Value } else { 0 }
}
$expectedPointPasses = if ($HazardDirected) { 0 } else { $expectedFunctionalPoints }
$hazardCoveragePass = $true
if ($HazardDirected) {
    $hazardCoveragePass = $hazardMetrics['HAZARD_LOAD_USE_STALLS'] -gt 0
    if ($PipelineMode -eq 'forwarding') {
        $hazardCoveragePass = $hazardCoveragePass -and
            $forwardEx -gt 0 -and $forwardMem -gt 0 -and $forwardWb -gt 0 -and
            $hazardMetrics['HAZARD_STORE_BASE_FORWARDS'] -gt 0 -and
            $hazardMetrics['HAZARD_STORE_DATA_FORWARDS'] -gt 0 -and
            $hazardMetrics['HAZARD_BRANCH_FORWARDS'] -gt 0 -and
            $hazardMetrics['HAZARD_JR_FORWARDS'] -gt 0 -and
            $hazardMetrics['HAZARD_PRIORITY_EX_USES'] -gt 0
    } else {
        $hazardCoveragePass = $hazardCoveragePass -and $forwardUses -eq 0
    }
}

$status = 'INCOMPLETE'
if ($traceOpenFailed) {
    $status = 'ENVIRONMENT_ERROR'
} elseif ($errors -or ($simCode -ne 0 -and $simCode -ne 124)) {
    $status = 'FAIL'
} elseif ($simCode -eq 124) {
    $status = 'ENVIRONMENT_ERROR'
} elseif ($CaptureWaveform -and -not $waveformCaptured) {
    $status = 'ENVIRONMENT_ERROR'
} elseif ($logText -match '(?im)^\s*ENVIRONMENT_ERROR:') {
    $status = 'ENVIRONMENT_ERROR'
} elseif (-not $compileSourcesFresh -or -not $stageLogs['simulate.log'] -or -not $simImageMatches) {
    $status = 'ENVIRONMENT_ERROR'
} elseif ($zeroRegWritebackMatch.Success -and $zeroRegWritebackAttempts -gt 0) {
    $status = 'FAIL'
} elseif ($endMarker -and $passMarker -and $traceOpened -and $finishAtEnd -and
    $pointPasses -eq $expectedPointPasses -and
    $reportedFunctionalPointPasses -eq $expectedPointPasses -and
    $hazardCoveragePass -and $zeroRegWritebackPass) {
    if ($Case -eq 'lab4' -and $PipelineMode -eq 'forwarding' -and ($forwardUses -eq 0 -or $stallCycles -eq 0)) {
        $status = 'FAIL'
    } elseif ($Case -eq 'lab4' -and $PipelineMode -eq 'blocking' -and $stallCycles -eq 0) {
        $status = 'FAIL'
    } else {
        $status = 'PASS'
    }
}

@(
    "STATUS=$status",
    "SIM_EXIT_CODE=$simCode",
    "PIPELINE_MODE=$PipelineMode",
    "TRACE_FILE=$traceFile",
    "INST_MIF=$instMif",
    "TRACE_OPENED=$traceOpened",
    "TEST_END=$endMarker",
    "PASS_MARKER=$passMarker",
    "EXPECTED_FUNCTIONAL_POINTS=$expectedPointPasses",
    "FUNCTIONAL_POINT_PASSES=$pointPasses",
    "FUNCTIONAL_POINT_COUNT_REPORTED=$reportedFunctionalPointPasses",
    "PIPELINE_CYCLES=$cycles",
    "PIPELINE_STALL_CYCLES=$stallCycles",
    "FORWARD_EX_USES=$forwardEx",
    "FORWARD_MEM_USES=$forwardMem",
    "FORWARD_WB_USES=$forwardWb",
    "FORWARD_USES=$forwardUses",
    "HAZARD_DIRECTED=$([bool]$HazardDirected)",
    "EXPECTED_FUNCTIONAL_POINT_PASSES=$expectedPointPasses",
    "HAZARD_LOAD_USE_STALLS=$($hazardMetrics['HAZARD_LOAD_USE_STALLS'])",
    "HAZARD_STORE_BASE_FORWARDS=$($hazardMetrics['HAZARD_STORE_BASE_FORWARDS'])",
    "HAZARD_STORE_DATA_FORWARDS=$($hazardMetrics['HAZARD_STORE_DATA_FORWARDS'])",
    "HAZARD_BRANCH_FORWARDS=$($hazardMetrics['HAZARD_BRANCH_FORWARDS'])",
    "HAZARD_JR_FORWARDS=$($hazardMetrics['HAZARD_JR_FORWARDS'])",
    "HAZARD_PRIORITY_EX_USES=$($hazardMetrics['HAZARD_PRIORITY_EX_USES'])",
    "HAZARD_ZERO_DEST_WRITES=$($hazardMetrics['HAZARD_ZERO_DEST_WRITES'])",
    "ZERO_REG_WRITEBACK_ATTEMPTS=$zeroRegWritebackAttempts",
    "ZERO_REG_WRITEBACK_PASS=$zeroRegWritebackPass",
    "WAVEFORM_CAPTURED=$waveformCaptured",
    "WAVEFORM_FILE=$waveformPath",
    "WAVEFORM_SHA256=$waveformHash",
    "HAZARD_COVERAGE_PASS=$hazardCoveragePass",
    "COMPILE_SOURCES_FRESH=$compileSourcesFresh",
    "XVLOG_LOG_FRESH=$($stageLogs['xvlog.log'])",
    "ELABORATE_LOG_FRESH=$($stageLogs['elaborate.log'])",
    "SIMULATE_STAGE_LOG_FRESH=$($stageLogs['simulate.log'])",
    "XSIM_SIMULATE_STAGE_LOG_FRESH=$($stageLogs['simulate.log'])",
    "SIM_IMAGE_MATCHES_SOURCE=$simImageMatches",
    "SIM_INST_MIF_SHA256=$simImageHash",
    "INST_COE_SHA256=$coeHash",
    "TRACE_SHA256=$traceHash",
    "INST_MIF_SHA256=$imageHash",
    "STARTED_UTC=$($startedAt.ToString('o'))",
    "FINISHED_UTC=$([DateTime]::UtcNow.ToString('o'))"
) | Set-Content -LiteralPath (Join-Path $resultDir 'result.txt') -Encoding UTF8

Write-Output "FUNCTIONAL_POINT_PASSES=$pointPasses"
Write-Output "FUNCTIONAL_POINT_COUNT_REPORTED=$reportedFunctionalPointPasses"
Write-Output "PIPELINE_CYCLES=$cycles"
Write-Output "PIPELINE_STALL_CYCLES=$stallCycles"
Write-Output "FORWARD_EX_USES=$forwardEx"
Write-Output "FORWARD_MEM_USES=$forwardMem"
Write-Output "FORWARD_WB_USES=$forwardWb"
Write-Output "HAZARD_LOAD_USE_STALLS=$($hazardMetrics['HAZARD_LOAD_USE_STALLS'])"
Write-Output "HAZARD_STORE_BASE_FORWARDS=$($hazardMetrics['HAZARD_STORE_BASE_FORWARDS'])"
Write-Output "HAZARD_STORE_DATA_FORWARDS=$($hazardMetrics['HAZARD_STORE_DATA_FORWARDS'])"
Write-Output "HAZARD_BRANCH_FORWARDS=$($hazardMetrics['HAZARD_BRANCH_FORWARDS'])"
Write-Output "HAZARD_JR_FORWARDS=$($hazardMetrics['HAZARD_JR_FORWARDS'])"
Write-Output "HAZARD_PRIORITY_EX_USES=$($hazardMetrics['HAZARD_PRIORITY_EX_USES'])"
Write-Output "HAZARD_ZERO_DEST_WRITES=$($hazardMetrics['HAZARD_ZERO_DEST_WRITES'])"
Write-Output "ZERO_REG_WRITEBACK_ATTEMPTS=$zeroRegWritebackAttempts"
Write-Output "ZERO_REG_WRITEBACK_PASS=$zeroRegWritebackPass"
Write-Output "WAVEFORM_CAPTURED=$waveformCaptured"
if ($waveformPath) { Write-Output "WAVEFORM_FILE=$waveformPath"; Write-Output "WAVEFORM_SHA256=$waveformHash" }
Write-Output "SIM_IMAGE_MATCHES_SOURCE=$simImageMatches"
Write-Output "STATUS=$status"
Write-Output "LOG=$($resultDir)"
if ($status -ne 'PASS') { exit 1 }
exit 0
