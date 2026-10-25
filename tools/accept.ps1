<#
.SYNOPSIS
  Versioned acceptance gate for the DSH screenshot plugin v2 (G-7).

.DESCRIPTION
  This is the versioned replacement for the ad-hoc out/captain-accept.ps1 rehearsal script.
  It EXECUTES the evidence chain through tools/e2e.ps1 (single source of truth for how each probe
  runs) and then re-asserts on the artifacts that run produced, so a weakened e2e step cannot make
  this gate pass. Everything it claims is read back from the JSON the probes wrote, never from
  console text (negative-control children leak their own FAIL lines into the console on purpose).

  Byte integrity: bin/*.exe, dist/*.tgz and every <repo>/*.tgz are hashed before and after the run and
  the comparison table is printed. With -NoBuild -SkipPack ANY change (or a new/removed file) is a
  hard failure: an acceptance run must not rewrite the very bytes it certifies.

  It never restarts DSH and never mutates the DSH profile (install.ps1 runs in -WhatIf mode).

  Exit codes: 0 = all checks passed, 1 = at least one check failed, 2 = usage/environment error.

.PARAMETER NoBuild
  Do not compile; use the existing bin/*.exe (they must be present).

.PARAMETER SkipPack
  Do not run npm pack; reuse the existing dsh-screenshot-<version>.tgz (repo root or dist/).

.PARAMETER SkipNative
  Skip the native overlay probes (engine/selftest/crash). Fast smoke only: those rows are
  recorded as skipped, never as passed.

.PARAMETER OutDir
  Where accept.json / ACCEPT.md / e2e.log and the nested e2e evidence go. A relative value resolves
  against the repository root. Defaults to out/ev-accept.

.EXAMPLE
  pwsh -NoProfile -File tools/accept.ps1 -NoBuild -SkipPack
#>
[CmdletBinding()]
param(
    [switch]$NoBuild,
    [switch]$SkipPack,
    [switch]$SkipNative,
    [string]$OutDir = 'out/ev-accept',
    [int]$E2eTimeoutSec = 900
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$script:Root = Split-Path -Parent $PSScriptRoot
$script:Rows = New-Object System.Collections.ArrayList
$script:Problems = New-Object System.Collections.ArrayList

function Add-Row {
    param([string]$Id, [string]$Title, [string]$Status, [string]$Detail)
    [void]$script:Rows.Add([pscustomobject][ordered]@{ id = $Id; title = $Title; status = $Status; detail = $Detail })
    if ($Status -eq 'fail') { [void]$script:Problems.Add($Id) }
    $tag = (@{ pass = 'PASS'; fail = 'FAIL'; skip = 'SKIP'; warn = 'WARN' })[$Status]
    Write-Host ('[{0,-4}] {1,-20} {2}' -f $tag, $Id, $Title)
    if ($Detail) { Write-Host (('        ' + $Detail)) }
}

function Get-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Get-RelPath {
    param([string]$Path)
    if (-not $Path) { return '' }
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full.StartsWith($script:Root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($script:Root.Length).TrimStart([char]92, [char]47).Replace([char]92, [char]47)
    }
    return $full
}

function Get-ArtifactSnapshot {
    $files = New-Object System.Collections.ArrayList
    $binDir = Join-Path $script:Root 'bin'
    if (Test-Path -LiteralPath $binDir) { foreach ($f in @(Get-ChildItem -LiteralPath $binDir -File -Filter '*.exe' -ErrorAction SilentlyContinue)) { [void]$files.Add($f) } }
    $distDir = Join-Path $script:Root 'dist'
    if (Test-Path -LiteralPath $distDir) { foreach ($f in @(Get-ChildItem -LiteralPath $distDir -File -Filter '*.tgz' -ErrorAction SilentlyContinue)) { [void]$files.Add($f) } }
    foreach ($f in @(Get-ChildItem -LiteralPath $script:Root -File -Filter '*.tgz' -ErrorAction SilentlyContinue)) { [void]$files.Add($f) }
    $map = [ordered]@{}
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($script:Root.Length).TrimStart([char]92, [char]47).Replace([char]92, [char]47)
        $hash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $map[$rel] = [pscustomobject][ordered]@{ sha256 = $hash; bytes = $f.Length; modifiedUtc = $f.LastWriteTimeUtc.ToString('o') }
    }
    return $map
}

function Compare-Snapshots {
    param($Before, $After)
    $changed = New-Object System.Collections.ArrayList
    $added = New-Object System.Collections.ArrayList
    $removed = New-Object System.Collections.ArrayList
    foreach ($k in $Before.Keys) {
        if (-not $After.Contains($k)) { [void]$removed.Add($k); continue }
        if ($Before[$k].sha256 -ne $After[$k].sha256) { [void]$changed.Add($k) }
    }
    foreach ($k in $After.Keys) { if (-not $Before.Contains($k)) { [void]$added.Add($k) } }
    return [pscustomobject][ordered]@{ changed = @($changed); added = @($added); removed = @($removed) }
}

function Write-SnapshotTable {
    param($Before, $After)
    Write-Host ''
    Write-Host 'artifact bytes: sha256 before -> after'
    Write-Host ('  {0,-30} {1,10} {2,-10} {3}' -f 'file', 'bytes', 'status', 'sha256 (first 16) before -> after')
    $keys = New-Object System.Collections.ArrayList
    foreach ($k in $Before.Keys) { [void]$keys.Add($k) }
    foreach ($k in $After.Keys) { if (-not $Before.Contains($k)) { [void]$keys.Add($k) } }
    foreach ($k in $keys) {
        $b = if ($Before.Contains($k)) { $Before[$k] } else { $null }
        $a = if ($After.Contains($k)) { $After[$k] } else { $null }
        $status = 'unchanged'
        if (-not $b) { $status = 'added' } elseif (-not $a) { $status = 'removed' } elseif ($b.sha256 -ne $a.sha256) { $status = 'CHANGED' }
        $bh = if ($b) { $b.sha256.Substring(0, 16) } else { '-' }
        $ah = if ($a) { $a.sha256.Substring(0, 16) } else { '-' }
        $bytesText = if ($a) { [string]$a.bytes } elseif ($b) { [string]$b.bytes } else { '-' }
        Write-Host ('  {0,-30} {1,10} {2,-10} {3} -> {4}' -f $k, $bytesText, $status, $bh, $ah)
    }
}

Write-Host ''
Write-Host 'DSH screenshot plugin v2 - acceptance gate (tools/accept.ps1)'
Write-Host ('  root : ' + $script:Root)
Write-Host ('  mode : ' + $(if ($NoBuild) { '-NoBuild ' } else { 'build ' }) + $(if ($SkipPack) { '-SkipPack ' } else { 'pack ' }) + $(if ($SkipNative) { '-SkipNative' } else { 'native probes' }))

$outAbs = if ([System.IO.Path]::IsPathRooted($OutDir)) { $OutDir } else { Join-Path $script:Root $OutDir }
if (-not (Test-Path -LiteralPath $outAbs)) { New-Item -ItemType Directory -Force -Path $outAbs | Out-Null }
$outFull = [System.IO.Path]::GetFullPath($outAbs)
if (-not $outFull.StartsWith($script:Root, [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Host ('-OutDir must stay inside the repository (' + $script:Root + '), got ' + $outFull) -ForegroundColor Red
    exit 2
}

Write-Host ('  out  : ' + (Get-RelPath $outFull))

# ---------------------------------------------------------------------------------
# 0. preconditions + byte snapshot
# ---------------------------------------------------------------------------------
$snipTool = Join-Path $script:Root 'bin/SnipTool.exe'
$engineExe = Join-Path $script:Root 'bin/EngineTests.exe'
if ($NoBuild) {
    if (-not (Test-Path -LiteralPath $snipTool)) {
        Add-Row 'precondition' 'bin/SnipTool.exe exists (-NoBuild needs a previous build)' 'fail' 'missing bin/SnipTool.exe; run without -NoBuild once'
    }
    if (-not (Test-Path -LiteralPath $engineExe)) {
        Add-Row 'precondition' 'bin/EngineTests.exe exists (-NoBuild needs a previous build)' 'fail' 'missing bin/EngineTests.exe; run without -NoBuild once'
    }
}
if ($SkipPack) {
    $tgz = @(Get-ChildItem -LiteralPath $script:Root -File -Filter 'dsh-screenshot-*.tgz' -ErrorAction SilentlyContinue)
    $distDir = Join-Path $script:Root 'dist'
    if (Test-Path -LiteralPath $distDir) { $tgz += @(Get-ChildItem -LiteralPath $distDir -File -Filter 'dsh-screenshot-*.tgz' -ErrorAction SilentlyContinue) }
    if ($tgz.Count -eq 0) {
        Add-Row 'precondition' 'a dsh-screenshot-<version>.tgz exists (-SkipPack reuses it)' 'fail' 'no tarball in the repo root or dist/; run without -SkipPack'
    } else {
        Add-Row 'precondition' 'a dsh-screenshot-<version>.tgz exists (-SkipPack reuses it)' 'pass' (($tgz | ForEach-Object { $_.Name + ' (' + $_.Length + ' bytes)' }) -join ', ')
    }
}
$before = Get-ArtifactSnapshot
if ($before.Count -eq 0) { Add-Row 'snapshot' 'artifact byte snapshot (bin/*.exe, dist/*.tgz, <repo>/*.tgz)' 'fail' 'nothing to hash: no binaries and no tarball' }
else { Add-Row 'snapshot' 'artifact byte snapshot (bin/*.exe, dist/*.tgz, <repo>/*.tgz)' 'pass' (($before.Keys) -join ', ') }

# ---------------------------------------------------------------------------------
# 1. run the evidence chain (tools/e2e.ps1 is the only executor)
# ---------------------------------------------------------------------------------
$e2e = Join-Path $PSScriptRoot 'e2e.ps1'
if (-not (Test-Path -LiteralPath $e2e)) { Write-Host 'tools/e2e.ps1 is missing' -ForegroundColor Red; exit 2 }
$pwshExe = (Get-Process -Id $PID).Path
$e2eOut = Join-Path $outFull 'e2e'
$e2eArgs = @('-NoProfile', '-File', $e2e, '-OutDir', $e2eOut)
if ($NoBuild) { $e2eArgs += '-SkipBuild' }
if ($SkipPack) { $e2eArgs += '-SkipPack' }
if ($SkipNative) { $e2eArgs += '-SkipNative' }
Write-Host ''
Write-Host ('running: pwsh ' + ($e2eArgs -join ' '))
$e2eLog = Join-Path $outFull 'e2e.log'
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$e2eOutput = & $pwshExe @e2eArgs 2>&1
$e2eCode = $LASTEXITCODE
$sw.Stop()
$e2eOutput | Set-Content -LiteralPath $e2eLog -Encoding utf8NoBOM
Write-Host ('e2e finished: exit=' + $e2eCode + ' in ' + [int]$sw.Elapsed.TotalSeconds + 's, log: ' + (Get-RelPath $e2eLog))
$report = Get-JsonFile (Join-Path $e2eOut 'report.json')
if ($null -eq $report) {
    Add-Row 'e2e-run' 'tools/e2e.ps1 produced out/report.json' 'fail' ('exit=' + $e2eCode + ', no report.json under ' + (Get-RelPath $e2eOut))
} else {
    $okRun = ($e2eCode -eq 0 -and $report.ok -eq $true -and [string]$report.status -eq 'pass' -and [int]$report.counts.fail -eq 0)
    Add-Row 'e2e-run' 'tools/e2e.ps1 exits 0 and report.ok=true' $(if ($okRun) { 'pass' } else { 'fail' }) ('exit=' + $e2eCode + ' status=' + $report.status + ' pass=' + $report.counts.pass + ' fail=' + $report.counts.fail + ' pending=' + $report.counts.pending)
}
$steps = @()
if ($null -ne $report) { $steps = @($report.steps) }
function Get-StepStatus { param([string]$Id) $s = @($steps | Where-Object { $_.id -eq $Id }); if ($s.Count -eq 0) { return 'missing' }; return [string]$s[0].status }

# ---------------------------------------------------------------------------------
# 2. step-level assertions (read the report, never the console)
# ---------------------------------------------------------------------------------
$buildWant = if ($NoBuild) { 'skipped' } else { 'pass' }
Add-Row 'step-build' 'build step status' $(if ((Get-StepStatus 'build') -eq $buildWant) { 'pass' } else { 'fail' }) ('build=' + (Get-StepStatus 'build') + ' (expected ' + $buildWant + ')')
Add-Row 'step-contract' 'client-contract step status (real slots gate must run)' $(if ((Get-StepStatus 'client-contract') -eq 'pass') { 'pass' } else { 'fail' }) ('client-contract=' + (Get-StepStatus 'client-contract'))
Add-Row 'step-plugin' 'plugin smoke step status' $(if ((Get-StepStatus 'plugin') -eq 'pass') { 'pass' } else { 'fail' }) ('plugin=' + (Get-StepStatus 'plugin'))
Add-Row 'step-install-plan' 'install.ps1 -WhatIf step status (plan only, no mutation)' $(if ((Get-StepStatus 'install-plan') -eq 'pass') { 'pass' } else { 'fail' }) ('install-plan=' + (Get-StepStatus 'install-plan'))
$packWant = if ($SkipPack) { 'skipped' } else { 'pass' }
Add-Row 'step-package' 'package step status' $(if ((Get-StepStatus 'package') -eq $packWant) { 'pass' } else { 'fail' }) ('package=' + (Get-StepStatus 'package') + ' (expected ' + $packWant + ')')
$nativeWant = if ($SkipNative) { 'skipped' } else { 'pass' }
foreach ($nid in @('engine', 'selftest', 'crash-probe')) {
    $st = Get-StepStatus $nid
    $okStep = ($st -eq $nativeWant)
    Add-Row ('step-' + $nid) ('native step ' + $nid) $(if ($okStep) { 'pass' } else { 'fail' }) ($nid + '=' + $st + ' (expected ' + $nativeWant + ')')
}
Add-Row 'step-docs' 'docs step status (VERIFY R1..R30 + manual markers + RELEASE sections)' $(if ((Get-StepStatus 'docs') -eq 'pass') { 'pass' } else { 'fail' }) ('docs=' + (Get-StepStatus 'docs'))

# ---------------------------------------------------------------------------------
# 3. artifact assertions: what the probes actually wrote
# ---------------------------------------------------------------------------------
$engineJson = Get-JsonFile (Join-Path $e2eOut 'engine.json')
if ($SkipNative) {
    Add-Row 'engine-json' 'engine.json: every detection check passed' 'skip' 'skipped by -SkipNative'
} elseif ($null -eq $engineJson) {
    Add-Row 'engine-json' 'engine.json: every detection check passed' 'fail' 'engine.json is missing'
} else {
    $bad = @($engineJson.checks | Where-Object { $_.status -ne 'passed' } | ForEach-Object { $_.name })
    Add-Row 'engine-json' 'engine.json: every detection check passed' $(if ($bad.Count -eq 0 -and @($engineJson.checks).Count -gt 0) { 'pass' } else { 'fail' }) ('checks=' + @($engineJson.checks).Count + ' failed=[' + ($bad -join ', ') + ']')
}

$selftestSummary = Get-JsonFile (Join-Path $e2eOut 'selftest/summary.json')
$requiredCriteria = @('A1', 'A2', 'A6', 'A7', 'A9/R26')
if ($SkipNative) {
    Add-Row 'selftest-summary' 'selftest summary: 5 criteria present and passed' 'skip' 'skipped by -SkipNative'
} elseif ($null -eq $selftestSummary) {
    Add-Row 'selftest-summary' 'selftest summary: 5 criteria present and passed' 'fail' 'selftest/summary.json is missing'
} else {
    $got = @($selftestSummary.results | ForEach-Object { [string]$_.criterion })
    $missingCrit = @($requiredCriteria | Where-Object { $got -notcontains $_ })
    $notPassed = @($selftestSummary.results | Where-Object { $_.status -ne 'passed' } | ForEach-Object { $_.criterion + '=' + $_.status })
    $pngDir = Join-Path $e2eOut 'selftest'
    $pngCount = @(Get-ChildItem -LiteralPath $pngDir -File -Filter '*.png' -ErrorAction SilentlyContinue).Count
    $okSelf = ($missingCrit.Count -eq 0 -and $notPassed.Count -eq 0 -and $pngCount -ge 6)
    Add-Row 'selftest-summary' 'selftest summary: 5 criteria present and passed (+ >=6 PNGs)' $(if ($okSelf) { 'pass' } else { 'fail' }) ('criteria=' + $got.Count + ' missing=[' + ($missingCrit -join ', ') + '] failed=[' + ($notPassed -join ', ') + '] pngs=' + $pngCount)
}

$crash = Get-JsonFile (Join-Path $e2eOut 'crashprobe/crash_probe.json')
if ($SkipNative) {
    Add-Row 'crash-probe-json' 'crash_probe.json: log rotated, bytes grew' 'skip' 'skipped by -SkipNative'
} elseif ($null -eq $crash) {
    Add-Row 'crash-probe-json' 'crash_probe.json: log rotated, bytes grew' 'fail' 'crashprobe/crash_probe.json is missing'
} else {
    $okCrash = ($crash.ok -eq $true -and [int]$crash.afterBytes -gt [int]$crash.beforeBytes -and ([string]$crash.logPath).EndsWith('dsh-snip-error.log'))
    Add-Row 'crash-probe-json' 'crash_probe.json: log rotated, bytes grew' $(if ($okCrash) { 'pass' } else { 'fail' }) ('ok=' + $crash.ok + ' bytes=' + $crash.beforeBytes + '->' + $crash.afterBytes + ' log=' + $crash.logPath)
}

$contract = Get-JsonFile (Join-Path $e2eOut 'ev-contract/client-contract.json')
if ($null -eq $contract) {
    Add-Row 'client-contract-json' 'client-contract.json: 15 checks pass, shipped 2.0.0 bundle rejected' 'fail' 'ev-contract/client-contract.json is missing'
} else {
    $badC = @($contract.checks | Where-Object { $_.status -ne 'pass' } | ForEach-Object { $_.id })
    $negObs = @($contract.negative.observedCategories)
    $negWant = @('missing-inject', 'non-function-callback', 'single-slot-conflict')
    $negMissing = @($negWant | Where-Object { $negObs -notcontains $_ })
    $regText = (@($contract.registrations | ForEach-Object { $_.slot + '/' + $_.id + '@' + $_.priority }) -join ',')
    $okC = ($contract.ok -eq $true -and $badC.Count -eq 0 -and $negMissing.Count -eq 0 -and @($contract.checks).Count -ge 15 -and $regText.Contains('conversation.input.right/shot-action@100'))
    Add-Row 'client-contract-json' 'client-contract.json: 15 checks pass, shipped 2.0.0 bundle rejected' $(if ($okC) { 'pass' } else { 'fail' }) ('checks=' + @($contract.checks).Count + ' failed=[' + ($badC -join ', ') + '] negative missing=[' + ($negMissing -join ', ') + '] registrations=' + $regText)
}
$contractNotes = $null
if ($null -ne $contract) {
    $verbatimIds = @($contract.contract.verbatim | ForEach-Object { $_.id })
    $guardIds = @($contract.contract.guardrails | ForEach-Object { $_.id })
    $wantVerbatim = @('missing-inject', 'single-slot-conflict')
    $wantGuard = @('non-function-callback', 'register-name')
    $missV = @($wantVerbatim | Where-Object { $verbatimIds -notcontains $_ })
    $missG = @($wantGuard | Where-Object { $guardIds -notcontains $_ })
    $perCheckProv = @($contract.checks | Where-Object { -not $_.provenance })
    $okProv = ($missV.Count -eq 0 -and $missG.Count -eq 0 -and $perCheckProv.Count -eq 0)
    Add-Row 'contract-provenance' 'client-contract.json: verbatim vs harness-guardrail provenance is declared (M-4)' $(if ($okProv) { 'pass' } else { 'fail' }) ('verbatim=[' + ($verbatimIds -join ', ') + '] guardrails=[' + ($guardIds -join ', ') + '] checks without provenance=' + $perCheckProv.Count)
}

$smoke = Get-JsonFile (Join-Path $e2eOut 'plugin-smoke.json')
if ($null -eq $smoke) {
    Add-Row 'plugin-smoke-json' 'plugin-smoke.json: 8 checks pass incl client-load via the real contract' 'fail' 'plugin-smoke.json is missing'
} else {
    $badS = @($smoke.checks | Where-Object { $_.status -ne 'pass' } | ForEach-Object { $_.id + '=' + $_.status })
    $clientLoad = @($smoke.checks | Where-Object { $_.id -eq 'client-load' })
    $clientDetail = if ($clientLoad.Count -gt 0) { [string]$clientLoad[0].detail } else { '' }
    $okS = ([string]$smoke.status -eq 'pass' -and $badS.Count -eq 0 -and @($smoke.checks).Count -ge 8 -and $clientDetail.Contains('real slots contract'))
    Add-Row 'plugin-smoke-json' 'plugin-smoke.json: 8 checks pass incl client-load via the real contract' $(if ($okS) { 'pass' } else { 'fail' }) ('status=' + $smoke.status + ' checks=' + @($smoke.checks).Count + ' failed=[' + ($badS -join ', ') + '] client-load=' + $clientDetail)
}

# ---------------------------------------------------------------------------------
# 5. byte integrity: did this run rewrite the artifacts it certifies?
# ---------------------------------------------------------------------------------
$after = Get-ArtifactSnapshot
Write-SnapshotTable -Before $before -After $after
$diff = Compare-Snapshots -Before $before -After $after
$diffText = 'changed=[' + ($diff.changed -join ', ') + '] added=[' + ($diff.added -join ', ') + '] removed=[' + ($diff.removed -join ', ') + ']'
$bytesClean = ($diff.changed.Count -eq 0 -and $diff.added.Count -eq 0 -and $diff.removed.Count -eq 0)
if ($NoBuild -and $SkipPack) {
    Add-Row 'bytes-unchanged' 'bin/*.exe + dist/*.tgz byte-identical (-NoBuild -SkipPack must not rewrite what they certify)' $(if ($bytesClean) { 'pass' } else { 'fail' }) $diffText
} else {
    Add-Row 'bytes-unchanged' 'bin/*.exe + dist/*.tgz byte-identical (not required without both -NoBuild -SkipPack)' $(if ($bytesClean) { 'pass' } else { 'warn' }) ($diffText + ' - expected because the run rebuilt/re-packed')
}

# ---------------------------------------------------------------------------------
# 6. verdict + machine-readable record
# ---------------------------------------------------------------------------------
$counts = [ordered]@{ pass = 0; fail = 0; skip = 0; warn = 0 }
foreach ($r in $script:Rows) { $counts[$r.status] = [int]$counts[$r.status] + 1 }
$ok = ($counts.fail -eq 0)
$result = [pscustomobject][ordered]@{
    schema = 'dsh-screenshot-accept/v1'
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    root = $script:Root
    mode = [pscustomobject][ordered]@{ noBuild = [bool]$NoBuild; skipPack = [bool]$SkipPack; skipNative = [bool]$SkipNative }
    ok = $ok
    counts = [pscustomobject]$counts
    checks = @($script:Rows)
    artifacts = [pscustomobject][ordered]@{ before = $before; after = $after; changed = @($diff.changed); added = @($diff.added); removed = @($diff.removed) }
    e2e = [pscustomobject][ordered]@{ exitCode = $e2eCode; evidenceDir = (Get-RelPath $e2eOut); log = (Get-RelPath $e2eLog) }
}
$jsonPath = Join-Path $outFull 'accept.json'
($result | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $jsonPath -Encoding utf8NoBOM
$mdLines = New-Object System.Collections.ArrayList
[void]$mdLines.Add('# acceptance gate - tools/accept.ps1')
[void]$mdLines.Add('')
[void]$mdLines.Add('- generated: ' + $result.generatedAt)
[void]$mdLines.Add('- mode: noBuild=' + $NoBuild + ' skipPack=' + $SkipPack + ' skipNative=' + $SkipNative)
[void]$mdLines.Add('- e2e: exit=' + $e2eCode + ', evidence ' + (Get-RelPath $e2eOut) + ', log ' + (Get-RelPath $e2eLog))
[void]$mdLines.Add('- counts: pass=' + $counts.pass + ' fail=' + $counts.fail + ' warn=' + $counts.warn + ' skip=' + $counts.skip)
[void]$mdLines.Add('')
[void]$mdLines.Add('| check | status | detail |')
[void]$mdLines.Add('| --- | --- | --- |')
foreach ($r in $script:Rows) { [void]$mdLines.Add('| ' + $r.id + ' | ' + $r.status + ' | ' + ($r.detail -replace '\|', '\|') + ' |') }
[void]$mdLines.Add('')
[void]$mdLines.Add('## artifact bytes (sha256 before -> after)')
[void]$mdLines.Add('')
[void]$mdLines.Add('| file | bytes | status | sha256 before -> after |')
[void]$mdLines.Add('| --- | --- | --- | --- |')
foreach ($k in $after.Keys) {
    $b = if ($before.Contains($k)) { $before[$k].sha256 } else { '-' }
    $a = $after[$k].sha256
    $st = if ($b -eq '-') { 'added' } elseif ($b -ne $a) { 'changed' } else { 'unchanged' }
    [void]$mdLines.Add('| ' + $k + ' | ' + $after[$k].bytes + ' | ' + $st + ' | ' + $b + ' -> ' + $a + ' |')
}
$mdPath = Join-Path $outFull 'ACCEPT.md'
$mdLines | Set-Content -LiteralPath $mdPath -Encoding utf8NoBOM

Write-Host ''
Write-Host ('checks: pass=' + $counts.pass + ' fail=' + $counts.fail + ' warn=' + $counts.warn + ' skip=' + $counts.skip)
Write-Host ('record: ' + (Get-RelPath $jsonPath) + ' / ' + (Get-RelPath $mdPath))
if ($ok) {
    Write-Host 'RESULT: ACCEPT (all checks passed)'
    exit 0
}
Write-Host ('RESULT: REJECT (' + ($script:Problems -join ', ') + ')') -ForegroundColor Red
exit 1
