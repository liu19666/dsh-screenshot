#Requires -Version 7.0
<#
.SYNOPSIS
  Install the DSH screenshot plugin (dsh-screenshot) into a DSH desktop profile.

.DESCRIPTION
  The installer changes exactly three things in the target profile and nothing else:

    1. 备份   copy package.json and cordis.patch.yml into <profile>/.backup-install-<stamp>/
    2. 安装   run "pnpm add file:<tgz>" inside the profile directory
    3. 注册   append "dsh-screenshot" to dsh.profile.bundles in <profile>/package.json

  Then it prints 「需重启 DSH 生效」 and stops. This script NEVER restarts, stops or
  otherwise touches the DSH process, never edits DSH resources/app, and never rewrites
  the bundles of any other plugin: the existing dsh.profile.bundles entries are read,
  verified to be preserved in order, and written back with the new name appended.

  -WhatIf prints the full plan (backup paths, exact pnpm command, the bundles delta,
  the restart reminder) and changes nothing at all. Always run -WhatIf first.

  -Rollback restores package.json and cordis.patch.yml from the newest
  .backup-install-* directory of the profile and prints the restart reminder.

.PARAMETER WhatIf
  Print the plan and exit without touching anything.

.PARAMETER Rollback
  Restore the newest backup instead of installing.

.PARAMETER ProfileDir
  DSH profile to install into. Defaults to $env:DSH_PROFILE, then
  %USERPROFILE%\.dsh\profiles\desktop.

.PARAMETER Tgz
  The packed plugin tarball (dsh-screenshot-<version>.tgz). Defaults to the newest
  *.tgz found in the repository root, out/dist/ or bin/.

.PARAMETER PackageName
  Package name to append to dsh.profile.bundles. Defaults to dsh-screenshot.

.PARAMETER Force
  Reinstall even when the package already looks installed.

.PARAMETER PnpmTimeoutSec
  Hard limit for the pnpm step (the backup is restored automatically if it fails).

.EXAMPLE
  pwsh -NoProfile -File install.ps1 -WhatIf

.EXAMPLE
  pwsh -NoProfile -File install.ps1 -Tgz out/dist/dsh-screenshot-1.0.5.tgz

.EXAMPLE
  pwsh -NoProfile -File install.ps1 -Rollback
