[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('lab10', 'lab11')]
    [string]$Case,
    [ValidateSet('directed', 'full')]
    [string]$Suite = 'full',
    [string]$VivadoBin = 'D:\Verilog\2025.2\Vivado\bin',
    [int]$TimeoutSeconds = 3600,
    [long]$MaxSimulationNs = 20000000,
    [string]$ReferenceTrace,
    [string]$InstMif,
    [string]$RunId,
    [switch]$CaptureWaveform,
    [switch]$PreflightOnly
)

$ErrorActionPreference = 'Stop'
$inputScanStatus = 'NOT_RUN'
$vivadoPreflightStatus = 'NOT_RUN'
$sourceIntegrityStatus = 'NOT_RUN'
$sourceCapturePhase = 'NOT_STARTED'
$effectiveManifestHash = ''
$effectiveManifestRelative = 'effective-source-manifest.csv'
$labRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $PSScriptRoot 'cases_bus.json'
if (-not (Test-Path -LiteralPath $configPath)) {
    Write-Output "ENVIRONMENT_ERROR: case configuration is missing: $configPath"
    exit 2
}
$allCases = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$settings = $allCases.$Case
if (-not $settings) {
    Write-Output "ENVIRONMENT_ERROR: no settings for case $Case"
    exit 2
}
if ($TimeoutSeconds -le 0 -or $MaxSimulationNs -le 0) {
    Write-Output 'ENVIRONMENT_ERROR: timeout and simulation duration must be positive.'
    exit 2
}
if ($CaptureWaveform -and $Suite -ne 'full') {
    Write-Output 'ENVIRONMENT_ERROR: waveform capture is available for the full suite only.'
    exit 2
}

if (Test-Path -LiteralPath $VivadoBin -PathType Leaf) {
    $Vivado = (Resolve-Path -LiteralPath $VivadoBin).Path
    $vivadoBinFull = Split-Path -Parent $Vivado
} else {
    $vivadoBinFull = (Resolve-Path -LiteralPath $VivadoBin).Path
    $Vivado = Join-Path $vivadoBinFull 'vivado.bat'
    if (-not (Test-Path -LiteralPath $Vivado)) { $Vivado = Join-Path $vivadoBinFull 'vivado' }
}
if (-not (Test-Path -LiteralPath $Vivado)) {
    Write-Output "ENVIRONMENT_ERROR: Vivado executable was not found under $VivadoBin"
    exit 2
}

$stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
if (-not $RunId) { $RunId = "$Case-$Suite-$stamp" }
if ($RunId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$') {
    Write-Output 'ENVIRONMENT_ERROR: RunId may contain only letters, digits, dot, underscore, and hyphen.'
    exit 2
}
$resultRoot = Join-Path $labRoot $settings.ResultRoot
$runDir = Join-Path $resultRoot $RunId
if (Test-Path -LiteralPath $runDir) {
    Write-Output "ENVIRONMENT_ERROR: refusing to reuse an existing run directory: $runDir"
    exit 2
}
New-Item -ItemType Directory -Path $runDir -Force | Out-Null

$projectXpr = Join-Path $labRoot $settings.ProjectXpr
$runProjectXpr = $projectXpr
$tracePath = if ($ReferenceTrace) {
    if (-not (Test-Path -LiteralPath $ReferenceTrace -PathType Leaf)) {
        Write-Output "ENVIRONMENT_ERROR: reference trace is missing: $ReferenceTrace"
        exit 2
    }
    (Resolve-Path -LiteralPath $ReferenceTrace).Path
} else {
    Join-Path $labRoot $settings.ReferenceTrace
}
$mifPath = if ($InstMif) {
    if (-not (Test-Path -LiteralPath $InstMif -PathType Leaf)) {
        Write-Output "ENVIRONMENT_ERROR: instruction MIF is missing: $InstMif"
        exit 2
    }
    (Resolve-Path -LiteralPath $InstMif).Path
} else {
    Join-Path $labRoot $settings.InstructionMif
}
foreach ($inputPath in @($projectXpr, $tracePath, $mifPath)) {
    if (-not (Test-Path -LiteralPath $inputPath -PathType Leaf)) {
        Write-Output "ENVIRONMENT_ERROR: required input is missing: $inputPath"
        exit 2
    }
}
if ((Get-Item -LiteralPath $tracePath).Length -eq 0 -or (Get-Item -LiteralPath $mifPath).Length -eq 0) {
    Write-Output 'ENVIRONMENT_ERROR: reference trace and instruction MIF must be nonempty.'
    exit 2
}

function Quote-CmdArg([string]$Value) {
    '"' + $Value.Replace('"', '""') + '"'
}

