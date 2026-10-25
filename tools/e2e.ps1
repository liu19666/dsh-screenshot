#Requires -Version 7.0
<#
.SYNOPSIS
  DSH screenshot plugin v2 — one-shot, reproducible evidence chain.

.DESCRIPTION
  Runs the v2 verification pipeline in order and writes a machine readable report:

    1. preflight     toolchain + repository facts (pwsh / node / pnpm / csc / git / profile)
    2. build         pwsh -File build.ps1 -Tests              -> bin/SnipTool.exe, bin/EngineTests.exe
    3. engine        bin/EngineTests.exe --json ... --png ... -> engine.json + PNG evidence
    4. selftest      bin/SnipTool.exe --selftest <dir>        -> overlay/editor PNG evidence
    5. crash-probe   bin/SnipTool.exe --crash-probe <dir>     -> crash_probe.json (log grows, ok=true)
    6. plugin        node tools/plugin-smoke.mjs --json ...   -> stub-load check of both plugin halves
    7. install-plan  pwsh -File install.ps1 -WhatIf           -> plan must print, nothing may change
    8. package       npm pack                                 -> dsh-screenshot-<version>.tgz + files whitelist
    9. docs          VERIFY.md covers R1..R30, RELEASE.md covers release sections

  Output (unless -OutDir says otherwise; a relative -OutDir is resolved against the REPO ROOT):
    out/evidence/report.json    machine readable report (schema dsh-screenshot-evidence/v2)
    out/evidence/SUMMARY.md     human summary of the same run
    out/evidence/logs/*.log     stdout/stderr of every external command

  Step statuses
    pass     ran and met its criteria
    pending  the owning module is not implemented yet (reported, NOT a failure)
    fail     ran and did not meet its criteria (or a required artifact is missing)
    skipped  not run because an earlier prerequisite failed or a -Skip* switch was used

  Exit code
    0  every executed step passed; pending steps are tolerated
    1  at least one step failed, or -Strict was used and something is pending

  -DryRun only validates the wiring: it checks that every file and tool the pipeline
  references exists, prints the exact command line of every step, and writes
  out/evidence/dryrun/report.json + SUMMARY.md. It never builds, never launches the
  native tool, never touches the DSH profile, and exits 0 when the wiring is sound.

.PARAMETER DryRun
  Wiring self-check only. Writes out/evidence/dryrun/ and executes no pipeline command.

.PARAMETER Strict
  Treat pending steps as failures (use this once every module is supposed to be done).

.PARAMETER SkipBuild
  Do not rebuild; use the binaries already in bin/. Steps that need a missing binary are skipped.

.PARAMETER SkipNative
  Skip the native steps (engine, selftest, crash-probe) — plugin/docs only.

.PARAMETER OutDir
  Evidence directory. Defaults to out/evidence (run) or out/evidence/dryrun (-DryRun).
  A RELATIVE value is always resolved against the repository root (the parent of this script's
  folder), never against the caller's cwd, so "cd <repo>; ... -OutDir out/evidence-x" and
  "cd <workspace>; pwsh -File <repo>/tools/e2e.ps1 -OutDir out/evidence-x" write to the same
  place. The resolved path must stay inside the checkout; anything else is refused with exit 2.

.PARAMETER SelftestTimeoutSec
  Hard kill for the overlay selftest (a hanging GUI must not hang this harness).

.PARAMETER CrashProbeTimeoutSec
  Hard kill for "--crash-probe" (it must never hang the chain).

.PARAMETER LongShotTimeoutSec
  Hard kill for "--longshot-probe" (a real long-shot stitch that hangs must not hang the chain).

.PARAMETER PackageTimeoutSec
  Hard kill for "npm pack" (a wedged npm must not hang the evidence chain).

.EXAMPLE
  pwsh -NoProfile -File tools/e2e.ps1

.EXAMPLE
  pwsh -NoProfile -File tools/e2e.ps1 -DryRun

.EXAMPLE
  pwsh -NoProfile -File tools/e2e.ps1 -Strict -OutDir out/evidence-strict

.EXAMPLE
  # -OutDir is repo-relative no matter where you call it from:
  # both lines below write to <repo>/out/evidence-review
  cd <repo>; pwsh -NoProfile -File tools/e2e.ps1 -OutDir out/evidence-review
  cd <workspace>; pwsh -NoProfile -File <repo>/tools/e2e.ps1 -OutDir out/evidence-review
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Strict,
    [switch]$SkipBuild,
    [switch]$SkipNative,
    [string]$OutDir,
    [int]$BuildTimeoutSec = 300,
    [int]$EngineTimeoutSec = 180,
    [int]$SelftestTimeoutSec = 240,
    [int]$CrashProbeTimeoutSec = 120,
    [int]$LongShotTimeoutSec = 120,
    [int]$PluginTimeoutSec = 180,
    [int]$InstallTimeoutSec = 120,
    [int]$PackageTimeoutSec = 180,
    [int]$MinSelftestPngs = 6
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$script:NL = [string][char]10
$script:BT = [string][char]96
$script:Root = Split-Path -Parent $PSScriptRoot
$script:ToolsDir = $PSScriptRoot
# N-9: a relative -OutDir is resolved against the REPOSITORY ROOT ($PSScriptRoot/..), never the
# caller's cwd. Before this, "tools/e2e.ps1 -OutDir out/review" run from the workspace root wrote
# its evidence into <workspace>/out (outside the checkout) with no warning.
if ($OutDir) {
    if ([System.IO.Path]::IsPathRooted($OutDir)) {
        $script:OutRoot = [System.IO.Path]::GetFullPath($OutDir)
    } else {
        $script:OutRoot = [System.IO.Path]::GetFullPath((Join-Path $script:Root $OutDir))
    }
} elseif ($DryRun) {
    $script:OutRoot = Join-Path $script:Root 'out/evidence/dryrun'
} else {
    $script:OutRoot = Join-Path $script:Root 'out/evidence'
}
# N-9: refuse to scatter evidence outside the checkout (repo discipline: never write outside it).
$script:RootFull = [System.IO.Path]::GetFullPath($script:Root).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
$script:OutRootFull = [System.IO.Path]::GetFullPath($script:OutRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
$script:OutRootInsideRepo = ($script:OutRootFull.Equals($script:RootFull, [System.StringComparison]::OrdinalIgnoreCase)) -or
    $script:OutRootFull.StartsWith(($script:RootFull + [System.IO.Path]::DirectorySeparatorChar), [System.StringComparison]::OrdinalIgnoreCase)
if (-not $script:OutRootInsideRepo) {
    Write-Host ''
    Write-Host '  e2e: -OutDir must stay inside the repository root.' -ForegroundColor Red
    Write-Host ('    repository root : ' + $script:RootFull) -ForegroundColor Red
    Write-Host ('    resolved OutDir : ' + $script:OutRootFull) -ForegroundColor Red
    Write-Host '    A relative -OutDir is resolved against the repository root (not the cwd);' -ForegroundColor Red
    Write-Host '    pass e.g. -OutDir out/evidence-review or an absolute path inside the checkout.' -ForegroundColor Red
    Write-Host ''
    exit 2
}
$script:PwshExe = (Get-Process -Id $PID).Path
if (-not $script:PwshExe) { $script:PwshExe = 'pwsh' }
$script:Steps = [System.Collections.Generic.List[object]]::new()
$script:Facts = $null
$script:StartedAt = Get-Date
$script:CscPath = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$script:ProfileDir = Join-Path $env:USERPROFILE '.dsh/profiles/desktop'

# ---------------------------------------------------------------------------------
# small helpers
# ---------------------------------------------------------------------------------

function Get-RelPath {
    param([string]$Path)
    if (-not $Path) { return '' }
    try {
        $abs = [System.IO.Path]::GetFullPath($Path)
        return [System.IO.Path]::GetRelativePath($script:Root, $abs).Replace('\', '/')
    } catch {
        return $Path
    }
}

function Write-StatusLabel {
    param([string]$Status)
    switch ($Status) {
        'pass' { return 'PASS' }
        'fail' { return 'FAIL' }
        'pending' { return 'PENDING' }
        'skipped' { return 'SKIP' }
        'planned' { return 'PLAN' }
        default { return ([string]$Status).ToUpperInvariant() }
    }
}

function Add-Step {
    param(
        [string]$Id,
        [string]$Title,
        [string]$Status,
        [string]$Detail = '',
        [object]$ExitCode = $null,
        [int]$DurationMs = 0,
        [string]$Command = '',
        [object[]]$Artifacts = @(),
        [string[]]$Warnings = @(),
        [string]$Log = ''
    )
    $step = [pscustomobject][ordered]@{
        id         = $Id
        title      = $Title
        status     = $Status
        exitCode   = $ExitCode
        durationMs = $DurationMs
        command    = $Command
        artifacts  = @($Artifacts)
        warnings   = @($Warnings)
        detail     = $Detail
        log        = $Log
    }
    $script:Steps.Add($step)
    $label = (Write-StatusLabel $Status).PadRight(7)
    Write-Host ("[{0}] {1,-13} {2}" -f $label, $Id, $Title)
    if ($Detail) { Write-Host ("          " + $Detail) }
    foreach ($w in $Warnings) { Write-Host ("          warn: " + $w) }
    return $step
}

function Get-HostFacts {
    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue | Select-Object -First 1
    $pnpmCmd = Get-Command pnpm -ErrorAction SilentlyContinue | Select-Object -First 1
    $nodeVersion = $null
    if ($nodeCmd) {
        try { $nodeVersion = (& $nodeCmd.Source --version 2>$null | Select-Object -First 1) } catch { $nodeVersion = $null }
    }
    $pnpmVersion = $null
    if ($pnpmCmd) {
        try { $pnpmVersion = (& $pnpmCmd.Source --version 2>$null | Select-Object -First 1) } catch { $pnpmVersion = $null }
    }
    $gitHead = $null
    $gitDirty = $null
    if (Test-Path (Join-Path $script:Root '.git')) {
        try {
            $gitHead = (& git -C $script:Root rev-parse --short HEAD 2>$null | Select-Object -First 1)
            $porcelain = @(& git -C $script:Root status --porcelain 2>$null)
            $gitDirty = $porcelain.Count
        } catch { }
    }
    return [pscustomobject][ordered]@{
        os         = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
        computer   = $env:COMPUTERNAME
        pwsh       = $PSVersionTable.PSVersion.ToString()
        pwshPath   = $script:PwshExe
        node       = $nodeVersion
        nodePath   = $(if ($nodeCmd) { $nodeCmd.Source } else { $null })
        pnpm       = $pnpmVersion
        csc        = $(if (Test-Path $script:CscPath) { $script:CscPath } else { $null })
        gitHead    = $gitHead
        gitDirty   = $gitDirty
        profileDir = $script:ProfileDir
        profileOk  = (Test-Path (Join-Path $script:ProfileDir 'package.json'))
    }
}

function Format-CommandLine {
    param([string]$FilePath, [string[]]$ArgumentList)
    $parts = @()
    foreach ($a in $ArgumentList) {
        if ($a -match '[\s"]') { $parts += ('"' + ($a -replace '"', '\"') + '"') } else { $parts += $a }
    }
    return ((Split-Path -Leaf $FilePath) + ' ' + ($parts -join ' ')).Trim()
}

function Invoke-Process {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$WorkingDirectory = $script:Root,
        [int]$TimeoutSec = 120
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $commandLine = Format-CommandLine -FilePath $FilePath -ArgumentList $ArgumentList
    $result = [pscustomobject][ordered]@{
        filePath    = $FilePath
        args        = $ArgumentList
        commandLine = $commandLine
        exitCode    = $null
        timedOut    = $false
        durationMs  = 0
        stdout      = ''
        stderr      = ''
        startError  = $null
    }
    if (-not (Test-Path -LiteralPath $FilePath)) {
        $result.startError = "executable not found: $FilePath"
        $result.exitCode = -2
        $result.durationMs = [int]$sw.ElapsedMilliseconds
        return $result
    }
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FilePath
    foreach ($a in $ArgumentList) { $psi.ArgumentList.Add([string]$a) }
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    try {
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    } catch { }
    $proc = $null
    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
    } catch {
        $result.startError = "failed to start: " + $_.Exception.Message
        $result.exitCode = -2
        $result.durationMs = [int]$sw.ElapsedMilliseconds
        return $result
    }
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()
    if ($TimeoutSec -gt 0) {
        if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
            $result.timedOut = $true
            try { $proc.Kill($true) } catch { try { $proc.Kill() } catch { } }
            try { [void]$proc.WaitForExit(5000) } catch { }
        }
    } else {
        $proc.WaitForExit()
    }
    foreach ($t in @($outTask, $errTask)) {
        try { [void]$t.Wait(3000) } catch { }
    }
    if ($outTask.IsCompleted) { $result.stdout = [string]$outTask.Result }
    if ($errTask.IsCompleted) { $result.stderr = [string]$errTask.Result }
    if (-not $result.timedOut) {
        try { $result.exitCode = $proc.ExitCode } catch { $result.exitCode = -3 }
    } else {
        $result.exitCode = -1
    }
    $result.durationMs = [int]$sw.ElapsedMilliseconds
    try { $proc.Dispose() } catch { }
    return $result
}

function Write-CommandLog {
    param([string]$Id, [object]$Run, [string]$Title)
    $logDir = Join-Path $script:OutRoot 'logs'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $path = Join-Path $logDir ($Id + '.log')
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("# step : $Id  ($Title)")
    [void]$sb.AppendLine("# when : " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'))
    [void]$sb.AppendLine("# cwd  : " + $script:Root)
    [void]$sb.AppendLine("# cmd  : " + $Run.commandLine)
    [void]$sb.AppendLine("# exit : " + $Run.exitCode + "   timedOut=" + $Run.timedOut + "   ms=" + $Run.durationMs)
    [void]$sb.AppendLine(('=' * 78))
    [void]$sb.AppendLine('--- stdout ---')
    [void]$sb.AppendLine([string]$Run.stdout)
    [void]$sb.AppendLine('--- stderr ---')
    [void]$sb.AppendLine([string]$Run.stderr)
    Set-Content -LiteralPath $path -Value $sb.ToString() -Encoding utf8NoBOM
    return (Get-RelPath $path)
}

function Get-Tail {
    param([string]$Text, [int]$Lines = 6)
    if (-not $Text) { return '' }
    $all = @($Text -split "[\r\n]+" | Where-Object { $_.Trim().Length -gt 0 })
    if ($all.Count -le $Lines) { return ($all -join ' | ') }
    return (($all | Select-Object -Last $Lines) -join ' | ')
}

function Test-NativeSwitchImplemented {
    param([string]$Switch)
    # A CLI switch only counts when it appears in code, not in a comment: until it exists the
    # executable would start the real overlay instead of the evidence mode, so probe the source.
    $srcDir = Join-Path $script:Root 'src'
    $needle = ([string][char]34) + $Switch + ([string][char]34)
    $hits = @()
    if (Test-Path $srcDir) {
        foreach ($file in (Get-ChildItem -Path $srcDir -Filter *.cs -Recurse -File)) {
            $text = Get-Content -LiteralPath $file.FullName -Raw
            if (-not $text) { continue }
            $stripped = [regex]::Replace($text, '/\*[\s\S]*?\*/', '')
            $stripped = [regex]::Replace($stripped, '//[^\r\n]*', '')
            if ($stripped.Contains($needle)) { $hits += $file.Name }
        }
    }
    return [pscustomobject]@{ implemented = ($hits.Count -gt 0); files = $hits }
}