#>
[CmdletBinding()]
param(
    [switch]$WhatIf,
    [switch]$Rollback,
    [string]$ProfileDir,
    [string]$Tgz,
    [string]$PackageName = 'dsh-screenshot',
    [switch]$Force,
    [int]$PnpmTimeoutSec = 300
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$script:RepoRoot = $PSScriptRoot
$script:NL = [string][char]10
$script:DidChange = $false
$script:PnpmExe = $null

# ---------------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------------

function Get-Stamp { return (Get-Date -Format 'yyyyMMdd-HHmmss') }

function Write-PlanLine {
    param([string]$Step, [string]$Text)
    Write-Host ('  [{0}] {1}' -f $Step, $Text)
}

function Resolve-Profile {
    param([string]$Explicit)
    if ($Explicit) {
        if (-not (Test-Path -LiteralPath $Explicit)) { throw "profile directory not found: $Explicit" }
        return [System.IO.Path]::GetFullPath($Explicit)
    }
    # Host environment hints, most specific first. DSH_PROFILE holds the profile *name*
    # (e.g. "desktop"), DSH_PROFILE_DIR the absolute directory, DSH_HOME the .dsh root.
    if ($env:DSH_PROFILE_DIR -and (Test-Path -LiteralPath $env:DSH_PROFILE_DIR)) {
        return [System.IO.Path]::GetFullPath($env:DSH_PROFILE_DIR)
    }
    $dshHome = $env:DSH_HOME
    if (-not $dshHome) { $dshHome = Join-Path $env:USERPROFILE '.dsh' }
    $profileName = $env:DSH_PROFILE
    if (-not $profileName) { $profileName = 'desktop' }
    # DSH_PROFILE holds a profile *name* ("desktop"), not a path: only honour it as a directory when
    # the value is rooted, otherwise a folder called "desktop" in whatever cwd happens to be current
    # would silently win over the real profile under DSH_HOME (F-19).
    if ($profileName -and [System.IO.Path]::IsPathRooted($profileName) -and (Test-Path -LiteralPath $profileName -PathType Container)) {
        return [System.IO.Path]::GetFullPath($profileName)
    }
    $candidate = Join-Path (Join-Path $dshHome 'profiles') $profileName
    if (Test-Path -LiteralPath $candidate) { return [System.IO.Path]::GetFullPath($candidate) }
    $default = Join-Path $env:USERPROFILE '.dsh/profiles/desktop'
    if (Test-Path -LiteralPath $default) { return [System.IO.Path]::GetFullPath($default) }
    throw ("desktop profile not found (tried DSH_PROFILE_DIR, {0}, {1}); pass -ProfileDir explicitly" -f $candidate, $default)
}

function Resolve-Tgz {
    param([string]$Explicit)
    if ($Explicit) {
        $candidate = $Explicit
        if (-not [System.IO.Path]::IsPathRooted($candidate)) { $candidate = Join-Path $script:RepoRoot $candidate }
        if (-not (Test-Path -LiteralPath $candidate)) { throw "tarball not found: $candidate" }
        return [System.IO.Path]::GetFullPath($candidate)
    }
    $roots = @(
        $script:RepoRoot,
        (Join-Path $script:RepoRoot 'out/dist'),
        (Join-Path $script:RepoRoot 'bin'),
        (Join-Path $script:RepoRoot 'out')
    )
    $found = @()
    foreach ($dir in $roots) {
        if (Test-Path -LiteralPath $dir) {
            $found += @(Get-ChildItem -LiteralPath $dir -Filter '*.tgz' -File -ErrorAction SilentlyContinue)
        }
    }
    if ($found.Count -eq 0) { return $null }
    return ($found | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}

function Find-Pnpm {
    # Get-Command prefers the pnpm.ps1 shim on PowerShell; a script cannot be started
    # directly through Process.Start, so return the kind together with the path.
    $cmd = Get-Command pnpm -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cmd) { return $null }
    $path = $cmd.Source
    $ext = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
    $kind = 'exe'
    if ($ext -eq '.ps1') {
        $kind = 'ps1'
        $sibling = [System.IO.Path]::ChangeExtension($path, '.cmd')
        if (Test-Path -LiteralPath $sibling) { return [pscustomobject]@{ path = $sibling; kind = 'cmd' } }
    } elseif ($ext -eq '.cmd' -or $ext -eq '.bat') {
        $kind = 'cmd'
    }
    return [pscustomobject]@{ path = $path; kind = $kind }
}

function Get-NewestBackup {
    param([string]$Profile)
    $dirs = @(Get-ChildItem -LiteralPath $Profile -Directory -Filter '.backup-install-*' -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
    if ($dirs.Count -eq 0) { return $null }
    return $dirs[0].FullName
}

function Get-BundleList {
    param([object]$PackageJson)
    $empty = @{ list = @(); source = 'none' }
    if (-not $PackageJson) { return $empty }
    if (-not ($PackageJson -is [System.Collections.IDictionary])) { return $empty }
    if (-not $PackageJson.Contains('dsh')) { return $empty }
    $dsh = $PackageJson['dsh']
    if (-not ($dsh -is [System.Collections.IDictionary])) { return $empty }
    if (-not $dsh.Contains('profile')) { return $empty }
    $profile = $dsh['profile']
    if (-not ($profile -is [System.Collections.IDictionary])) { return $empty }
    if (-not $profile.Contains('bundles')) { return $empty }
    return @{ list = @($profile['bundles']); source = 'dsh.profile.bundles' }
}

function Invoke-PnpmAdd {
    param([object]$Pnpm, [string]$Spec, [string]$WorkingDirectory, [int]$TimeoutSec, [string]$LogPath)
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    if ($Pnpm.kind -eq 'ps1') {
        $psi.FileName = (Get-Process -Id $PID).Path
        $psi.ArgumentList.Add('-NoProfile')
        $psi.ArgumentList.Add('-File')
        $psi.ArgumentList.Add($Pnpm.path)
    } elseif ($Pnpm.kind -eq 'cmd') {
        $psi.FileName = (Join-Path $env:SystemRoot 'System32\cmd.exe')
        $psi.ArgumentList.Add('/c')
        $psi.ArgumentList.Add($Pnpm.path)
    } else {
        $psi.FileName = $Pnpm.path
    }
    $psi.ArgumentList.Add('add')
    $psi.ArgumentList.Add($Spec)
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()
    $timedOut = $false
    if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
        $timedOut = $true
        try { $proc.Kill($true) } catch { try { $proc.Kill() } catch { } }
        try { [void]$proc.WaitForExit(5000) } catch { }
    }
    $out = ''
    $err = ''
    try { $out = [string]$outTask.Result } catch { }
    try { $err = [string]$errTask.Result } catch { }
    $code = -1
    if (-not $timedOut) { try { $code = $proc.ExitCode } catch { $code = -3 } }
    try { $proc.Dispose() } catch { }
    $log = @(
        '# pnpm add ' + $Spec,
        '# cwd : ' + $WorkingDirectory,
        '# when: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'),
        '# exit: ' + $code + '  timedOut=' + $timedOut,
        '--- stdout ---',
        $out,
        '--- stderr ---',
        $err
    ) -join $script:NL
    Set-Content -LiteralPath $LogPath -Value $log -Encoding utf8NoBOM
    return [pscustomobject]@{ exitCode = $code; timedOut = $timedOut; stdout = $out; stderr = $err; log = $LogPath }
}

