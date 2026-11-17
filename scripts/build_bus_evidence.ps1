[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('lab10', 'lab11')][string]$Case,
    [Parameter(Mandatory)][string]$RunId,
    [ValidateRange(1, 99)][int]$Attempt = 1,
    [string]$VivadoBin = 'D:\Verilog\2025.2\Vivado\bin\vivado.bat'
)

$ErrorActionPreference = 'Stop'
$labRoot = Split-Path -Parent $PSScriptRoot
$builder = Join-Path $PSScriptRoot 'build_bus_evidence.py'
if (-not (Test-Path -LiteralPath $builder -PathType Leaf)) {
    throw "evidence builder is missing: $builder"
}
$python = Get-Command python -ErrorAction Stop
$arguments = @($builder, '--repo-root', $labRoot, '--case', $Case, '--run-id', $RunId,
    '--attempt', "$Attempt")
if ($VivadoBin) { $arguments += @('--vivado-bin', $VivadoBin) }
& $python.Source @arguments
if ($LASTEXITCODE -ne 0) {
    throw "build_bus_evidence.py failed with exit code $LASTEXITCODE. Keep its logs and inspect the selected Run."
}