function Test-SelftestImplemented {
    # The overlay selftest (src/SelfTest.cs) launches the real overlay when the switch is absent.
    return Test-NativeSwitchImplemented '--selftest'
}

function Get-PngInfo {
    param([string]$Path)
    $info = [pscustomobject][ordered]@{ name = (Split-Path -Leaf $Path); bytes = 0; width = $null; height = $null; ok = $false }
    try { $info.bytes = (Get-Item -LiteralPath $Path).Length } catch { return $info }
    try {
        if (-not ('System.Drawing.Bitmap' -as [type])) { Add-Type -AssemblyName System.Drawing }
        $img = [System.Drawing.Image]::FromFile($Path)
        try {
            $info.width = $img.Width
            $info.height = $img.Height
            $info.ok = $true
        } finally { $img.Dispose() }
    } catch {
        # Without System.Drawing a PNG that is at least a few hundred bytes is accepted.
        $info.ok = ($info.bytes -gt 512)
    }
    return $info
}

function Test-MissingRel {
    param([string]$RelPath)
    return (-not (Test-Path -LiteralPath (Join-Path $script:Root $RelPath)))
}

# ---------------------------------------------------------------------------------
# step 1: preflight
# ---------------------------------------------------------------------------------
function Invoke-Preflight {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $facts = Get-HostFacts
    $script:Facts = $facts
    $warnings = @()
    $required = @('build.ps1', 'install.ps1', 'package.json', 'tools/plugin-smoke.mjs', 'docs/VERIFY.md', 'docs/RELEASE.md')
    $missing = @($required | Where-Object { Test-MissingRel $_ })
    if (-not $facts.csc) { $warnings += "csc.exe not found at $script:CscPath (native build cannot run)" }
    if (-not $facts.node) { $warnings += 'node is not on PATH (plugin smoke cannot run)' }
    if (-not $facts.pnpm) { $warnings += 'pnpm is not on PATH (install.ps1 real run will fail)' }
    if (-not $facts.profileOk) { $warnings += "desktop profile not found: $script:ProfileDir (install-plan still prints its plan)" }
    $detail = @(
        ('pwsh {0}' -f $facts.pwsh),
        ('node {0}' -f $facts.node),
        ('csc {0}' -f $(if ($facts.csc) { 'found' } else { 'MISSING' })),
        ('git {0} (+{1} dirty)' -f $facts.gitHead, $facts.gitDirty)
    ) -join '; '
    if ($missing.Count -gt 0) {
        return Add-Step -Id 'preflight' -Title 'environment + repository wiring' -Status 'fail' -Detail ("missing required file(s): " + ($missing -join ', ')) -DurationMs ([int]$sw.ElapsedMilliseconds) -Warnings $warnings
    }
    return Add-Step -Id 'preflight' -Title 'environment + repository wiring' -Status 'pass' -Detail $detail -DurationMs ([int]$sw.ElapsedMilliseconds) -Warnings $warnings
}

# ---------------------------------------------------------------------------------
# step 2: build
# ---------------------------------------------------------------------------------
function Invoke-BuildStep {
    if ($SkipBuild) {
        return Add-Step -Id 'build' -Title 'pwsh -File build.ps1 -Tests' -Status 'skipped' -Detail 'skipped by -SkipBuild'
    }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $buildScript = Join-Path $script:Root 'build.ps1'
    $run = Invoke-Process -FilePath $script:PwshExe -ArgumentList @('-NoProfile', '-File', $buildScript, '-Tests') -WorkingDirectory $script:Root -TimeoutSec $BuildTimeoutSec
    $log = Write-CommandLog -Id 'build' -Run $run -Title 'build -Tests'
    $exe = Join-Path $script:Root 'bin/SnipTool.exe'
    $engineExe = Join-Path $script:Root 'bin/EngineTests.exe'
    $artifacts = @(@($exe, $engineExe) | Where-Object { Test-Path -LiteralPath $_ } | ForEach-Object { Get-RelPath $_ })
    if ($run.timedOut) {
        return Add-Step -Id 'build' -Title 'pwsh -File build.ps1 -Tests' -Status 'fail' -Command $run.commandLine -Detail ("build timed out after {0}s" -f $BuildTimeoutSec) -ExitCode $run.exitCode -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
    }
    if ($run.exitCode -ne 0) {
        $tail = Get-Tail ($run.stdout + $script:NL + $run.stderr) 6
        return Add-Step -Id 'build' -Title 'pwsh -File build.ps1 -Tests' -Status 'fail' -Command $run.commandLine -Detail ("exit {0}: {1}" -f $run.exitCode, $tail) -ExitCode $run.exitCode -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
    }
    $missing = @()
    if (-not (Test-Path -LiteralPath $exe)) { $missing += 'bin/SnipTool.exe' }
    if (-not (Test-Path -LiteralPath $engineExe)) { $missing += 'bin/EngineTests.exe' }
    if ($missing.Count -gt 0) {
        return Add-Step -Id 'build' -Title 'pwsh -File build.ps1 -Tests' -Status 'fail' -Command $run.commandLine -Detail ("build exited 0 but did not produce: " + ($missing -join ', ')) -ExitCode 0 -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
    }
    return Add-Step -Id 'build' -Title 'pwsh -File build.ps1 -Tests' -Status 'pass' -Command $run.commandLine -Detail ("bin/SnipTool.exe + bin/EngineTests.exe built in {0:0.0}s" -f ($run.durationMs / 1000)) -ExitCode 0 -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
}

function Test-BuildReady {
    param([string]$Executable)
    if (-not (Test-Path -LiteralPath $Executable)) { return $false }
    if ($SkipBuild) { return $true }
    $build = $script:Steps | Where-Object { $_.id -eq 'build' } | Select-Object -First 1
    if ($null -eq $build) { return $true }
    return ($build.status -eq 'pass')
}