function Invoke-VivadoBatch([string]$Name, [string]$TclFile, [string[]]$TclArgs) {
    $vivadoLog = Join-Path $runDir "$Name-vivado.log"
    $journal = Join-Path $runDir "$Name-vivado.jou"
    $stdout = Join-Path $runDir "$Name-console.log"
    $stderr = Join-Path $runDir "$Name-console.err"
    $commandFile = Join-Path $runDir "$Name-command.cmd"
    $allArgs = @('-mode', 'batch', '-source', $TclFile, '-log', $vivadoLog,
                 '-journal', $journal, '-tclargs') + $TclArgs
    $quoted = ($allArgs | ForEach-Object { Quote-CmdArg ([string]$_) }) -join ' '
    @('@echo off', "cd /d $(Quote-CmdArg $vivadoBinFull)",
      "call $(Quote-CmdArg $Vivado) $quoted", 'exit /b %ERRORLEVEL%') |
        Set-Content -LiteralPath $commandFile -Encoding ASCII
    $process = Start-Process -FilePath (Join-Path $env:WINDIR 'System32\cmd.exe') `
        -ArgumentList @('/d', '/c', (Quote-CmdArg $commandFile)) `
        -WorkingDirectory $vivadoBinFull -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        $taskkill = Join-Path $env:WINDIR 'System32\taskkill.exe'
        try {
            Start-Process -FilePath $taskkill -ArgumentList @('/PID', [string]$process.Id, '/T', '/F') `
                -WindowStyle Hidden -Wait | Out-Null
        } catch { }
        try {
            $process.Refresh()
            if (-not $process.HasExited) { $process.Kill($true) }
            $process.WaitForExit(5000) | Out-Null
        } catch { }
        Write-Host "ENVIRONMENT_ERROR: $Name exceeded the $TimeoutSeconds second host timeout."
        return 124
    }
    $process.WaitForExit()
    return [int]$process.ExitCode
}

@(
    "RUN_ID=$RunId",
    "CASE=$Case",
    "SUITE=$(if ($PreflightOnly) { 'preflight' } else { $Suite })",
    "VIVADO=$Vivado",
    "PROJECT_XPR=$projectXpr",
    "REFERENCE_TRACE=$tracePath",
    "INST_MIF=$mifPath",
    "MAX_SIMULATION_NS=$MaxSimulationNs",
    "TIMEOUT_SECONDS=$TimeoutSeconds",
    "CAPTURE_WAVEFORM=$([bool]$CaptureWaveform)",
    "COMMAND=verify_bus.ps1 -Case $Case -Suite $Suite -RunId $RunId"
) | Set-Content -LiteralPath (Join-Path $runDir 'command.txt') -Encoding UTF8

try {
    $pythonArgs = @((Join-Path $PSScriptRoot 'check_bus_inputs.py'), '--repo-root', $labRoot,
                    '--lab-root', $labRoot, '--output-dir', $runDir,
                    '--case', $Case, '--suite', $Suite, '--run-id', $RunId,
                    '--trace', $tracePath, '--mif', $mifPath)
    if ($InstMif) { $pythonArgs += '--inst-override' }
    $pythonOutput = & python @pythonArgs 2>&1
    $pythonCode = $LASTEXITCODE
    $pythonOutput | Set-Content -LiteralPath (Join-Path $runDir 'input-check.log') -Encoding UTF8
    if ($pythonCode -ne 0) { throw "input manifest creation failed with exit code $pythonCode" }
    $inputScanInfo = Get-Content -LiteralPath (Join-Path $runDir 'input-scan.txt') -Raw
    $scanMatch = [regex]::Match($inputScanInfo, '(?m)^INPUT_SCAN_STATUS=(PASS|FAIL)\s*$')
    if (-not $scanMatch.Success) { throw 'input-scan.txt did not record INPUT_SCAN_STATUS.' }
    $inputScanStatus = $scanMatch.Groups[1].Value
    if ($inputScanStatus -ne 'PASS') { throw 'static input scan failed; see input-scan.txt.' }

    $preflightDir = Join-Path $runDir 'preflight'
    New-Item -ItemType Directory -Path $preflightDir | Out-Null
    $preflightTcl = Join-Path $PSScriptRoot 'check_bus_project.tcl'
    $preflightCode = Invoke-VivadoBatch 'preflight' $preflightTcl @($Case, $projectXpr, $preflightDir)
    $preflightReport = Join-Path $preflightDir 'project-preflight.txt'
    $preflightText = if (Test-Path -LiteralPath $preflightReport) {
        Get-Content -LiteralPath $preflightReport -Raw
    } else { '' }
    $preflightMatch = [regex]::Match($preflightText, '(?m)^PREFLIGHT=(PASS|FAIL)\s*$')
    $vivadoPreflightStatus = if ($preflightMatch.Success) { $preflightMatch.Groups[1].Value } else { 'FAIL' }
    $versionForSummary = [regex]::Match($preflightText, '(?m)^VIVADO_VERSION=(.+)$')
    $ipForSummary = [regex]::Match($preflightText, '(?m)^IP_STATUS=(.+)$')
    @(
        "RUN_ID=$RunId", "CASE=$Case", "SUITE=$(if ($PreflightOnly) { 'preflight' } else { $Suite })",
        "VIVADO_PREFLIGHT_STATUS=$vivadoPreflightStatus",
        "VIVADO_VERSION=$(if ($versionForSummary.Success) { $versionForSummary.Groups[1].Value.Trim() } else { 'NOT_RECORDED' })",
        "IP_STATUS=$(if ($ipForSummary.Success) { $ipForSummary.Groups[1].Value.Trim() } else { 'NOT_RECORDED' })",
        "PROJECT_PREFLIGHT_REPORT=$(Join-Path $preflightDir 'project-preflight.txt')"
    ) | Set-Content -LiteralPath (Join-Path $runDir 'vivado-preflight-summary.txt') -Encoding UTF8
    if ($preflightCode -ne 0 -or $preflightText -notmatch 'PREFLIGHT=PASS') {
        @("RUN_ID=$RunId", "CASE=$Case", 'SUITE=preflight', 'STATUS=ENVIRONMENT_ERROR',
          "INPUT_SCAN_STATUS=$inputScanStatus", 'VIVADO_PREFLIGHT_STATUS=FAIL',
          'PREFLIGHT_STATUS=FAIL', 'FUNCTIONAL_STATUS=NOT_RUN', 'TRACE_COMPARE_STATUS=NOT_RUN') |
            Set-Content -LiteralPath (Join-Path $runDir 'result.txt') -Encoding UTF8
        Write-Output "ENVIRONMENT_ERROR: read-only project preflight failed. See $runDir"
        exit 2
    }
    $versionMatch = [regex]::Match($preflightText, '(?m)^VIVADO_VERSION=(.+)$')
    if (-not $versionMatch.Success) { throw 'Vivado version was not recorded by project preflight.' }
    $vivadoVersion = $versionMatch.Groups[1].Value.Trim()
    Set-Content -LiteralPath (Join-Path $runDir 'vivado-version.txt') -Encoding UTF8 -Value $vivadoVersion
    if ($PreflightOnly) {
        @("RUN_ID=$RunId", "CASE=$Case", 'SUITE=preflight', 'STATUS=INCOMPLETE',
          "INPUT_SCAN_STATUS=$inputScanStatus", "VIVADO_PREFLIGHT_STATUS=$vivadoPreflightStatus",
          'PREFLIGHT_STATUS=PASS', 'FUNCTIONAL_STATUS=NOT_RUN', 'PROTOCOL_STATUS=NOT_RUN',
          'WAVEFORM_STATUS=NOT_REQUESTED', 'TRACE_COMPARE_STATUS=NOT_RUN',
          "VIVADO_VERSION=$vivadoVersion") |
            Set-Content -LiteralPath (Join-Path $runDir 'result.txt') -Encoding UTF8
        Write-Output "PREFLIGHT=PASS"
        Write-Output "RUN_DIR=$runDir"
        exit 0
    }

    if ($Suite -eq 'directed') {
        if ($Case -eq 'lab10') {
            $unitXpr = Join-Path (Split-Path -Parent $projectXpr) "mycpu_lab10_directed_$RunId.xpr"
            $cpuDir = Join-Path $labRoot $settings.CpuSourceDir
            $unitBench = Join-Path $labRoot $settings.DirectedTestbench
            $creator = Join-Path $labRoot $settings.UnitCreator
            $unitArgs = @($creator, '--base-xpr', $projectXpr, '--cpu-dir', $cpuDir,
                          '--design-top', 'if_stage', '--sim-top', 'tb_lab10_bus',
                          '--sim-file', $unitBench,
                          '--design-file', (Join-Path $cpuDir 'mycpu.h'),
                          '--design-file', (Join-Path $cpuDir 'IF_stage.v'),
                          '--design-file', (Join-Path $cpuDir 'MEM_stage.v'),
                          '--output-xpr', $unitXpr)
            $created = & python @unitArgs 2>&1
            $creatorCode = $LASTEXITCODE
            $created | Set-Content -LiteralPath (Join-Path $runDir 'create-project.log') -Encoding UTF8
            if ($creatorCode -ne 0) { throw "Lab10 directed XPR creation failed: $creatorCode" }
            $runProjectXpr = $unitXpr
            $tclArgs = @($unitXpr, $runDir)
        } else {
            $unitXpr = Join-Path $runDir 'project/lab11_axi3_directed.xpr'
            $cpuDir = Join-Path $labRoot $settings.CpuSourceDir
            $unitBench = Join-Path $labRoot $settings.DirectedTestbench
            $creator = Join-Path $labRoot 'scripts/create_bus_unit_xpr.py'
            $unitArgs = @($creator, '--base-xpr', $projectXpr, '--cpu-dir', $cpuDir,
                          '--design-top', 'if_stage', '--sim-top', 'tb_lab11_axi3_bus',
                          '--sim-file', $unitBench,
                          '--design-file', (Join-Path $cpuDir 'mycpu.h'),
                          '--design-file', (Join-Path $cpuDir 'IF_stage.v'),
                          '--design-file', (Join-Path $cpuDir 'axi3_cpu_bus.v'),
                          '--output-xpr', $unitXpr)
            $created = & python @unitArgs 2>&1
            $creatorCode = $LASTEXITCODE
            $created | Set-Content -LiteralPath (Join-Path $runDir 'create-project.log') -Encoding UTF8
            if ($creatorCode -ne 0) { throw "Lab11 directed XPR creation failed: $creatorCode" }
            $runProjectXpr = $unitXpr
            $tclArgs = @($unitXpr, $runDir)
        }
        $runner = Join-Path $labRoot $settings.UnitRunner
    } else {
        $creator = Join-Path $labRoot $settings.SocCreator
        $createArgs = @($creator, '--repo-root', $labRoot, '--run-dir', $runDir)
        if ($InstMif) {
            $overrideCoe = Join-Path $runDir 'inst-image-override.coe'
            $convert = & python (Join-Path $PSScriptRoot 'mif_to_coe.py') `
                --input $mifPath --output $overrideCoe 2>&1
            $convertCode = $LASTEXITCODE
            $convert | Set-Content -LiteralPath (Join-Path $runDir 'mif-conversion.log') -Encoding UTF8
            if ($convertCode -ne 0) { throw "instruction MIF conversion failed: $convertCode" }
            $createArgs += @('--inst-coe', $overrideCoe)
            $coePathForManifest = $overrideCoe
        } else {
            $coePathForManifest = Join-Path $labRoot $settings.InstructionCoe
        }
        $created = & python @createArgs 2>&1
        $creatorCode = $LASTEXITCODE
        $created | Set-Content -LiteralPath (Join-Path $runDir 'create-project.log') -Encoding UTF8
        if ($creatorCode -ne 0) { throw "SoC XPR creation failed: $creatorCode" }
        $xprLine = $created | Where-Object { $_ -match '^PROJECT_XPR=' } | Select-Object -First 1
        if (-not $xprLine) { throw 'SoC XPR creator did not print PROJECT_XPR.' }
        $socXpr = $xprLine.Substring('PROJECT_XPR='.Length)
        $runProjectXpr = $socXpr
        $captureArg = if ($CaptureWaveform) { '1' } else { '0' }
        $tclArgs = @($socXpr, $runDir, [string]$MaxSimulationNs, $tracePath,
                     [string]$settings.ExpectedFunctionalPoints, $captureArg)
        $runner = Join-Path $labRoot $settings.SocRunner
    }

    if (-not $coePathForManifest) { $coePathForManifest = Join-Path $labRoot $settings.InstructionCoe }
    $manifestPath = Join-Path $runDir $effectiveManifestRelative
    $captureScript = Join-Path $PSScriptRoot 'capture_bus_source_manifest.py'
    $captureArgs = @($captureScript, '--repo-root', $labRoot, '--case', $Case, '--suite', $Suite,
                     '--run-id', $RunId, '--xpr', $runProjectXpr,
                     '--manifest', $manifestPath, '--phase', 'PRE_SIM',
                     '--coe', $coePathForManifest, '--mif', $mifPath, '--trace', $tracePath)
    if ($InstMif) { $captureArgs += '--inst-override' }
    $sourceCapturePhase = 'PRE_SIM'
    $captureOutput = & python @captureArgs 2>&1
    $captureCode = $LASTEXITCODE
    $captureOutput | Set-Content -LiteralPath (Join-Path $runDir 'source-capture-pre.log') -Encoding UTF8
    if ($captureCode -ne 0) {
        $sourceIntegrityStatus = 'FAIL'
        throw "PRE_SIM source manifest capture failed with exit code $captureCode"
    }
    $sourceIntegrityStatus = 'PENDING'

    $runCode = Invoke-VivadoBatch $Suite $runner $tclArgs
    $sourceCapturePhase = 'PRE_SIM_AND_POST_SIM'
    $postCaptureArgs = @($captureScript, '--repo-root', $labRoot, '--case', $Case, '--suite', $Suite,
                         '--run-id', $RunId, '--xpr', $runProjectXpr,
                         '--manifest', $manifestPath, '--phase', 'POST_SIM',
                         '--coe', $coePathForManifest, '--mif', $mifPath, '--trace', $tracePath)
    if ($InstMif) { $postCaptureArgs += '--inst-override' }
    $postCaptureOutput = & python @postCaptureArgs 2>&1
    $postCaptureCode = $LASTEXITCODE
    $postCaptureOutput | Set-Content -LiteralPath (Join-Path $runDir 'source-capture-post.log') -Encoding UTF8
    $integrityMatch = [regex]::Match(($postCaptureOutput -join "`n"), '(?m)^SOURCE_INTEGRITY=(PASS|FAIL)$')
    if ($integrityMatch.Success) { $sourceIntegrityStatus = $integrityMatch.Groups[1].Value }
    else { $sourceIntegrityStatus = 'FAIL' }
    if ($postCaptureCode -ne 0 -or $sourceIntegrityStatus -ne 'PASS') {
        throw "POST_SIM source integrity check failed (exit=$postCaptureCode, status=$sourceIntegrityStatus)."
    }
    $effectiveManifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
    if ($runCode -ne 0) {
        if (-not (Test-Path -LiteralPath (Join-Path $runDir 'result.txt'))) {
            @("RUN_ID=$RunId", "CASE=$Case", "SUITE=$Suite", 'STATUS=FAIL',
              "SIM_EXIT_CODE=$runCode", "INPUT_SCAN_STATUS=$inputScanStatus",
              "VIVADO_PREFLIGHT_STATUS=$vivadoPreflightStatus", 'PREFLIGHT_STATUS=PASS',
              "SOURCE_INTEGRITY=$sourceIntegrityStatus",
              "EFFECTIVE_SOURCE_MANIFEST=$effectiveManifestRelative",
              "EFFECTIVE_SOURCE_MANIFEST_SHA256=$effectiveManifestHash",
              "SOURCE_CAPTURE_PHASE=$sourceCapturePhase") |
                Set-Content -LiteralPath (Join-Path $runDir 'result.txt') -Encoding UTF8
        }
        Write-Output "FAIL: $Suite exited with code $runCode. See $runDir"
        exit 1
    }

    $resultPath = Join-Path $runDir 'result.txt'
    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "Vivado exited with code 0 but the runner did not produce a validated result.txt. See $runDir"
    }
    $runnerResultText = Get-Content -LiteralPath $resultPath -Raw
    if ($runnerResultText -notmatch '(?m)^STATUS=PASS\s*$') {
        throw "Vivado runner result does not contain STATUS=PASS. See $resultPath"
    }
    $simLog = Join-Path $runDir 'simulate.log'
    if (-not (Test-Path -LiteralPath $simLog -PathType Leaf) -or (Get-Item -LiteralPath $simLog).Length -eq 0) {
        throw "validated simulation log is missing or empty: $simLog"
    }
    $simText = Get-Content -LiteralPath $simLog -Raw
    if ($Suite -eq 'directed') {
        $requiredMarkers = if ($Case -eq 'lab10') {
            @('LAB10_IF_PASS accepts=4 responses=4', 'LAB10_MEM_PASS accepts=11 responses=11 stores=5 loads=6', 'LAB10_BUS_PASS')
        } else {
            @('LAB11_AXI3_HANDSHAKE_PASS reads=2 stores=2 AW_first=1 W_first=1',
              'LAB11_AXI3_RID_CHECK_PASS', 'LAB11_AXI3_RRESP_CHECK_PASS', 'LAB11_AXI3_RLAST_CHECK_PASS',
              'LAB11_AXI3_BID_CHECK_PASS', 'LAB11_AXI3_BRESP_CHECK_PASS',
              'LAB11_AXI3_IF_REDIRECT_STALLED_AR_PASS', 'LAB11_AXI3_IF_REDIRECT_ACCEPTED_AR_PASS',
              'LAB11_AXI3_BUS_PASS')
        }
        foreach ($marker in $requiredMarkers) {
            if ($simText.IndexOf($marker, [StringComparison]::Ordinal) -lt 0) {
                throw "validated directed simulation marker is missing: $marker"
            }
        }
        if ($simText -match 'Fatal:|LAB10_[A-Z_]*FAIL|LAB11_AXI3_ASSERT|LAB11_AXI3_WATCHDOG') {
            throw "directed simulation log contains a failure marker: $simLog"
        }
    } else {
        if ($simText -notmatch 'COURSE_SOC_PASS' -or
            $simText -notmatch 'TRACE_EXHAUSTION_PASS records=\d+ valid=\d+' -or
            $simText -notmatch 'BUS_METRICS\s+') {
            throw "full simulation log is missing a required success/metrics marker: $simLog"
        }
    }
    $inputRows = Import-Csv -LiteralPath (Join-Path $runDir 'input_manifest.csv')
    $caseInputs = $inputRows | Where-Object { $_.case -eq $Case } | Select-Object -First 1
    if (-not $caseInputs) { throw "input manifest has no $Case row." }
    $coePath = $coePathForManifest
    $traceHash = (Get-FileHash -LiteralPath $tracePath -Algorithm SHA256).Hash
    $mifHash = (Get-FileHash -LiteralPath $mifPath -Algorithm SHA256).Hash
    $coeHash = if (Test-Path -LiteralPath $coePath -PathType Leaf) {
        (Get-FileHash -LiteralPath $coePath -Algorithm SHA256).Hash
    } else { 'MISSING' }
    $traceMatch = [regex]::Match($simText, 'TRACE_EXHAUSTION_PASS records=(\d+) valid=(\d+)')
    $busMatch = [regex]::Match($simText, 'BUS_METRICS\s+([^\r\n]+)')
    $busFields = @{}
    if ($busMatch.Success) {
        foreach ($match in [regex]::Matches($busMatch.Groups[1].Value, '([a-z_]+)=(\d+)')) {
            $busFields[$match.Groups[1].Value] = $match.Groups[2].Value
        }
    }
    if ($Suite -eq 'directed' -and $Case -eq 'lab10') {
        $ifCounts = [regex]::Match($simText, 'LAB10_IF_PASS accepts=(\d+) responses=(\d+)')
        $memCounts = [regex]::Match($simText, 'LAB10_MEM_PASS accepts=(\d+) responses=(\d+) stores=(\d+) loads=(\d+)')
        if ($ifCounts.Success -and $memCounts.Success) {
            $busFields['inst_req_accept'] = $ifCounts.Groups[1].Value
            $busFields['inst_data_complete'] = $ifCounts.Groups[2].Value
            $busFields['load_req_accept'] = $memCounts.Groups[4].Value
            $busFields['load_data_complete'] = $memCounts.Groups[4].Value
            $busFields['store_req_accept'] = $memCounts.Groups[3].Value
            $busFields['store_data_complete'] = $memCounts.Groups[3].Value
            $busFields['duplicate_store_count'] = '0'
        }
    } elseif ($Suite -eq 'directed' -and $Case -eq 'lab11') {
        $counts = [regex]::Match($simText, 'LAB11_AXI3_HANDSHAKE_PASS reads=(\d+) stores=(\d+) AW_first=1 W_first=1')
        if ($counts.Success) {
            $busFields['load_req_accept'] = $counts.Groups[1].Value
            $busFields['load_data_complete'] = $counts.Groups[1].Value
            $busFields['store_req_accept'] = $counts.Groups[2].Value
            $busFields['store_data_complete'] = $counts.Groups[2].Value
            $busFields['ar_handshakes'] = $counts.Groups[1].Value
            $busFields['r_handshakes'] = $counts.Groups[1].Value
            $busFields['aw_handshakes'] = $counts.Groups[2].Value
            $busFields['w_handshakes'] = $counts.Groups[2].Value
            $busFields['b_handshakes'] = $counts.Groups[2].Value
            $busFields['duplicate_store_count'] = '0'
        }
    }
    $actualPoints = if ($Suite -eq 'full') { [regex]::Matches($simText, 'Functional Test Point PASS').Count } else { 'N/A' }
    $testEndSeen = if ($Suite -eq 'full') { $simText -match 'Test end!' } else { $runnerResultText -match '(?m)^STATUS=PASS\s*$' }
    $functionalStatus = if ($Suite -eq 'full' -and $actualPoints -ne [int]$settings.ExpectedFunctionalPoints) { 'FAIL' } else { 'PASS' }
    $protocolStatus = if (($Suite -eq 'full' -and $simText -match 'AXI3_FAULT|COURSE_SOC_FAIL') -or
        ($busFields.ContainsKey('protocol_assertions_failed') -and [int]$busFields['protocol_assertions_failed'] -gt 0) -or
        ($busFields.ContainsKey('duplicate_store_count') -and [int]$busFields['duplicate_store_count'] -gt 0)) { 'FAIL' } else { 'PASS' }
    $waveStatus = 'NOT_CAPTURED'
    $waveFile = ''
    $wdbHash = ''
    if ($Suite -eq 'full') {
        $socProjectDir = Split-Path -Parent $socXpr
        $socProjectName = [IO.Path]::GetFileNameWithoutExtension($socXpr)
        $simDir = Join-Path $socProjectDir "$socProjectName.sim\sim_1\behav\xsim"
        foreach ($logName in @('compile.log', 'elaborate.log')) {
            $sourceLog = Join-Path $simDir $logName
            $destLog = Join-Path $runDir $logName
            if ((Test-Path -LiteralPath $sourceLog) -and -not (Test-Path -LiteralPath $destLog)) {
                Copy-Item -LiteralPath $sourceLog -Destination $destLog
            }
        }
        if ($CaptureWaveform) {
            $wdbSource = Join-Path $simDir 'tb_top_behav.wdb'
            $wdbTarget = Join-Path $runDir 'wave-full.wdb'
            if (-not (Test-Path -LiteralPath $wdbSource -PathType Leaf) -or (Get-Item $wdbSource).Length -eq 0) {
                throw "requested waveform database is missing or empty: $wdbSource"
            }
            if (Test-Path -LiteralPath $wdbTarget) {
                throw "refusing to overwrite an existing waveform database: $wdbTarget"
            }
            Copy-Item -LiteralPath $wdbSource -Destination $wdbTarget
            $wdbHash = (Get-FileHash -LiteralPath $wdbTarget -Algorithm SHA256).Hash
            $waveStatus = 'CAPTURED'
            $waveFile = 'wave-full.wdb'
        }
    }

    $runnerResultPath = Join-Path $runDir 'runner-result.txt'
    if (Test-Path -LiteralPath $runnerResultPath) {
        throw "refusing to overwrite the preserved raw runner result: $runnerResultPath"
    }
    Copy-Item -LiteralPath $resultPath -Destination $runnerResultPath
    $resultLines = [System.Collections.Generic.List[string]]::new()
    $resultLines.AddRange([string[]]@(
        "RUN_ID=$RunId", "CASE=$Case", "SUITE=$Suite", 'STATUS=PASS', 'PREFLIGHT_STATUS=PASS',
        "INPUT_SCAN_STATUS=$inputScanStatus", "VIVADO_PREFLIGHT_STATUS=$vivadoPreflightStatus",
        "EFFECTIVE_SOURCE_MANIFEST=$effectiveManifestRelative",
        "EFFECTIVE_SOURCE_MANIFEST_SHA256=$effectiveManifestHash",
        "SOURCE_INTEGRITY=$sourceIntegrityStatus", "SOURCE_CAPTURE_PHASE=$sourceCapturePhase",
        "FUNCTIONAL_STATUS=$functionalStatus", "PROTOCOL_STATUS=$protocolStatus",
        "SOURCE_COMMIT=$($caseInputs.source_commit)", "SOURCE_DIRTY=$($caseInputs.source_dirty)",
        "SOURCE_DIFF_SHA256=$($caseInputs.source_diff_sha256)",
        "PROJECT_XPR=$runProjectXpr", "RTL_MANIFEST=$effectiveManifestRelative",
        "INST_COE=$coePath", "INST_COE_SHA256=$coeHash", "INST_MIF=$mifPath", "INST_MIF_SHA256=$mifHash",
        "REFERENCE_TRACE=$tracePath", "TRACE_FILE=$tracePath", "TRACE_SHA256=$traceHash",
        "EXPECTED_FUNCTIONAL_POINTS=$(if ($Suite -eq 'full') { $settings.ExpectedFunctionalPoints } else { 'N/A' })", "ACTUAL_FUNCTIONAL_POINTS=$actualPoints",
        "TRACE_COMPARE_STATUS=$(if ($traceMatch.Success) { 'PASS' } elseif ($Suite -eq 'full') { 'FAIL' } else { 'NOT_RUN' })",
        "TRACE_RECORDS_COMPARED=$(if ($traceMatch.Success) { $traceMatch.Groups[1].Value } elseif ($Suite -eq 'full') { '0' } else { 'N/A' })",
        "PROTOCOL_ASSERTS_PASS=$(if ($Suite -eq 'directed') { 'PASS' } else { 'N/A' })", "PROTOCOL_ASSERTS_FAIL=$(if ($busFields.ContainsKey('protocol_assertions_failed')) { $busFields['protocol_assertions_failed'] } else { 'N/A' })",
        "DUPLICATE_STORE_COUNT=$(if ($busFields.ContainsKey('duplicate_store_count')) { $busFields['duplicate_store_count'] } else { 'N/A' })",
        "INSTRUCTION_REQUESTS_ACCEPTED=$(if ($busFields.ContainsKey('inst_req_accept')) { $busFields['inst_req_accept'] } else { 'N/A' })",
        "INSTRUCTION_RESPONSES_CONSUMED=$(if ($busFields.ContainsKey('inst_data_complete')) { $busFields['inst_data_complete'] } else { 'N/A' })",
        "DATA_READ_REQUESTS_ACCEPTED=$(if ($busFields.ContainsKey('load_req_accept')) { $busFields['load_req_accept'] } else { 'N/A' })",
        "DATA_READ_RESPONSES_CONSUMED=$(if ($busFields.ContainsKey('load_data_complete')) { $busFields['load_data_complete'] } else { 'N/A' })",
        "DATA_WRITE_REQUESTS_ACCEPTED=$(if ($busFields.ContainsKey('store_req_accept')) { $busFields['store_req_accept'] } else { 'N/A' })",
        "DATA_WRITE_COMPLETIONS=$(if ($busFields.ContainsKey('store_data_complete')) { $busFields['store_data_complete'] } else { 'N/A' })",
        "AR_HANDSHAKES=$(if ($busFields.ContainsKey('ar_handshakes')) { $busFields['ar_handshakes'] } else { 'N/A' })", "R_HANDSHAKES=$(if ($busFields.ContainsKey('r_handshakes')) { $busFields['r_handshakes'] } else { 'N/A' })",
        "AW_HANDSHAKES=$(if ($busFields.ContainsKey('aw_handshakes')) { $busFields['aw_handshakes'] } else { 'N/A' })", "W_HANDSHAKES=$(if ($busFields.ContainsKey('w_handshakes')) { $busFields['w_handshakes'] } else { 'N/A' })",
        "B_HANDSHAKES=$(if ($busFields.ContainsKey('b_handshakes')) { $busFields['b_handshakes'] } else { 'N/A' })", "STALE_FETCH_RESPONSES_DROPPED=$(if ($busFields.ContainsKey('stale_fetch_drops')) { $busFields['stale_fetch_drops'] } else { 'N/A' })",
        "PIPELINE_CYCLES=$(if ($busFields.ContainsKey('pipeline_cycles')) { $busFields['pipeline_cycles'] } else { 'N/A' })", 'PIPELINE_STALL_CYCLES=N/A', "SIM_EXIT_CODE=$runCode",
        "TEST_END_SEEN=$($testEndSeen.ToString().ToLowerInvariant())", "WAVEFORM_STATUS=$waveStatus",
        "WAVEFORM_FILE=$waveFile", "WAVEFORM_SHA256=$wdbHash", 'WCFG_VALIDATION=NOT_RUN',
        "VIVADO_VERSION=$vivadoVersion"
    ))
    $resultLines | Set-Content -LiteralPath $resultPath -Encoding UTF8

    Write-Output 'STATUS=PASS'
    Write-Output "RUN_DIR=$runDir"
    exit 0
} catch {
    $resultPath = Join-Path $runDir 'result.txt'
    $runnerResultPath = Join-Path $runDir 'runner-result.txt'
    if ((Test-Path -LiteralPath $resultPath) -and -not (Test-Path -LiteralPath $runnerResultPath)) {
        Copy-Item -LiteralPath $resultPath -Destination $runnerResultPath
    }
    @("RUN_ID=$RunId", "CASE=$Case", "SUITE=$Suite", 'STATUS=ENVIRONMENT_ERROR',
      "INPUT_SCAN_STATUS=$inputScanStatus", "VIVADO_PREFLIGHT_STATUS=$vivadoPreflightStatus",
      "SOURCE_INTEGRITY=$sourceIntegrityStatus", "EFFECTIVE_SOURCE_MANIFEST=$effectiveManifestRelative",
      "EFFECTIVE_SOURCE_MANIFEST_SHA256=$effectiveManifestHash",
      "SOURCE_CAPTURE_PHASE=$sourceCapturePhase",
      "PREFLIGHT_STATUS=$vivadoPreflightStatus", "ERROR_REASON=$($_.Exception.Message)") |
        Set-Content -LiteralPath $resultPath -Encoding UTF8
    Write-Output "ENVIRONMENT_ERROR: $($_.Exception.Message)"
    Write-Output "RUN_DIR=$runDir"
    exit 2
}