function Read-PackageJson {
    param([string]$Path)
    $raw = Get-Content -LiteralPath $Path -Raw
    if (-not $raw) { throw "empty package.json: $Path" }
    return ($raw | ConvertFrom-Json -AsHashtable)
}

function Add-BundleEntry {
    # Appends one entry to dsh.profile.bundles by editing the JSON text in place instead of
    # re-serialising the whole document: a ConvertTo-Json round trip rewrites every key, drops the
    # host's formatting and can reorder the fields the DSH loader reads (F-19). The only bytes that
    # change here are the new array element.
    param([string]$Path, [string]$Name, [string[]]$ExpectedBefore)
    $raw = Get-Content -LiteralPath $Path -Raw
    if (-not $raw) { throw "empty package.json: $Path" }
    $profileMatch = [regex]::Match($raw, '"profile"\s*:\s*\{')
    $searchFrom = 0
    if ($profileMatch.Success) { $searchFrom = $profileMatch.Index }
    $bundlesMatch = [regex]::Match($raw.Substring($searchFrom), '"bundles"\s*:\s*\[')
    if (-not $bundlesMatch.Success) { throw 'refusing to write package.json: no dsh.profile.bundles array found' }
    $open = $raw.IndexOf('[', $searchFrom + $bundlesMatch.Index)
    $depth = 0
    $close = -1
    for ($i = $open; $i -lt $raw.Length; $i++) {
        $ch = $raw[$i]
        if ($ch -eq [char]34) {
            # skip the whole JSON string: a ']' inside a bundle name must not close the array early
            $i++
            while ($i -lt $raw.Length) {
                if ($raw[$i] -eq [char]92) { $i += 2; continue }
                if ($raw[$i] -eq [char]34) { break }
                $i++
            }
            continue
        }
        if ($ch -eq '[') { $depth++ }
        elseif ($ch -eq ']') {
            $depth--
            if ($depth -eq 0) { $close = $i; break }
        }
    }
    if ($close -lt 0) { throw 'refusing to write package.json: unbalanced dsh.profile.bundles array' }

    $body = $raw.Substring($open + 1, $close - $open - 1)
    $quoted = '"' + $Name + '"'
    if ($body.Trim().Length -eq 0) {
        $patched = $raw.Substring(0, $open + 1) + $quoted + $raw.Substring($close)
    } else {
        $lastChunk = $body.TrimEnd()
        $elementEnd = $open + 1 + $lastChunk.Length
        $trailing = $raw.Substring($elementEnd, $close - $elementEnd)
        $nlIndex = $lastChunk.LastIndexOf([char]10)
        $indent = ''
        if ($nlIndex -ge 0) {
            # keep the new element on the same column as the last existing one
            $line = $lastChunk.Substring($nlIndex + 1)
            $k = 0
            while ($k -lt $line.Length -and ($line[$k] -eq ' ' -or $line[$k] -eq [char]9)) { $k++ }
            if ($k -gt 0) { $indent = $line.Substring(0, $k) }
        }
        if ($nlIndex -lt 0) {
            $patched = $raw.Substring(0, $elementEnd) + ', ' + $quoted + $trailing + $raw.Substring($close)
        } else {
            $patched = $raw.Substring(0, $elementEnd) + ',' + $script:NL + $indent + $quoted + $trailing + $raw.Substring($close)
        }
    }

    $temp = $Path + '.tmp-install'
    Set-Content -LiteralPath $temp -Value $patched -Encoding utf8NoBOM
    # verify before swapping the real file in place: it must still parse, the bundles must be the old
    # list plus exactly this package, and every other field must be byte-identical in value terms.
    try {
        $check = Get-Content -LiteralPath $temp -Raw | ConvertFrom-Json -AsHashtable
        $after = @((Get-BundleList $check).list)
        $ok = ($after.Count -eq ($ExpectedBefore.Count + 1)) -and ($after[$after.Count - 1] -eq $Name)
        for ($i = 0; $ok -and $i -lt $ExpectedBefore.Count; $i++) {
            if ($after[$i] -ne $ExpectedBefore[$i]) { $ok = $false }
        }
        if ($ok) {
            $before = $raw | ConvertFrom-Json -AsHashtable
            $before['dsh']['profile']['bundles'] = @()
            $check['dsh']['profile']['bundles'] = @()
            if (($before | ConvertTo-Json -Depth 32 -Compress) -ne ($check | ConvertTo-Json -Depth 32 -Compress)) { $ok = $false }
        }
        if (-not $ok) { throw 'the patched document does not match the intended change' }
    } catch {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        throw ('refusing to write package.json: ' + $_.Exception.Message)
    }
    Move-Item -LiteralPath $temp -Destination $Path -Force
}