# ---------------------------------------------------------------------------------
# step 3: engine (EngineTests.exe)
# ---------------------------------------------------------------------------------
function Invoke-EngineStep {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $title = 'bin/EngineTests.exe (target detection + long-shot math)'
    $exe = Join-Path $script:Root 'bin/EngineTests.exe'
    if ($SkipNative) {
        return Add-Step -Id 'engine' -Title $title -Status 'skipped' -Detail 'skipped by -SkipNative'
    }
    if (-not (Test-BuildReady $exe)) {
        $build = $script:Steps | Where-Object { $_.id -eq 'build' } | Select-Object -First 1
        $why = if ($build -and $build.status -eq 'fail') { 'build failed, so the engine tests could not run' } else { 'bin/EngineTests.exe is missing (run without -SkipBuild)' }
        return Add-Step -Id 'engine' -Title $title -Status 'skipped' -Detail $why
    }
    $jsonPath = Join-Path $script:OutRoot 'engine.json'
    $pngDir = Join-Path $script:OutRoot 'png/engine'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $jsonPath) | Out-Null
    New-Item -ItemType Directory -Force -Path $pngDir | Out-Null
    $run = Invoke-Process -FilePath $exe -ArgumentList @('--json', $jsonPath, '--png', $pngDir) -WorkingDirectory $script:Root -TimeoutSec $EngineTimeoutSec
    $log = Write-CommandLog -Id 'engine' -Run $run -Title 'EngineTests --json/--png'
    $artifacts = @()
    if (Test-Path -LiteralPath $jsonPath) { $artifacts += (Get-RelPath $jsonPath) }
    $pngs = @(Get-ChildItem -Path $pngDir -Filter *.png -File -ErrorAction SilentlyContinue)
    if ($pngs.Count -gt 0) { $artifacts += (Get-RelPath $pngDir) }

    if ($run.startError) {
        return Add-Step -Id 'engine' -Title $title -Status 'fail' -Command $run.commandLine -Detail $run.startError -ExitCode $run.exitCode -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
    }
    if ($run.timedOut) {
        return Add-Step -Id 'engine' -Title $title -Status 'fail' -Command $run.commandLine -Detail ("timed out after {0}s" -f $EngineTimeoutSec) -ExitCode $run.exitCode -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
    }
    $json = $null
    if (Test-Path -LiteralPath $jsonPath) {
        try { $json = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json } catch { $json = $null }
    }
    if ($null -eq $json) {
        $detail = if ($run.exitCode -eq 2) { 'EngineTests exits 2 and writes no results yet (engine-dev not implemented)' } else { ("no parsable JSON at {0}; exit {1}: {2}" -f (Get-RelPath $jsonPath), $run.exitCode, (Get-Tail ($run.stdout + $script:NL + $run.stderr) 4)) }
        $status = if ($run.exitCode -eq 2) { 'pending' } else { 'fail' }
        return Add-Step -Id 'engine' -Title $title -Status $status -Command $run.commandLine -Detail $detail -ExitCode $run.exitCode -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
    }
    $implemented = $true
    if ($json.PSObject.Properties.Name -contains 'implemented') { $implemented = [bool]$json.implemented }
    $checks = @()
    if ($json.PSObject.Properties.Name -contains 'checks') { $checks = @($json.checks) }
    $checkNames = @($checks | ForEach-Object { $_.name } | Where-Object { $_ })
    if (-not $implemented -or ($run.exitCode -eq 2 -and $checks.Count -eq 0)) {
        $note = ''
        if ($json.PSObject.Properties.Name -contains 'note') { $note = [string]$json.note }
        $why = 'engine tests not implemented yet (implemented=false)'
        if ($note) { $why = $why + "; note: $note" }
        return Add-Step -Id 'engine' -Title $title -Status 'pending' -Command $run.commandLine -Detail $why -ExitCode $run.exitCode -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
    }
    $failed = @($checks | Where-Object { ($_.PSObject.Properties.Name -contains 'ok') -and (-not $_.ok) })
    if ($run.exitCode -eq 0 -and $json.ok -eq $true -and $failed.Count -eq 0) {
        $names = ''
        if ($checkNames.Count -gt 0) { $names = ': ' + (($checkNames | Select-Object -First 8) -join ', ') }
        return Add-Step -Id 'engine' -Title $title -Status 'pass' -Command $run.commandLine -Detail ("{0} checks passed{1}" -f $checks.Count, $names) -ExitCode 0 -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
    }
    $failureNames = @($failed | ForEach-Object { [string]$_.name })
    $failedText = if ($failureNames.Count) { $failureNames -join ', ' } else { '(none listed)' }
    return Add-Step -Id 'engine' -Title $title -Status 'fail' -Command $run.commandLine -Detail ("exit {0}, ok={1}; failed checks: {2}" -f $run.exitCode, $json.ok, $failedText) -ExitCode $run.exitCode -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
}

# ---------------------------------------------------------------------------------
# step 4: overlay selftest (SnipTool.exe --selftest)
# ---------------------------------------------------------------------------------
function Invoke-SelftestStep {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $title = 'bin/SnipTool.exe --selftest (overlay + editor evidence PNGs)'
    $exe = Join-Path $script:Root 'bin/SnipTool.exe'
    if ($SkipNative) {
        return Add-Step -Id 'selftest' -Title $title -Status 'skipped' -Detail 'skipped by -SkipNative'
    }
    if (-not (Test-BuildReady $exe)) {
        $build = $script:Steps | Where-Object { $_.id -eq 'build' } | Select-Object -First 1
        $why = if ($build -and $build.status -eq 'fail') { 'build failed, so the overlay selftest could not run' } else { 'bin/SnipTool.exe is missing (run without -SkipBuild)' }
        return Add-Step -Id 'selftest' -Title $title -Status 'skipped' -Detail $why
    }
    $probe = Test-SelftestImplemented
    if (-not $probe.implemented) {
        return Add-Step -Id 'selftest' -Title $title -Status 'pending' -Detail 'no non-comment "--selftest" switch in src/*.cs yet (overlay-dev not implemented); native tool not launched'
    }
    $outDir = Join-Path $script:OutRoot 'selftest'
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    # clean stale PNGs so a pass cannot be inherited from an earlier run
    Get-ChildItem -Path $outDir -Filter *.png -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    $run = Invoke-Process -FilePath $exe -ArgumentList @('--selftest', $outDir) -WorkingDirectory $script:Root -TimeoutSec $SelftestTimeoutSec
    $log = Write-CommandLog -Id 'selftest' -Run $run -Title 'SnipTool --selftest'
    $pngs = @(Get-ChildItem -Path $outDir -Filter *.png -File -ErrorAction SilentlyContinue | Sort-Object Name)
    $artifacts = @()
    if ($pngs.Count -gt 0) { $artifacts += (Get-RelPath $outDir) }
    if ($run.timedOut) {
        return Add-Step -Id 'selftest' -Title $title -Status 'fail' -Command $run.commandLine -Detail ("selftest did not exit within {0}s and was killed (a hanging GUI cannot block the evidence chain)" -f $SelftestTimeoutSec) -ExitCode $run.exitCode -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
    }
    if ($run.exitCode -ne 0) {
        return Add-Step -Id 'selftest' -Title $title -Status 'fail' -Command $run.commandLine -Detail ("exit {0}: {1}" -f $run.exitCode, (Get-Tail ($run.stdout + $script:NL + $run.stderr) 5)) -ExitCode $run.exitCode -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
    }
    if ($pngs.Count -eq 0) {
        return Add-Step -Id 'selftest' -Title $title -Status 'fail' -Command $run.commandLine -Detail ("exit 0 but no PNG was written to " + (Get-RelPath $outDir)) -ExitCode 0 -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
    }
    $details = @()
    $bad = @()
    foreach ($png in $pngs) {
        $info = Get-PngInfo $png.FullName
        $details += ("{0} ({1}x{2}, {3}B)" -f $info.name, $info.width, $info.height, $info.bytes)
        if (-not $info.ok) { $bad += $info.name }
        elseif ($info.bytes -lt 1500) { $bad += ($info.name + ' (too small to judge by eye)') }
        elseif (($null -ne $info.width) -and (($info.width -lt 120) -or ($info.height -lt 40))) { $bad += ($info.name + ' (dimensions too small to judge by eye)') }
    }
    $summary = ("{0} PNGs: {1}" -f $pngs.Count, (($details | Select-Object -First 10) -join ', '))
    if ($pngs.Count -lt $MinSelftestPngs) {
        return Add-Step -Id 'selftest' -Title $title -Status 'fail' -Command $run.commandLine -Detail ("only {0} PNG(s), the evidence protocol expects at least {1} (highlight, dim mask, size label, top bar, long-shot preview, editor toolbar, mosaic before/after): {2}" -f $pngs.Count, $MinSelftestPngs, $summary) -ExitCode 0 -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
    }
    if ($bad.Count -gt 0) {
        return Add-Step -Id 'selftest' -Title $title -Status 'fail' -Command $run.commandLine -Detail ("unusable PNG evidence: " + ($bad -join ', ') + '; ' + $summary) -ExitCode 0 -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
    }
    # F-11/F-18: a PNG proves the renderer ran, not that the behaviour was asserted. summary.json
    # carries one verdict per acceptance criterion, so every entry has to read "passed" before
    # this step may pass: a missing file, a missing criterion or any non-passed verdict fails here.
    # N-5: a criterion may declare itself "attested" (its property cannot be probed headlessly, e.g.
    # "C# 5 only" or "right-click exits"). "attested" counts as a pass but is never silent: the core
    # A1-A6 criteria must be strictly "passed", and the detail line names every attested criterion.
    $summaryPath = Join-Path $outDir 'summary.json'
    if (-not (Test-Path -LiteralPath $summaryPath)) {
        return Add-Step -Id 'selftest' -Title $title -Status 'fail' -Command $run.commandLine -Detail ("selftest wrote {0} PNG(s) but no summary.json, so the per-criterion verdicts cannot be checked: {1}" -f $pngs.Count, $summary) -ExitCode 0 -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
    }
    $criteria = @()
    $summaryParseError = $null
    try {
        $doc = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
        $criteria = @($doc.results)
        if ($criteria.Count -eq 0) { $criteria = @($doc.criteria) }
    } catch {
        $summaryParseError = $_.Exception.Message
    }
    if ($summaryParseError) {
        return Add-Step -Id 'selftest' -Title $title -Status 'fail' -Command $run.commandLine -Detail ("summary.json is not valid JSON: " + $summaryParseError) -ExitCode 0 -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
    }
    if ($criteria.Count -eq 0) {
        return Add-Step -Id 'selftest' -Title $title -Status 'fail' -Command $run.commandLine -Detail 'summary.json lists no criteria (expected results[] with one passed entry per acceptance item)' -ExitCode 0 -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
    }
    $notPassed = @()
    $attested = @()
    foreach ($criterion in $criteria) {
        $verdict = ([string]$criterion.status).ToLowerInvariant()
        $label = [string]$criterion.criterion
        if (-not $label) { $label = [string]$criterion.name }
        if (-not $label) { $label = '(unnamed)' }
        if ($verdict -eq 'attested') {
            $attested += $label
        } elseif ($verdict -ne 'passed') {
            if ($verdict) { $notPassed += ($label + '=' + $verdict) } else { $notPassed += ($label + '=(no status)') }
        }
    }
    if ($notPassed.Count -gt 0) {
        return Add-Step -Id 'selftest' -Title $title -Status 'fail' -Command $run.commandLine -Detail ("summary.json reports non-passed criteria: " + ($notPassed -join ', ')) -ExitCode 0 -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
    }
    $verdictIds = @($criteria | ForEach-Object { [string]$_.criterion })
    # t22 final: the suite carries 13 criteria (A1..A8, A9/R26 and the repair legs N1/N2/N2b/N3).
    # Every one must be present -- a shrunken suite must never read as "all criteria passed".
    $requiredVerdicts = @('A1', 'A2', 'A3', 'A4', 'A5', 'A6', 'A7', 'A8', 'A9/R26', 'N1', 'N2', 'N2b', 'N3')
    # Non-core verdicts may be attested; the visual/behavioural core must be asserted by a probe (N-5).
    $coreVerdicts = @('A1', 'A2', 'A3', 'A4', 'A5', 'A6')
    $missingVerdicts = @($requiredVerdicts | Where-Object { $verdictIds -notcontains $_ })
    if ($missingVerdicts.Count -gt 0) {
        return Add-Step -Id 'selftest' -Title $title -Status 'fail' -Command $run.commandLine -Detail ("summary.json has no verdict for " + ($missingVerdicts -join ', ') + '; present: ' + ($verdictIds -join ', ')) -ExitCode 0 -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
    }
    $attestedCore = @($coreVerdicts | Where-Object { $attested -contains $_ })
    if ($attestedCore.Count -gt 0) {
        return Add-Step -Id 'selftest' -Title $title -Status 'fail' -Command $run.commandLine -Detail ("core criteria must be asserted by a probe, not merely attested: " + ($attestedCore -join ', ')) -ExitCode 0 -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
    }
    $verdictText = ("{0} criteria all passed in summary.json ({1})" -f $criteria.Count, ($verdictIds -join ', '))
    if ($attested.Count -gt 0) {
        $verdictText += ("; attested without a runtime probe: " + ($attested -join ', '))
    }
    $warnings = @()
    $names = (($pngs | ForEach-Object { $_.Name.ToLowerInvariant() }) -join ' ')
    if ($names -notmatch 'long|preview|scroll') { $warnings += 'no PNG name looks like the long-shot preview (preview coverage is not machine-verifiable, check by eye)' }
    if ($names -notmatch 'mosaic|pixel') { $warnings += 'no PNG name looks like the mosaic before/after (check by eye)' }
    return Add-Step -Id 'selftest' -Title $title -Status 'pass' -Command $run.commandLine -Detail ($summary + '; ' + $verdictText) -ExitCode 0 -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Warnings $warnings -Log $log
}

