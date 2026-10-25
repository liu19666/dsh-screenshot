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

# Compiles to a scratch file and then swaps it into place with retries.
# Rationale: a just-exited SnipTool.exe (warm server, --selftest, --longshot-probe) or an
# antivirus scan can keep the previous image locked for a moment; csc then fails with
# "error CS0016: could not write to output file ... being used by another process".
# That is a timing artefact, not a build error, so retry the swap instead of failing.
function Invoke-Csc {
    param([string]$Out, [string]$Target, [string[]]$Sources)
    $tmp = Join-Path (Split-Path -Parent $Out) (([System.IO.Path]::GetFileName($Out)) + '.build-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.tmp')
    $argv = @('/nologo', "/target:$Target", "/out:$tmp", '/platform:anycpu', '/optimize+') + $refs + $Sources
    & $csc @argv
    if ($LASTEXITCODE -ne 0) {
        Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
        throw "csc failed (exit $LASTEXITCODE) -> $Out"
    }
    $lastErr = $null
    for ($i = 0; $i -lt 10; $i++) {
        try {
            Move-Item -LiteralPath $tmp -Destination $Out -Force -ErrorAction Stop
            return
        } catch {
            $lastErr = $_
            Start-Sleep -Milliseconds 400
        }
    }
    Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
    throw ("cannot replace '" + $Out + "' - it is locked by a running process. " +
           "Close any SnipTool.exe instance (taskkill /IM SnipTool.exe /F) and rebuild. Details: " +
           $lastErr.Exception.Message)
}

$all = Get-ChildItem -Path (Join-Path $root 'src') -Filter *.cs -Recurse | Sort-Object FullName
$mainSources = @($all | Where-Object { $_.Name -ne 'EngineTests.cs' } | ForEach-Object { $_.FullName })
$testSources = @($all | Where-Object { $_.Name -eq 'EngineTests.cs' -or $_.Name -eq 'Detect.cs' } | ForEach-Object { $_.FullName })

Invoke-Csc -Out (Join-Path $OutDir 'SnipTool.exe') -Target 'winexe' -Sources $mainSources
Write-Host ("built " + (Join-Path $OutDir 'SnipTool.exe'))

if ($Tests) {
    Invoke-Csc -Out (Join-Path $OutDir 'EngineTests.exe') -Target 'exe' -Sources $testSources
    Write-Host ("built " + (Join-Path $OutDir 'EngineTests.exe'))
}