# ---------------------------------------------------------------------------------
# rollback
# ---------------------------------------------------------------------------------

function Invoke-RollbackPlan {
    param([string]$Profile)
    $backup = Get-NewestBackup -Profile $Profile
    Write-Host ''
    Write-Host 'DSH screenshot plugin — rollback plan'
    Write-Host ('  profile : ' + $Profile)
    if (-not $backup) {
        Write-Host '  backup  : none found (.backup-install-* is missing)'
        Write-Host ('  result  : nothing to roll back; install first, or restore manually from ' + (Join-Path $Profile '.backup-install-*'))
        return $false
    }
    Write-Host ('  backup  : ' + $backup)
    foreach ($name in @('package.json', 'cordis.patch.yml')) {
        $src = Join-Path $backup $name
        $dst = Join-Path $Profile $name
        $has = Test-Path -LiteralPath $src
        $state = if ($has) { 'restore' } else { 'MISSING in backup' }
        Write-PlanLine 'rollback' ('{0} : {1} -> {2}' -f $name, $state, $dst)
    }
    Write-Host ''
    Write-Host '  note    : after restoring package.json run "pnpm install" in the profile to prune node_modules.'
    Write-Host '  需重启 DSH 生效（本脚本不会重启 DSH）'
    return $true
}

function Invoke-Rollback {
    param([string]$Profile)
    $backup = Get-NewestBackup -Profile $Profile
    if (-not $backup) { Write-Host 'no .backup-install-* directory to restore'; exit 1 }
    $restored = @()
    foreach ($name in @('package.json', 'cordis.patch.yml')) {
        $src = Join-Path $backup $name
        if (-not (Test-Path -LiteralPath $src)) {
            Write-Host ('missing in backup: ' + $src)
            exit 1
        }
        $dst = Join-Path $Profile $name
        Copy-Item -LiteralPath $src -Destination $dst -Force
        $restored += $dst
    }
    $bundles = @((Get-BundleList (Read-PackageJson (Join-Path $Profile 'package.json'))).list)
    Write-Host ''
    Write-Host 'rollback done:'
    foreach ($r in $restored) { Write-Host ('  restored ' + $r) }
    Write-Host ('  dsh.profile.bundles now has {0} entries; contains {1}: {2}' -f $bundles.Count, $PackageName, ($bundles -contains $PackageName))
    Write-Host ''
    Write-Host '  next: run "pnpm install" in the profile if node_modules should drop the package.'
    Write-Host '  需重启 DSH 生效（本脚本不会重启 DSH）'
    Write-Host ''
    exit 0
}