# ---------------------------------------------------------------------------------
# step 4b: long-shot stitch probe (SnipTool.exe --longshot-probe)
# ---------------------------------------------------------------------------------
# F-1 was a blocker that the mock-only selftest could not catch: the long screenshot was cropped
# back to one screen. The probe drives the real scroll-capture + stitch path headlessly and writes
# longshot_probe.json, so this step can assert composedHeight > selectionHeight instead of trusting
# a picture. When the switch does not exist yet the step is skipped and says so — never "passing".
function Invoke-LongShotProbeStep {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $title = 'bin/SnipTool.exe --longshot-probe (real scroll capture + stitch, headless)'
    $exe = Join-Path $script:Root 'bin/SnipTool.exe'
    if ($SkipNative) {
        return Add-Step -Id 'longshot-probe' -Title $title -Status 'skipped' -Detail 'skipped by -SkipNative'
    }
    if (-not (Test-BuildReady $exe)) {
        $build = $script:Steps | Where-Object { $_.id -eq 'build' } | Select-Object -First 1
        $why = if ($build -and $build.status -eq 'fail') { 'build failed, so the long-shot probe could not run' } else { 'bin/SnipTool.exe is missing (run without -SkipBuild)' }
        return Add-Step -Id 'longshot-probe' -Title $title -Status 'skipped' -Detail $why
    }
    $probe = Test-NativeSwitchImplemented '--longshot-probe'
    if (-not $probe.implemented) {
        return Add-Step -Id 'longshot-probe' -Title $title -Status 'skipped' -Detail 'src/ has no non-comment "--longshot-probe" switch yet, so the stitched long screenshot cannot be verified headlessly; it is explicitly NOT claimed as passing (see F-1)'
    }
    $outDir = Join-Path $script:OutRoot 'longshot'
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    Get-ChildItem -Path $outDir -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    $run = Invoke-Process -FilePath $exe -ArgumentList @('--longshot-probe', $outDir) -WorkingDirectory $script:Root -TimeoutSec $LongShotTimeoutSec
    $log = Write-CommandLog -Id 'longshot-probe' -Run $run -Title 'SnipTool --longshot-probe'
    $artifacts = @((Get-RelPath $outDir))
    $jsonPath = Join-Path $outDir 'longshot_probe.json'
    if ($run.timedOut) {
        return Add-Step -Id 'longshot-probe' -Title $title -Status 'fail' -Command $run.commandLine -Detail ("probe did not exit within {0}s and was killed" -f $LongShotTimeoutSec) -ExitCode $run.exitCode -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
    }
    if ($run.exitCode -ne 0) {
        return Add-Step -Id 'longshot-probe' -Title $title -Status 'fail' -Command $run.commandLine -Detail ("exit {0}: {1}" -f $run.exitCode, (Get-Tail ($run.stdout + $script:NL + $run.stderr) 6)) -ExitCode $run.exitCode -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
    }
    if (-not (Test-Path -LiteralPath $jsonPath)) {
        return Add-Step -Id 'longshot-probe' -Title $title -Status 'fail' -Command $run.commandLine -Detail ('exit 0 but no longshot_probe.json was written to ' + (Get-RelPath $outDir)) -ExitCode 0 -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
    }
    $doc = $null
    try { $doc = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json } catch { $doc = $null }
    if ($null -eq $doc) {
        return Add-Step -Id 'longshot-probe' -Title $title -Status 'fail' -Command $run.commandLine -Detail 'longshot_probe.json is not valid JSON' -ExitCode 0 -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
    }
    $problems = @()
    if ($doc.ok -ne $true) { $problems += ('ok=' + [string]$doc.ok) }
    # captain (t20 addendum) + t15 N-2: reviewer proved the probe could pass entirely through the
    # helperForm.ScrollBy(60) fallback, so a PASS says nothing about the real wheel-forwarding path.
    # The probe must now state fallbackUsed, and a true value is a hard FAIL, not a warning.
    $fallbackSeen = $null
    $fallbackName = ''
    foreach ($name in @('fallbackUsed', 'usedScrollFallback', 'scrollFallbackUsed')) {
        if ($null -ne $doc.$name) { $fallbackSeen = $doc.$name; $fallbackName = $name; break }
    }
    $fallbackText = 'missing'
    if ($null -eq $fallbackSeen) {
        $problems += 'longshot_probe.json has no fallbackUsed field (contract change since t22: the probe must declare whether it reached the scroll offset through the wheel-forwarding path or through the ScrollBy fallback)'
    } else {
        $fallbackText = [string]$fallbackSeen
        if (($fallbackSeen -eq $true) -or ([string]$fallbackSeen -match '^(?i:true|1|yes)$')) {
            $problems += ('the probe used the scroll fallback instead of wheel forwarding (' + $fallbackName + '=' + [string]$fallbackSeen + '), which does not prove the wheel path')
        }
    }
    $frames = $null
    foreach ($name in @('frames', 'frameCount')) { if ($null -ne $doc.$name) { $frames = [int]$doc.$name; break } }
    if ($null -eq $frames) { $problems += 'no frames/frameCount field' }
    elseif ($frames -lt 2) { $problems += ('frames=' + $frames + ' (a long screenshot needs at least 2 captured frames)') }
    $composed = $null
    $selected = $null
    foreach ($name in @('composedHeight', 'stitchedHeight', 'height')) { if ($null -ne $doc.$name) { $composed = [int]$doc.$name; break } }
    foreach ($name in @('selHeight', 'selectionHeight', 'viewportHeight')) { if ($null -ne $doc.$name) { $selected = [int]$doc.$name; break } }
    if (($null -eq $composed) -or ($null -eq $selected)) {
        $problems += 'no composed/selection height fields (probe schema not recognised)'
    } elseif ($composed -le $selected) {
        $problems += ('composed height {0} is not taller than the selection height {1} — the stitched image was cropped back to one screen (F-1)' -f $composed, $selected)
    }
    # t22 final probe schema. These four fields are what separates "a real long-shot capture" from
    # "a picture of one window": they must exist and hold the expected value, otherwise the contract
    # changed and the step has to fail (never skip, never warn).
    $realPathText = if ($null -ne $doc.realPath) { [string]$doc.realPath } else { 'missing' }
    $n1Text = if ($null -ne $doc.n1RegressionOk) { [string]$doc.n1RegressionOk } else { 'missing' }
    $hookText = if ($null -ne $doc.hookUnhooked) { [string]$doc.hookUnhooked } else { 'missing' }
    foreach ($flag in @(
            @{ Name = 'realPath'; Why = 'the probe did not drive the real SnipForm capture path' },
            @{ Name = 'n1RegressionOk'; Why = 'the N-1 regression leg (the stitched image must survive an editor drag) failed' },
            @{ Name = 'hookUnhooked'; Why = 'the keyboard hook was not uninstalled after the long-shot ended (N-3)' })) {
        $fieldName = [string]$flag.Name
        if ($null -eq $doc.$fieldName) {
            $problems += ('longshot_probe.json has no ' + $fieldName + ' field (contract change since t22)')
        } elseif ($doc.$fieldName -ne $true) {
            $problems += ($fieldName + '=' + [string]$doc.$fieldName + ' (' + [string]$flag.Why + ')')
        }
    }
    $exported = $null
    foreach ($name in @('exportedHeight', 'outputHeight', 'pngHeight')) { if ($null -ne $doc.$name) { $exported = [int]$doc.$name; break } }
    $exportedText = if ($null -ne $exported) { [string]$exported } else { 'missing' }
    if ($null -eq $exported) {
        $problems += 'longshot_probe.json has no exportedHeight field (contract change since t22)'
    } elseif (($null -ne $composed) -and ($exported -lt $composed)) {
        $problems += ('exportedHeight={0} is shorter than composedHeight={1}, so the exported PNG lost rows that were actually captured (N-1)' -f $exported, $composed)
    }
    $detail = ("ok={0}, frames={1}, composedHeight={2}, selectionHeight={3}, fallbackUsed={4}, realPath={5}, n1RegressionOk={6}, exportedHeight={7}, hookUnhooked={8}" -f [string]$doc.ok, [string]$frames, [string]$composed, [string]$selected, $fallbackText, $realPathText, $n1Text, $exportedText, $hookText)
    if ($problems.Count -gt 0) {
        return Add-Step -Id 'longshot-probe' -Title $title -Status 'fail' -Command $run.commandLine -Detail (($problems -join ' | ') + '; ' + $detail) -ExitCode 0 -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
    }
    return Add-Step -Id 'longshot-probe' -Title $title -Status 'pass' -Command $run.commandLine -Detail $detail -ExitCode 0 -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
}

