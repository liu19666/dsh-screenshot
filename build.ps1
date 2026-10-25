# Builds the native capture tool (net48 / csc, no extra runtime required).
#   pwsh -File build.ps1          -> bin/SnipTool.exe
#   pwsh -File build.ps1 -Tests   -> bin/SnipTool.exe + bin/EngineTests.exe
[CmdletBinding()]
param(
    [string]$OutDir,
    [switch]$Tests
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
if (-not $OutDir) { $OutDir = Join-Path $root 'bin' }

$csc = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { throw "csc.exe not found: $csc" }

$refs = @('/r:System.dll', '/r:System.Drawing.dll', '/r:System.Windows.Forms.dll', '/r:System.Core.dll')
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Invoke-Csc {
    param([string]$Out, [string]$Target, [string[]]$Sources)
    $argv = @('/nologo', "/target:$Target", "/out:$Out", '/platform:anycpu', '/optimize+') + $refs + $Sources
    & $csc @argv
    if ($LASTEXITCODE -ne 0) { throw "csc failed (exit $LASTEXITCODE) -> $Out" }
}

$all = Get-ChildItem -Path (Join-Path $root 'src') -Filter *.cs -Recurse | Sort-Object FullName
$mainSources = @($all | Where-Object { $_.Name -ne 'EngineTests.cs' } | ForEach-Object { $_.FullName })
$testSources = @($all | Where-Object { $_.Name -eq 'EngineTests.cs' -or $_.Name -eq 'Detect.cs' -or $_.Name -eq 'LongShot.cs' } | ForEach-Object { $_.FullName })

Invoke-Csc -Out (Join-Path $OutDir 'SnipTool.exe') -Target 'winexe' -Sources $mainSources
Write-Host ("built " + (Join-Path $OutDir 'SnipTool.exe'))

if ($Tests) {
    Invoke-Csc -Out (Join-Path $OutDir 'EngineTests.exe') -Target 'exe' -Sources $testSources
    Write-Host ("built " + (Join-Path $OutDir 'EngineTests.exe'))
}