# ---------------------------------------------------------------------------------
# install plan / install
# ---------------------------------------------------------------------------------

function Show-InstallPlan {
    param([string]$Profile, [string]$Tarball, [object]$Pnpm, [bool]$AlreadyInstalled, [string]$BackupDir, [string[]]$Bundles)
    Write-Host ''
    Write-Host 'DSH screenshot plugin — install plan'
    Write-Host ('  repo    : ' + $script:RepoRoot)
    Write-Host ('  profile : ' + $Profile)
    if ($Tarball) {
        $size = (Get-Item -LiteralPath $Tarball).Length
        Write-Host ('  tarball : ' + $Tarball + '  (' + $size + ' bytes)')
    } else {
        Write-Host '  tarball : NOT FOUND — run "pnpm pack" in the repository first (see docs/RELEASE.md)'
    }
    Write-Host ('  pnpm    : ' + $(if ($Pnpm) { $Pnpm.path } else { 'NOT ON PATH (install cannot run)' }))
    Write-Host ''
    Write-PlanLine '1/5' ('备份  : copy package.json + cordis.patch.yml -> ' + $BackupDir)
    if ($Tarball) {
        Write-PlanLine '2/5' ('安装  : pnpm add "file:' + $Tarball + '"   (cwd: ' + $Profile + ')')
    } else {
        Write-PlanLine '2/5' '安装  : pnpm add "file:<tgz>"   (skipped until a tarball exists)'
    }
    $before = @($Bundles).Count
    if ($AlreadyInstalled) {
        Write-PlanLine '3/5' ('注册  : dsh.profile.bundles already lists ' + $PackageName + ' (' + $before + ' entries) — no change')
    } else {
        Write-PlanLine '3/5' ('注册  : dsh.profile.bundles ' + $before + ' -> ' + ($before + 1) + ' entries (append ' + $PackageName + '; every existing entry is preserved)')
    }
    Write-PlanLine '4/5' '校验  : re-read package.json, confirm all previous bundles are still there and the JSON parses'
    Write-PlanLine '5/5' '重启  : 需重启 DSH 生效（本脚本不会重启 DSH，也不会停止任何 DSH 进程）'
    Write-Host ''
    if ($WhatIf) {
        Write-Host '  -WhatIf: plan only, nothing was written (no backup, no pnpm call, package.json untouched).'
    }
    Write-Host '  需重启 DSH 生效'
    Write-Host ''
}