# ---------------------------------------------------------------------------------
# step 4c: long-shot probe negative control (wheel forwarding disabled -> must FAIL)
# ---------------------------------------------------------------------------------
# t15 N-2: the reviewer proved the probe could reach a stitched PNG purely through the ScrollBy
# fallback, so a green probe proved nothing about wheel forwarding. The verifier added
# "--longshot-probe <dir> wheelOnly=false", which disables wheel forwarding; it must exit non-zero
# and write ok=false. A green negative control would mean the probe cannot tell the two paths apart.
function Invoke-LongShotNegativeStep {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $title = 'bin/SnipTool.exe --longshot-probe wheelOnly=false (negative control must fail)'
    $exe = Join-Path $script:Root 'bin/SnipTool.exe'
    if ($SkipNative) {
        return Add-Step -Id 'longshot-negative' -Title $title -Status 'skipped' -Detail 'skipped by -SkipNative'
    }
    if (-not (Test-BuildReady $exe)) {
        $build = $script:Steps | Where-Object { $_.id -eq 'build' } | Select-Object -First 1
        $why = if ($build -and $build.status -eq 'fail') { 'build failed, so the negative control could not run' } else { 'bin/SnipTool.exe is missing (run without -SkipBuild)' }
        return Add-Step -Id 'longshot-negative' -Title $title -Status 'skipped' -Detail $why
    }
    $probe = Test-NativeSwitchImplemented '--longshot-probe'
    if (-not $probe.implemented) {
        return Add-Step -Id 'longshot-negative' -Title $title -Status 'skipped' -Detail 'src/ has no non-comment "--longshot-probe" switch yet, so the negative control cannot run; the probe is explicitly NOT claimed as passing (see N-2)'
    }
    $outDir = Join-Path $script:OutRoot 'longshot-negative'
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    Get-ChildItem -Path $outDir -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    $run = Invoke-Process -FilePath $exe -ArgumentList @('--longshot-probe', $outDir, 'wheelOnly=false') -WorkingDirectory $script:Root -TimeoutSec $LongShotTimeoutSec
    $log = Write-CommandLog -Id 'longshot-negative' -Run $run -Title 'SnipTool --longshot-probe wheelOnly=false (negative control)'
    $artifacts = @((Get-RelPath $outDir))
    if ($run.timedOut) {
        return Add-Step -Id 'longshot-negative' -Title $title -Status 'fail' -Command $run.commandLine -Detail ("the negative control did not exit within {0}s and was killed" -f $LongShotTimeoutSec) -ExitCode $run.exitCode -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
    }
    $jsonPath = Join-Path $outDir 'longshot_probe.json'
    $negText = 'no longshot_probe.json was written'
    $negOk = $null
    if (Test-Path -LiteralPath $jsonPath) {
        $neg = $null
        try { $neg = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json } catch { $neg = $null }
        if ($null -ne $neg) {
            $negOk = $neg.ok
            $negFrames = if ($null -ne $neg.frames) { [string]$neg.frames } else { 'missing' }
            $negText = ('ok={0}, frames={1}' -f [string]$neg.ok, $negFrames)
        } else {
            $negText = 'longshot_probe.json is not valid JSON'
        }
    }
    if ($run.exitCode -eq 0) {
        return Add-Step -Id 'longshot-negative' -Title $title -Status 'fail' -Command $run.commandLine -Detail ('the negative control exited 0, so the probe cannot tell a real long-shot capture from a blocked wheel path (N-2); ' + $negText) -ExitCode $run.exitCode -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
    }
    if ($negOk -eq $true) {
        return Add-Step -Id 'longshot-negative' -Title $title -Status 'fail' -Command $run.commandLine -Detail ('the negative control exited {0} but still wrote ok=true, which contradicts itself; {1}' -f $run.exitCode, $negText) -ExitCode $run.exitCode -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
    }
    $warnings = @()
    if ($run.exitCode -ne 1) { $warnings += ('the negative control exited ' + $run.exitCode + ' instead of 1; only "non-zero exit" is asserted') }
    return Add-Step -Id 'longshot-negative' -Title $title -Status 'pass' -Command $run.commandLine -Detail ('expected non-zero exit received, ' + $negText) -ExitCode $run.exitCode -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Warnings $warnings -Log $log
}

# ---------------------------------------------------------------------------------
# step 5: crash probe (SnipTool.exe --crash-probe)
# ---------------------------------------------------------------------------------
function Invoke-CrashProbeStep {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $title = 'bin/SnipTool.exe --crash-probe (crash log is append-only)'
    $exe = Join-Path $script:Root 'bin/SnipTool.exe'
    if ($SkipNative) {
        return Add-Step -Id 'crash-probe' -Title $title -Status 'skipped' -Detail 'skipped by -SkipNative'
    }
    if (-not (Test-BuildReady $exe)) {
        $build = $script:Steps | Where-Object { $_.id -eq 'build' } | Select-Object -First 1
        $why = if ($build -and $build.status -eq 'fail') { 'build failed, so the crash probe could not run' } else { 'bin/SnipTool.exe is missing (run without -SkipBuild)' }
        return Add-Step -Id 'crash-probe' -Title $title -Status 'skipped' -Detail $why
    }
    $probe = Test-NativeSwitchImplemented '--crash-probe'
    if (-not $probe.implemented) {
        return Add-Step -Id 'crash-probe' -Title $title -Status 'pending' -Detail 'no non-comment [--crash-probe] switch in src/*.cs yet; native tool not launched'
    }
    $outDir = Join-Path $script:OutRoot 'crashprobe'
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $jsonPath = Join-Path $outDir 'crash_probe.json'
    Remove-Item -LiteralPath $jsonPath -Force -ErrorAction SilentlyContinue
    $run = Invoke-Process -FilePath $exe -ArgumentList @('--crash-probe', $outDir) -WorkingDirectory $script:Root -TimeoutSec $CrashProbeTimeoutSec
    $log = Write-CommandLog -Id 'crash-probe' -Run $run -Title 'SnipTool --crash-probe'
    $artifacts = @()
    if (Test-Path -LiteralPath $outDir) { $artifacts += (Get-RelPath $outDir) }
    if ($run.timedOut) {
        return Add-Step -Id 'crash-probe' -Title $title -Status 'fail' -Command $run.commandLine -Detail ("crash probe did not exit within {0}s and was killed" -f $CrashProbeTimeoutSec) -ExitCode $run.exitCode -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
    }
    if ($run.exitCode -ne 0) {
        return Add-Step -Id 'crash-probe' -Title $title -Status 'fail' -Command $run.commandLine -Detail ("exit {0}: {1}" -f $run.exitCode, (Get-Tail ($run.stdout + $script:NL + $run.stderr) 6)) -ExitCode $run.exitCode -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
    }
    if (-not (Test-Path -LiteralPath $jsonPath)) {
        return Add-Step -Id 'crash-probe' -Title $title -Status 'fail' -Command $run.commandLine -Detail 'exit 0 but no crash_probe.json was written' -ExitCode 0 -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
    }
    $json = $null
    try { $json = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json } catch { $json = $null }
    if ($null -eq $json) {
        return Add-Step -Id 'crash-probe' -Title $title -Status 'fail' -Command $run.commandLine -Detail 'crash_probe.json is not valid JSON' -ExitCode 0 -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
    }
    $problems = @()
    if ($json.ok -ne $true) { $problems += ('crash_probe.json ok is not true (got: ' + [string]$json.ok + ')') }
    if (-not ([long]$json.afterBytes -gt [long]$json.beforeBytes)) { $problems += ("afterBytes ({0}) is not greater than beforeBytes ({1})" -f $json.afterBytes, $json.beforeBytes) }
    if ($json.logPath -and ([string]$json.logPath) -notmatch 'dsh-snip-error\.log$') { $problems += ('unexpected logPath: ' + [string]$json.logPath) }
    $detail = ("ok={0}; %TEMP%\dsh-snip-error.log {1} -> {2} bytes; the probe calls LogCrash directly, so no real crash and no WER dialog" -f $json.ok, $json.beforeBytes, $json.afterBytes)
    if ($problems.Count -gt 0) {
        return Add-Step -Id 'crash-probe' -Title $title -Status 'fail' -Command $run.commandLine -Detail (($problems -join ' | ') + '; ' + $detail) -ExitCode 0 -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
    }
    return Add-Step -Id 'crash-probe' -Title $title -Status 'pass' -Command $run.commandLine -Detail $detail -ExitCode 0 -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
}

# ---------------------------------------------------------------------------------
# step 6: plugin smoke (tools/plugin-smoke.mjs)
# ---------------------------------------------------------------------------------
function Invoke-PluginStep {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $title = 'plugin smoke: stub-load lib/index.js + lib/client.js'
    $smoke = Join-Path $script:ToolsDir 'plugin-smoke.mjs'
    if (-not (Test-Path -LiteralPath $smoke)) {
        return Add-Step -Id 'plugin' -Title $title -Status 'fail' -Detail ("missing harness file: " + (Get-RelPath $smoke))
    }
    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $nodeCmd) {
        return Add-Step -Id 'plugin' -Title $title -Status 'fail' -Detail 'node is not on PATH'
    }
    $jsonPath = Join-Path $script:OutRoot 'plugin-smoke.json'
    New-Item -ItemType Directory -Force -Path $script:OutRoot | Out-Null
    $run = Invoke-Process -FilePath $nodeCmd.Source -ArgumentList @($smoke, '--root', $script:Root, '--json', $jsonPath) -WorkingDirectory $script:Root -TimeoutSec $PluginTimeoutSec
    $log = Write-CommandLog -Id 'plugin' -Run $run -Title 'plugin-smoke.mjs'
    $artifacts = @()
    if (Test-Path -LiteralPath $jsonPath) { $artifacts += (Get-RelPath $jsonPath) }

    if ($run.timedOut) {
        return Add-Step -Id 'plugin' -Title $title -Status 'fail' -Command $run.commandLine -Detail ("timed out after {0}s" -f $PluginTimeoutSec) -ExitCode $run.exitCode -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
    }
    $json = $null
    if (Test-Path -LiteralPath $jsonPath) {
        try { $json = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json } catch { $json = $null }
    }
    if ($null -eq $json) {
        return Add-Step -Id 'plugin' -Title $title -Status 'fail' -Command $run.commandLine -Detail ("plugin-smoke wrote no JSON (exit {0}): {1}" -f $run.exitCode, (Get-Tail ($run.stdout + $script:NL + $run.stderr) 6)) -ExitCode $run.exitCode -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Log $log
    }
    $checks = @($json.checks)
    $failed = @($checks | Where-Object { $_.status -eq 'fail' })
    $pendingChecks = @($checks | Where-Object { $_.status -eq 'pending' })
    $warnChecks = @($checks | Where-Object { $_.status -eq 'warn' })
    $passChecks = @($checks | Where-Object { $_.status -eq 'pass' })
    $status = [string]$json.status
    $detail = ("{0} pass / {1} warn / {2} pending / {3} fail" -f $passChecks.Count, $warnChecks.Count, $pendingChecks.Count, $failed.Count)
    $warnings = @($warnChecks | ForEach-Object { "$($_.id): $($_.detail)" })
    if ($status -eq 'fail' -or $run.exitCode -ne 0 -or $failed.Count -gt 0) {
        $failing = @($failed | ForEach-Object { "$($_.id): $($_.detail)" }) -join ' | '
        return Add-Step -Id 'plugin' -Title $title -Status 'fail' -Command $run.commandLine -Detail ("{0}; failing: {1}" -f $detail, $failing) -ExitCode $run.exitCode -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Warnings $warnings -Log $log
    }
    if ($status -eq 'pending' -or $pendingChecks.Count -gt 0) {
        $waiting = @($pendingChecks | ForEach-Object { $_.id }) -join ', '
        return Add-Step -Id 'plugin' -Title $title -Status 'pending' -Command $run.commandLine -Detail ($detail + '; waiting on: ' + $waiting) -ExitCode $run.exitCode -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Warnings $warnings -Log $log
    }
    return Add-Step -Id 'plugin' -Title $title -Status 'pass' -Command $run.commandLine -Detail $detail -ExitCode $run.exitCode -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts -Warnings $warnings -Log $log
}

# ---------------------------------------------------------------------------------
# step 7: installer plan (install.ps1 -WhatIf)
# ---------------------------------------------------------------------------------
function Invoke-InstallPlanStep {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $title = 'install.ps1 -WhatIf (plan only, touches nothing)'
    $installer = Join-Path $script:Root 'install.ps1'
    if (-not (Test-Path -LiteralPath $installer)) {
        return Add-Step -Id 'install-plan' -Title $title -Status 'fail' -Detail 'missing install.ps1'
    }
    $run = Invoke-Process -FilePath $script:PwshExe -ArgumentList @('-NoProfile', '-File', $installer, '-WhatIf') -WorkingDirectory $script:Root -TimeoutSec $InstallTimeoutSec
    $log = Write-CommandLog -Id 'install-plan' -Run $run -Title 'install.ps1 -WhatIf'
    if ($run.timedOut) {
        return Add-Step -Id 'install-plan' -Title $title -Status 'fail' -Command $run.commandLine -Detail ("timed out after {0}s" -f $InstallTimeoutSec) -ExitCode $run.exitCode -DurationMs ([int]$sw.ElapsedMilliseconds) -Log $log
    }
    $output = [string]$run.stdout + $script:NL + [string]$run.stderr
    if ($run.exitCode -ne 0) {
        return Add-Step -Id 'install-plan' -Title $title -Status 'fail' -Command $run.commandLine -Detail ("exit {0}: {1}" -f $run.exitCode, (Get-Tail $output 6)) -ExitCode $run.exitCode -DurationMs ([int]$sw.ElapsedMilliseconds) -Log $log
    }
    $expected = @('备份', 'pnpm add', 'dsh.profile.bundles', '需重启 DSH 生效')
    $missingMarkers = @()
    foreach ($marker in $expected) {
        if ($output -notmatch [regex]::Escape($marker)) { $missingMarkers += $marker }
    }
    if ($missingMarkers.Count -gt 0) {
        return Add-Step -Id 'install-plan' -Title $title -Status 'fail' -Command $run.commandLine -Detail ("plan is missing required marker(s): " + ($missingMarkers -join ', ')) -ExitCode 0 -DurationMs ([int]$sw.ElapsedMilliseconds) -Log $log
    }
    if ($output -match '(?i)\b(Stop-Process|Restart-Computer|taskkill)\b') {
        return Add-Step -Id 'install-plan' -Title $title -Status 'fail' -Command $run.commandLine -Detail 'plan output mentions stopping/restarting processes — the installer must never do that' -ExitCode 0 -DurationMs ([int]$sw.ElapsedMilliseconds) -Log $log
    }
    return Add-Step -Id 'install-plan' -Title $title -Status 'pass' -Command $run.commandLine -Detail 'plan covers backup -> pnpm add -> dsh.profile.bundles -> restart reminder; nothing was mutated' -ExitCode 0 -DurationMs ([int]$sw.ElapsedMilliseconds) -Log $log
}