function Invoke-Install {
    param([string]$Profile, [string]$Tarball, [object]$Pnpm, [string]$BackupDir)

    $pkgPath = Join-Path $Profile 'package.json'
    $patchPath = Join-Path $Profile 'cordis.patch.yml'
    foreach ($required in @($pkgPath, $patchPath)) {
        if (-not (Test-Path -LiteralPath $required)) { throw "required profile file missing: $required" }
    }
    $original = Read-PackageJson $pkgPath
    $bundleInfo = Get-BundleList $original
    $originalBundles = @($bundleInfo.list)
    if ($originalBundles.Count -eq 0) { throw 'profile package.json has no dsh.profile.bundles array; refusing to guess' }

    # ---- 1. backup -------------------------------------------------------------
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    foreach ($name in @('package.json', 'cordis.patch.yml')) {
        Copy-Item -LiteralPath (Join-Path $Profile $name) -Destination (Join-Path $BackupDir $name) -Force
    }
    $manifest = [ordered]@{
        createdAt = (Get-Date).ToString('o')
        tool      = 'dsh-screenshot install.ps1'
        profile   = $Profile
        tarball   = $Tarball
        package   = $PackageName
        bundlesBefore = $originalBundles
        files     = @('package.json', 'cordis.patch.yml')
    }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $BackupDir 'manifest.json') -Encoding utf8NoBOM
    Write-Host ('备份完成: ' + $BackupDir)
    foreach ($name in @('package.json', 'cordis.patch.yml')) {
        $bytes = (Get-Item -LiteralPath (Join-Path $BackupDir $name)).Length
        Write-Host ('  backed up ' + $name + ' (' + $bytes + ' bytes)')
    }

    # ---- 2. pnpm add -----------------------------------------------------------
    $spec = 'file:' + $Tarball
    Write-Host ('安装中: pnpm add "' + $spec + '"')
    $logPath = Join-Path $BackupDir 'pnpm-add.log'
    $pnpm = Invoke-PnpmAdd -Pnpm $Pnpm -Spec $spec -WorkingDirectory $Profile -TimeoutSec $PnpmTimeoutSec -LogPath $logPath
    if ($pnpm.timedOut -or $pnpm.exitCode -ne 0) {
        Write-Host ''
        Write-Host ('pnpm add failed (exit ' + $pnpm.exitCode + ', timedOut=' + $pnpm.timedOut + '). Log: ' + $logPath)
        $tail = @(($pnpm.stdout + $script:NL + $pnpm.stderr) -split "[\r\n]+" | Where-Object { $_.Trim().Length -gt 0 } | Select-Object -Last 8)
        foreach ($line in $tail) { Write-Host ('  ' + $line) }
        foreach ($name in @('package.json', 'cordis.patch.yml')) {
            Copy-Item -LiteralPath (Join-Path $BackupDir $name) -Destination (Join-Path $Profile $name) -Force
        }
        Write-Host '已自动还原 package.json 与 cordis.patch.yml（profile 回到安装前状态）'
        exit 1
    }
    Write-Host ('  pnpm add ok (exit 0); log: ' + $logPath)

    # ---- 3. bundles append -----------------------------------------------------
    $current = Read-PackageJson $pkgPath
    $info = Get-BundleList $current
    $currentBundles = @($info.list)
    if ($currentBundles.Count -eq 0) { throw 'post-install package.json lost dsh.profile.bundles; nothing was appended (backup is intact)' }
    if ($currentBundles -contains $PackageName) {
        Write-Host ('注册: dsh.profile.bundles already lists ' + $PackageName + ' (' + $currentBundles.Count + ' entries) — left unchanged')
    } else {
        Add-BundleEntry -Path $pkgPath -Name $PackageName -ExpectedBefore $currentBundles
        $verify = Read-PackageJson $pkgPath
        $final = @((Get-BundleList $verify).list)
        $prefixOk = $true
        for ($i = 0; $i -lt $currentBundles.Count; $i++) {
            if ($final[$i] -ne $currentBundles[$i]) { $prefixOk = $false }
        }
        if (-not $prefixOk -or $final.Count -ne ($currentBundles.Count + 1) -or $final[$final.Count - 1] -ne $PackageName) {
            foreach ($name in @('package.json', 'cordis.patch.yml')) {
                Copy-Item -LiteralPath (Join-Path $BackupDir $name) -Destination (Join-Path $Profile $name) -Force
            }
            Write-Host '注册校验失败，已还原 profile package.json；请把上面的输出发给维护者。'
            exit 1
        }
        Write-Host ('dsh.profile.bundles: ' + $currentBundles.Count + ' -> ' + $final.Count + ' entries (+' + $PackageName + '), all previous entries preserved')
    }

    # ---- 4. final checks -------------------------------------------------------
    if (-not (Test-Path -LiteralPath $patchPath)) { Write-Host 'WARNING: cordis.patch.yml disappeared from the profile' }
    Write-Host ''
    Write-Host ('安装完成: ' + $PackageName)
    Write-Host ('  备份目录: ' + $BackupDir)
    Write-Host ('  回滚命令: pwsh -NoProfile -File ' + (Join-Path $script:RepoRoot 'install.ps1') + ' -Rollback -ProfileDir "' + $Profile + '"')
    Write-Host '  需重启 DSH 生效（本脚本不会重启 DSH，也不会停止任何 DSH 进程）'
    Write-Host ''
}