# ---------------------------------------------------------------------------------
# step 8: package (npm pack -> dsh-screenshot-<version>.tgz + files whitelist check)
# ---------------------------------------------------------------------------------
function Invoke-PackageStep {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $title = 'npm pack -> dsh-screenshot-<version>.tgz (files whitelist enforced)'
    if (Test-MissingRel 'bin/SnipTool.exe') {
        return Add-Step -Id 'package' -Title $title -Status 'skipped' -Detail 'bin/SnipTool.exe is missing (the build step must pass first)'
    }
    $pkgPath = Join-Path $script:Root 'package.json'
    if (-not (Test-Path -LiteralPath $pkgPath)) {
        return Add-Step -Id 'package' -Title $title -Status 'fail' -Detail 'missing package.json'
    }
    try {
        $pkg = Get-Content -LiteralPath $pkgPath -Raw | ConvertFrom-Json
    } catch {
        return Add-Step -Id 'package' -Title $title -Status 'fail' -Detail ('package.json is not valid JSON: ' + $_.Exception.Message)
    }
    $version = [string]$pkg.version
    $tarballName = ('{0}-{1}.tgz' -f [string]$pkg.name, $version)
    $tarballPath = Join-Path $script:Root $tarballName

    $npmCmd = Get-Command npm -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $npmCmd) {
        return Add-Step -Id 'package' -Title $title -Status 'fail' -Detail 'npm is not on PATH'
    }

    # npm is a .cmd shim on Windows and Invoke-Process never uses a shell, so the pack runs
    # through cmd.exe. --json keeps the packed file list machine readable; --loglevel=error
    # keeps notice lines out of stdout.
    $comspec = if ($env:ComSpec) { $env:ComSpec } else { 'cmd.exe' }
    $run = Invoke-Process -FilePath $comspec -ArgumentList @('/c', 'npm', 'pack', '--json', '--loglevel=error') -WorkingDirectory $script:Root -TimeoutSec $PackageTimeoutSec
    $log = Write-CommandLog -Id 'package' -Run $run -Title 'npm pack --json'
    if ($run.timedOut) {
        return Add-Step -Id 'package' -Title $title -Status 'fail' -Command $run.commandLine -Detail ("npm pack timed out after {0}s" -f $PackageTimeoutSec) -ExitCode $run.exitCode -DurationMs ([int]$sw.ElapsedMilliseconds) -Log $log
    }
    if ($run.startError) {
        return Add-Step -Id 'package' -Title $title -Status 'fail' -Command $run.commandLine -Detail ('could not start npm: ' + [string]$run.startError) -ExitCode $run.exitCode -DurationMs ([int]$sw.ElapsedMilliseconds) -Log $log
    }
    if ($run.exitCode -ne 0) {
        return Add-Step -Id 'package' -Title $title -Status 'fail' -Command $run.commandLine -Detail ("npm pack exit {0}: {1}" -f $run.exitCode, (Get-Tail ([string]$run.stdout + $script:NL + [string]$run.stderr) 6)) -ExitCode $run.exitCode -DurationMs ([int]$sw.ElapsedMilliseconds) -Log $log
    }

    # npm may still print a banner around the JSON array: cut to the outermost brackets.
    $stdout = [string]$run.stdout
    $from = $stdout.IndexOf('[')
    $to = $stdout.LastIndexOf(']')
    if ($from -lt 0 -or $to -le $from) {
        return Add-Step -Id 'package' -Title $title -Status 'fail' -Command $run.commandLine -Detail ('npm pack printed no JSON: ' + (Get-Tail $stdout 4)) -ExitCode 0 -DurationMs ([int]$sw.ElapsedMilliseconds) -Log $log
    }
    try {
        $packed = @(($stdout.Substring($from, $to - $from + 1) | ConvertFrom-Json))
    } catch {
        return Add-Step -Id 'package' -Title $title -Status 'fail' -Command $run.commandLine -Detail ('npm pack JSON is not parseable: ' + $_.Exception.Message) -ExitCode 0 -DurationMs ([int]$sw.ElapsedMilliseconds) -Log $log
    }
    if ($packed.Count -eq 0) {
        return Add-Step -Id 'package' -Title $title -Status 'fail' -Command $run.commandLine -Detail 'npm pack reported no package' -ExitCode 0 -DurationMs ([int]$sw.ElapsedMilliseconds) -Log $log
    }
    $info = $packed[0]
    if ([string]$info.filename) { $tarballName = [string]$info.filename }
    if (-not (Test-Path -LiteralPath $tarballPath)) {
        # npm names the file after the manifest; trust the manifest, but accept the reported name.
        $alt = Join-Path $script:Root $tarballName
        if (Test-Path -LiteralPath $alt) { $tarballPath = $alt } else {
            return Add-Step -Id 'package' -Title $title -Status 'fail' -Command $run.commandLine -Detail ('npm pack did not produce ' + $tarballName) -ExitCode 0 -DurationMs ([int]$sw.ElapsedMilliseconds) -Log $log
        }
    }

    $files = @($info.files | ForEach-Object { ([string]$_.path).Replace('\', '/').ToLowerInvariant() })
    if ($files.Count -eq 0) {
        return Add-Step -Id 'package' -Title $title -Status 'fail' -Command $run.commandLine -Detail 'npm pack reported an empty file list' -ExitCode 0 -DurationMs ([int]$sw.ElapsedMilliseconds) -Log $log
    }

    # Everything the installed plugin needs, and nothing a profile must not receive.
    $required = @('lib/index.js', 'lib/client.js', 'bin/sniptool.exe', 'package.json', 'cordis.patch.yml')
    $problems = @()
    foreach ($need in $required) {
        if ($files -notcontains $need) { $problems += ('tarball is missing ' + $need) }
    }
    $forbidden = @('tools/', 'test/', 'out/', '.agent-teams/', 'install.ps1', 'build.ps1')
    foreach ($bad in $forbidden) {
        $hit = @($files | Where-Object { $_.StartsWith($bad) -or $_.EndsWith('/' + $bad.TrimEnd('/')) -or $_ -eq $bad })
        if ($hit.Count -gt 0) { $problems += ('tarball ships ' + $bad + ' (' + ($hit -join ', ') + ')') }
    }

    # files[] whitelist: every packed path must be covered by it (package.json, README* and
    # the main entry are always included by npm itself).
    $alwaysIncluded = @('package.json', 'readme.md', 'readme', 'license', 'licence', 'changelog')
    $whitelist = @($pkg.files | ForEach-Object { ([string]$_).Replace('\', '/').ToLowerInvariant() })
    $uncovered = @()
    foreach ($path in $files) {
        $leaf = ($path -split '/')[-1]
        if ($alwaysIncluded -contains $leaf -or $alwaysIncluded -contains $path) { continue }
        $covered = $false
        foreach ($entry in $whitelist) {
            if ($entry.EndsWith('/')) {
                if ($path.StartsWith($entry)) { $covered = $true; break }
            } elseif ($path -eq $entry) { $covered = $true; break }
        }
        if (-not $covered) { $uncovered += $path }
    }
    if ($uncovered.Count -gt 0) {
        $problems += ('packed files outside the package.json "files" whitelist: ' + ($uncovered -join ', '))
    }

    $sizeKb = [int]([math]::Round((Get-Item -LiteralPath $tarballPath).Length / 1024, 1))
    $detail = ('{0} ({1} KiB, {2} files); covers lib/, bin/SnipTool.exe, package.json, cordis.patch.yml; nothing outside the files whitelist' -f $tarballName, $sizeKb, $files.Count)
    if ($problems.Count -gt 0) {
        return Add-Step -Id 'package' -Title $title -Status 'fail' -Command $run.commandLine -Detail ($problems -join ' | ') -ExitCode 0 -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts @((Get-RelPath $tarballPath)) -Log $log
    }
    return Add-Step -Id 'package' -Title $title -Status 'pass' -Command $run.commandLine -Detail $detail -ExitCode 0 -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts @((Get-RelPath $tarballPath)) -Log $log
}

# ---------------------------------------------------------------------------------
# step 9: docs coverage (VERIFY R1..R30, RELEASE sections)
# ---------------------------------------------------------------------------------
function Invoke-DocsStep {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $title = 'docs: VERIFY.md covers R1..R30, RELEASE.md covers release sections'
    $verifyPath = Join-Path $script:Root 'docs/VERIFY.md'
    $releasePath = Join-Path $script:Root 'docs/RELEASE.md'
    $problems = @()
    $detailParts = @()
    $artifacts = @()
    if (-not (Test-Path -LiteralPath $verifyPath)) {
        $problems += 'docs/VERIFY.md is missing'
    } else {
        $artifacts += 'docs/VERIFY.md'
        $text = Get-Content -LiteralPath $verifyPath -Raw
        $sectionRe = [regex]'(?ms)^(#{2,4})[ \t]*R(\d{1,2})\b(.*?)(?=^#{2,4}[ \t]|\z)'
        $found = @{}
        $weak = @()
        foreach ($m in $sectionRe.Matches($text)) {
            $rid = [int]$m.Groups[2].Value
            $found[$rid] = $true
            $body = $m.Groups[3].Value
            $lacks = @(@('操作', '预期', '证据') | Where-Object { $body -notmatch [regex]::Escape($_) })
            if ($lacks.Count -gt 0) { $weak += ("R{0} lacks {1}" -f $rid, ($lacks -join '/')) }
        }
        $missing = @(1..30 | Where-Object { -not $found.ContainsKey($_) })
        if ($missing.Count -gt 0) { $problems += ('VERIFY.md has no section for: ' + (($missing | ForEach-Object { "R$_" }) -join ', ')) }
        if ($weak.Count -gt 0) { $problems += ('VERIFY.md sections incomplete (need 操作/预期/证据): ' + ($weak -join '; ')) }
        $detailParts += ("VERIFY sections: {0}/30" -f $found.Count)
    }
    if (-not (Test-Path -LiteralPath $releasePath)) {
        $problems += 'docs/RELEASE.md is missing'
    } else {
        $artifacts += 'docs/RELEASE.md'
        $text = Get-Content -LiteralPath $releasePath -Raw
        $headingRe = [regex]'(?m)^#{1,4}[ \t]+(.+)$'
        $headings = @($headingRe.Matches($text) | ForEach-Object { $_.Groups[1].Value })
        $required = @('版本', '构建', '打包', '安装', '回滚', '已知限制')
        $missingSections = @($required | Where-Object { $kw = $_; -not ($headings | Where-Object { $_ -like "*$kw*" }) })
        if ($missingSections.Count -gt 0) { $problems += ('RELEASE.md has no section for: ' + ($missingSections -join ', ')) }
        $hit = @($required | Where-Object { $kw = $_; ($headings | Where-Object { $_ -like "*$kw*" }) }).Count
        $detailParts += ("RELEASE sections: {0}/6" -f $hit)
    }
    $detail = $detailParts -join '; '
    if ($problems.Count -gt 0) {
        return Add-Step -Id 'docs' -Title $title -Status 'fail' -Detail (($problems -join ' | ') + $(if ($detail) { "; $detail" } else { '' })) -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts
    }
    return Add-Step -Id 'docs' -Title $title -Status 'pass' -Detail ($detail + '; every R section carries 操作/预期/证据') -DurationMs ([int]$sw.ElapsedMilliseconds) -Artifacts $artifacts
}

# ---------------------------------------------------------------------------------
# report + summary
# ---------------------------------------------------------------------------------
function Get-OverallState {
    $failCount = @($script:Steps | Where-Object { $_.status -eq 'fail' }).Count
    $pendingCount = @($script:Steps | Where-Object { $_.status -eq 'pending' }).Count
    if ($failCount -gt 0) { return [pscustomobject]@{ status = 'fail'; exitCode = 1; reason = "$failCount step(s) failed" } }
    if ($pendingCount -gt 0) {
        if ($Strict) { return [pscustomobject]@{ status = 'fail'; exitCode = 1; reason = "-Strict: $pendingCount step(s) pending" } }
        return [pscustomobject]@{ status = 'pending'; exitCode = 0; reason = "$pendingCount step(s) waiting on other modules" }
    }
    return [pscustomobject]@{ status = 'pass'; exitCode = 0; reason = 'all steps passed' }
}

function Write-Evidence {
    param([string]$Mode)
    $overall = Get-OverallState
    New-Item -ItemType Directory -Force -Path $script:OutRoot | Out-Null
    $counts = [ordered]@{}
    foreach ($st in @('pass', 'pending', 'fail', 'skipped', 'planned')) {
        $counts[$st] = @($script:Steps | Where-Object { $_.status -eq $st }).Count
    }
    $report = [ordered]@{
        schema      = 'dsh-screenshot-evidence/v2'
        mode        = $Mode
        generatedAt = (Get-Date).ToString('o')
        durationMs  = [int]((Get-Date) - $script:StartedAt).TotalMilliseconds
        root        = $script:Root
        strict      = [bool]$Strict
        status      = $overall.status
        ok          = ($overall.status -ne 'fail')
        exitCode    = $overall.exitCode
        reason      = $overall.reason
        counts      = $counts
        host        = $script:Facts
        steps       = @($script:Steps)
        artifacts   = [ordered]@{
            summary = Get-RelPath (Join-Path $script:OutRoot 'SUMMARY.md')
            report  = Get-RelPath (Join-Path $script:OutRoot 'report.json')
            logs    = Get-RelPath (Join-Path $script:OutRoot 'logs')
        }
    }
    $jsonPath = Join-Path $script:OutRoot 'report.json'
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding utf8NoBOM

    $bt = $script:BT
    $lines = @()
    $lines += '# DSH 截图插件 v2 — 证据汇总'
    $lines += ''
    $lines += ('> 由 {0}tools/e2e.ps1{0} 自动生成于 {1}（模式：{2}）' -f $bt, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'), $Mode)
    $lines += ''
    $lines += '| 项 | 值 |'
    $lines += '| --- | --- |'
    $lines += ('| 总体状态 | **{0}** |' -f $overall.status.ToUpperInvariant())
    $lines += ('| 退出码 | {0} |' -f $overall.exitCode)
    $lines += ('| 说明 | {0} |' -f $overall.reason)
    $lines += ('| 仓库 | {0}{1}{0} |' -f $bt, $script:Root)
    $lines += ('| 严格模式 | {0} |' -f ([bool]$Strict))
    $lines += ''
    $lines += '## 步骤'
    $lines += ''
    $lines += '| # | 步骤 | 状态 | 退出码 | 耗时 | 证据 |'
    $lines += '| --- | --- | --- | --- | --- | --- |'
    $i = 0
    foreach ($s in $script:Steps) {
        $i += 1
        $arts = ''
        if (@($s.artifacts).Count -gt 0) { $arts = (@($s.artifacts) | ForEach-Object { $bt + $_ + $bt }) -join '<br>' }
        if ($s.log) { $arts = $arts + $(if ($arts) { '<br>' } else { '' }) + $bt + $s.log + $bt }
        $exitText = if ($null -ne $s.exitCode) { $s.exitCode } else { '' }
        $lines += ('| {0} | {1} | {2} | {3} | {4:0.0}s | {5} |' -f $i, $s.title, (Write-StatusLabel $s.status), $exitText, ($s.durationMs / 1000), $arts)
    }
    $lines += ''
    $lines += '## 明细'
    $lines += ''
    foreach ($s in $script:Steps) {
        $lines += ('### {0} — {1}' -f $s.id, (Write-StatusLabel $s.status))
        $lines += ''
        $lines += ('- 说明：{0}' -f $(if ($s.detail) { $s.detail } else { '—' }))
        if ($s.command) { $lines += ('- 命令：{0}{1}{0}' -f $bt, $s.command) }
        if ($null -ne $s.exitCode) { $lines += ('- 退出码：{0}' -f $s.exitCode) }
        if (@($s.artifacts).Count -gt 0) { $lines += ('- 产物：' + ((@($s.artifacts) | ForEach-Object { $bt + $_ + $bt }) -join '、')) }
        foreach ($w in @($s.warnings)) { $lines += ('- 警告：{0}' -f $w) }
        if ($s.status -eq 'pending') { $lines += ('- 处理：该步骤的模块尚未实现；实现后重跑 {0}pwsh -NoProfile -File tools/e2e.ps1{0}。' -f $bt) }
        if ($s.status -eq 'fail') { $lines += ('- 处理：查看 {0}{1}{0} 的 stderr 定位原因后重跑。' -f $bt, $(if ($s.log) { $s.log } else { 'out/evidence/logs/' })) }
        $lines += ''
    }
    $lines += '## 复现'
    $lines += ''
    $lines += $bt + $bt + $bt + 'powershell'
    $lines += 'cd ' + $script:Root
    $lines += 'pwsh -NoProfile -File tools/e2e.ps1' + $(if ($Strict) { ' -Strict' } else { '' })
    $lines += $bt + $bt + $bt
    $lines += ''
    $lines += '手工验证步骤见 ' + $bt + 'docs/VERIFY.md' + $bt + '；打包/安装/回滚见 ' + $bt + 'docs/RELEASE.md' + $bt + '。'
    $lines += ''
    $summaryPath = Join-Path $script:OutRoot 'SUMMARY.md'
    Set-Content -LiteralPath $summaryPath -Value ($lines -join $script:NL) -Encoding utf8NoBOM
    return [pscustomobject][ordered]@{ status = $overall.status; exitCode = $overall.exitCode; reason = $overall.reason; report = $jsonPath; summary = $summaryPath }
}

# ---------------------------------------------------------------------------------
# dry run: wiring self-check
# ---------------------------------------------------------------------------------
function Get-PlannedSteps {
    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue | Select-Object -First 1
    $nodePath = if ($nodeCmd) { $nodeCmd.Source } else { 'node' }
    $buildScript = Join-Path $script:Root 'build.ps1'
    $installer = Join-Path $script:Root 'install.ps1'
    return @(
        [pscustomobject][ordered]@{
            id = 'build'; title = 'pwsh -File build.ps1 -Tests'
            command = Format-CommandLine -FilePath $script:PwshExe -ArgumentList @('-NoProfile', '-File', $buildScript, '-Tests')
            prereqs = @('build.ps1', 'src')
        },
        [pscustomobject][ordered]@{
            id = 'engine'; title = 'bin/EngineTests.exe --json out/evidence/engine.json --png out/evidence/png/engine'
            command = 'bin/EngineTests.exe --json out/evidence/engine.json --png out/evidence/png/engine'
            prereqs = @('bin/EngineTests.exe')
        },
        [pscustomobject][ordered]@{
            id = 'selftest'; title = 'bin/SnipTool.exe --selftest out/evidence/selftest'
            command = 'bin/SnipTool.exe --selftest out/evidence/selftest'
            prereqs = @('bin/SnipTool.exe', 'src')
        },
        [pscustomobject][ordered]@{
            id = 'longshot-probe'; title = 'bin/SnipTool.exe --longshot-probe out/evidence/longshot'
            command = 'bin/SnipTool.exe --longshot-probe out/evidence/longshot'
            prereqs = @('bin/SnipTool.exe', 'src')
        },
        [pscustomobject][ordered]@{
            id = 'longshot-negative'; title = 'bin/SnipTool.exe --longshot-probe out/evidence/longshot-negative wheelOnly=false (must exit non-zero)'
            command = 'bin/SnipTool.exe --longshot-probe out/evidence/longshot-negative wheelOnly=false'
            prereqs = @('bin/SnipTool.exe', 'src')
        },
        [pscustomobject][ordered]@{
            id = 'crash-probe'; title = 'bin/SnipTool.exe --crash-probe out/evidence/crashprobe'
            command = 'bin/SnipTool.exe --crash-probe out/evidence/crashprobe'
            prereqs = @('bin/SnipTool.exe', 'src')
        },
        [pscustomobject][ordered]@{
            id = 'plugin'; title = 'node tools/plugin-smoke.mjs --root <repo> --json out/evidence/plugin-smoke.json'
            command = Format-CommandLine -FilePath $nodePath -ArgumentList @('tools/plugin-smoke.mjs', '--root', $script:Root, '--json', 'out/evidence/plugin-smoke.json')
            prereqs = @('tools/plugin-smoke.mjs', 'lib/index.js', 'lib/client.js', 'package.json')
        },
        [pscustomobject][ordered]@{
            id = 'install-plan'; title = 'pwsh -File install.ps1 -WhatIf'
            command = Format-CommandLine -FilePath $script:PwshExe -ArgumentList @('-NoProfile', '-File', $installer, '-WhatIf')
            prereqs = @('install.ps1')
        },
        [pscustomobject][ordered]@{
            id = 'package'; title = 'npm pack -> dsh-screenshot-<version>.tgz (files whitelist enforced)'
            command = '(cmd.exe /c) npm pack --json --loglevel=error   (cwd: ' + $script:Root + ')'
            prereqs = @('package.json', 'bin/SnipTool.exe', 'lib/index.js', 'lib/client.js', 'cordis.patch.yml')
        },
        [pscustomobject][ordered]@{
            id = 'docs'; title = 'docs/VERIFY.md R1..R30 + docs/RELEASE.md sections'
            command = '(built into tools/e2e.ps1 - no external command)'
            prereqs = @('docs/VERIFY.md', 'docs/RELEASE.md')
        }
    )
}

function Invoke-WiringCheck {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $problems = @()
    $notes = @()
    $facts = Get-HostFacts
    $script:Facts = $facts
    $requiredFiles = @(
        'build.ps1', 'install.ps1', 'package.json',
        'tools/plugin-smoke.mjs', 'tools/e2e.ps1',
        'docs/VERIFY.md', 'docs/RELEASE.md',
        'lib/index.js', 'lib/client.js', 'cordis.patch.yml'
    )
    foreach ($rel in $requiredFiles) {
        if (Test-MissingRel $rel) { $problems += "missing file: $rel" }
    }
    if (-not (Test-Path (Join-Path $script:Root 'src'))) { $problems += 'missing directory: src/' }
    if (-not $facts.csc) { $problems += "csc.exe not found: $script:CscPath" }
    if (-not $facts.node) { $problems += 'node is not on PATH' } else { $notes += "node $($facts.node)" }
    if (-not $facts.pnpm) { $notes += 'pnpm not on PATH (only needed for a real install run)' } else { $notes += "pnpm $($facts.pnpm)" }
    if (-not $facts.profileOk) { $notes += "desktop profile not found: $($facts.profileDir) (install.ps1 -WhatIf still prints its plan)" } else { $notes += "desktop profile: $($facts.profileDir)" }
    try {
        New-Item -ItemType Directory -Force -Path $script:OutRoot | Out-Null
        $probe = Join-Path $script:OutRoot '.write-probe'
        Set-Content -LiteralPath $probe -Value 'ok' -Encoding utf8NoBOM
        Remove-Item -LiteralPath $probe -Force
        $notes += ('evidence dir writable: ' + (Get-RelPath $script:OutRoot))
    } catch {
        $problems += ("evidence directory is not writable: {0} ({1})" -f $script:OutRoot, $_.Exception.Message)
    }
    $planned = Get-PlannedSteps
    $missingPrereqs = @()
    foreach ($p in $planned) {
        foreach ($rel in $p.prereqs) {
            if (-not (Test-Path (Join-Path $script:Root $rel))) { $missingPrereqs += ("{0} -> {1}" -f $p.id, $rel) }
        }
    }
    if ($missingPrereqs.Count -gt 0) { $notes += ('not built yet (expected until the owning module lands): ' + ($missingPrereqs -join ', ')) }

    if ($problems.Count -gt 0) {
        Add-Step -Id 'wiring' -Title 'wiring self-check (files, toolchain, writable evidence dir)' -Status 'fail' -Detail ($problems -join ' | ') -DurationMs ([int]$sw.ElapsedMilliseconds) -Warnings $notes | Out-Null
    } else {
        Add-Step -Id 'wiring' -Title 'wiring self-check (files, toolchain, writable evidence dir)' -Status 'pass' -Detail ($notes -join '; ') -DurationMs ([int]$sw.ElapsedMilliseconds) | Out-Null
    }
    foreach ($p in $planned) {
        $missingHere = @($p.prereqs | Where-Object { -not (Test-Path (Join-Path $script:Root $_)) })
        $detail = 'dry run: command not executed'
        if ($missingHere.Count -gt 0) { $detail += ('; prerequisite(s) not present yet: ' + ($missingHere -join ', ')) }
        Add-Step -Id $p.id -Title $p.title -Status 'planned' -Detail $detail -Command $p.command | Out-Null
    }
}

# ---------------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------------
Write-Host ''
Write-Host 'DSH screenshot plugin v2 — evidence chain'
Write-Host ('  root : ' + $script:Root)
Write-Host ('  mode : ' + $(if ($DryRun) { 'dry-run (wiring self-check only)' } else { 'run' }))
Write-Host ('  out  : ' + (Get-RelPath $script:OutRoot))
Write-Host ''

try {
    if ($DryRun) {
        Invoke-WiringCheck
    } else {
        Invoke-Preflight
        Invoke-BuildStep
        Invoke-EngineStep
        Invoke-SelftestStep
        Invoke-LongShotProbeStep
        Invoke-LongShotNegativeStep
        Invoke-CrashProbeStep
        Invoke-PluginStep
        Invoke-InstallPlanStep
        Invoke-PackageStep
        Invoke-DocsStep
    }
    $result = Write-Evidence -Mode $(if ($DryRun) { 'dry-run' } else { 'run' })
    Write-Host ''
    Write-Host ('overall: ' + $result.status.ToUpperInvariant() + '  (' + $result.reason + ')')
    Write-Host ('report : ' + (Get-RelPath $result.report))
    Write-Host ('summary: ' + (Get-RelPath $result.summary))
    Write-Host ''
    exit $result.exitCode
} catch {
    # Never leave the caller without a report: an unexpected harness failure is still evidence.
    $message = $_.Exception.Message
    $where = $_.InvocationInfo.PositionMessage
    Write-Host ''
    Write-Host ('HARNESS ERROR: ' + $message) -ForegroundColor Red
    Write-Host $where
    Add-Step -Id 'harness' -Title 'unexpected harness failure' -Status 'fail' -Detail ("$message @ $where") | Out-Null
    try {
        $result = Write-Evidence -Mode $(if ($DryRun) { 'dry-run' } else { 'run' })
        Write-Host ('report : ' + (Get-RelPath $result.report))
    } catch {
        Write-Host ('could not write evidence report: ' + $_.Exception.Message) -ForegroundColor Red
    }
    exit 1
}