# ---------------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------------
try {
    $profile = Resolve-Profile -Explicit $ProfileDir
} catch {
    Write-Host ('error: ' + $_.Exception.Message)
    exit 1
}

if ($Rollback) {
    if ($WhatIf) {
        $has = Invoke-RollbackPlan -Profile $profile
        if ($has) { exit 0 } else { exit 0 }
    }
    Invoke-Rollback -Profile $profile
}

$tarball = $null
$tgzError = $null
try { $tarball = Resolve-Tgz -Explicit $Tgz } catch { $tgzError = $_.Exception.Message }

$pnpm = Find-Pnpm
$pkgPath = Join-Path $profile 'package.json'
$patchPath = Join-Path $profile 'cordis.patch.yml'
$alreadyInstalled = $false
$bundles = @()
if (Test-Path -LiteralPath $pkgPath) {
    try {
        $parsed = Read-PackageJson $pkgPath
        $bundles = @((Get-BundleList $parsed).list)
        $alreadyInstalled = ($bundles -contains $PackageName)
    } catch {
        Write-Host ('error: cannot parse ' + $pkgPath + ': ' + $_.Exception.Message)
        exit 1
    }
}
$backupDir = Join-Path $profile ('.backup-install-' + (Get-Stamp))

if ($WhatIf) {
    Show-InstallPlan -Profile $profile -Tarball $tarball -Pnpm $pnpm -AlreadyInstalled $alreadyInstalled -BackupDir $backupDir -Bundles $bundles
    if ($tgzError) { Write-Host ('  warning: ' + $tgzError) }
    if (-not $tarball) { Write-Host '  warning: no .tgz found — packaging is still to do (pnpm pack, see docs/RELEASE.md)' }
    if (-not $pnpm) { Write-Host '  warning: pnpm is not on PATH; the real run would stop at step 2/5' }
    exit 0
}

if ($tgzError) { Write-Host ('error: ' + $tgzError); exit 1 }
if (-not $tarball) {
    Write-Host 'error: no plugin tarball found. Build the package first:'
    Write-Host ('  cd ' + $script:RepoRoot)
    Write-Host '  pnpm pack'
    Write-Host 'then rerun with -Tgz <path> (or see docs/RELEASE.md).'
    exit 1
}
if (-not $pnpm) {
    Write-Host 'error: pnpm is not on PATH; it is required for "pnpm add file:<tgz>".'
    exit 1
}
if (-not (Test-Path -LiteralPath $pkgPath)) { Write-Host ('error: profile package.json not found: ' + $pkgPath); exit 1 }
if (-not (Test-Path -LiteralPath $patchPath)) { Write-Host ('error: profile cordis.patch.yml not found: ' + $patchPath); exit 1 }

if ($alreadyInstalled -and -not $Force) {
    Write-Host ('already installed: ' + $PackageName + ' is listed in dsh.profile.bundles (' + $bundles.Count + ' entries).')
    Write-Host ('  use -Force to reinstall, or -Rollback to undo (backup: ' + (Join-Path $profile '.backup-install-*') + ')')
    Write-Host '  需重启 DSH 生效（本脚本不会重启 DSH）'
    exit 0
}

Show-InstallPlan -Profile $profile -Tarball $tarball -Pnpm $pnpm -AlreadyInstalled $alreadyInstalled -BackupDir $backupDir -Bundles $bundles
Write-Host 'applying the plan above ...'
try {
    Invoke-Install -Profile $profile -Tarball $tarball -Pnpm $pnpm -BackupDir $backupDir
} catch {
    Write-Host ('error: ' + $_.Exception.Message)
    if (Test-Path -LiteralPath $backupDir) {
        foreach ($name in @('package.json', 'cordis.patch.yml')) {
            $b = Join-Path $backupDir $name
            if (Test-Path -LiteralPath $b) { Copy-Item -LiteralPath $b -Destination (Join-Path $profile $name) -Force }
        }
        Write-Host '已尝试还原备份（profile 回到安装前状态）'
    }
    exit 1
}
exit 0
