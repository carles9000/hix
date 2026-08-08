<#
.SYNOPSIS
    Install HIX AI System into a Claude Code environment.

.DESCRIPTION
    Wires the HIX AI System assets (skills, agents, commands, CLAUDE.md) into:
      1. The user's Claude Code home directory (~\.claude\) via symlinks -- so
         every project sees the hix-* skills automatically.
      2. The target project's CLAUDE.md, appending an @import to the HIX AI
         CLAUDE.md so the framework rules load at session start.

    Assets live in this repo (referenced, not copied). A `git pull` in
    C:\HIX.PROJECT\hix\ updates every installed project instantly.

.PARAMETER Target
    Absolute path to the project where CLAUDE.md should be created/updated.

.PARAMETER SourceRoot
    Root of the HIX AI System. Defaults to the parent of this script's parent
    (i.e. C:\HIX.PROJECT\hix\ia when script lives at hix\ia\scripts\).

.PARAMETER ForceCopy
    Skip symlinks and copy files instead. Use when Developer Mode is off and
    the user cannot run as admin.

.EXAMPLE
    .\install.ps1 -Target C:\MyProject

.EXAMPLE
    .\install.ps1 -Target C:\MyProject -ForceCopy
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Target,

    [Parameter(Mandatory = $false)]
    [string] $SourceRoot,

    [Parameter(Mandatory = $false)]
    [switch] $ForceCopy
)

$ErrorActionPreference = 'Stop'

# --- Resolve paths -----------------------------------------------------------

if (-not $SourceRoot) {
    $SourceRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
}

$SourceRoot = (Resolve-Path $SourceRoot).Path
$Target     = (Resolve-Path $Target -ErrorAction SilentlyContinue).Path
if (-not $Target) {
    throw "Target path does not exist. Create the project directory first."
}

$ClaudeSrc = Join-Path $SourceRoot 'claude'
if (-not (Test-Path $ClaudeSrc)) {
    throw "Source claude/ directory not found at $ClaudeSrc"
}

$UserClaude = Join-Path $env:USERPROFILE '.claude'
foreach ($sub in @('skills', 'agents', 'commands')) {
    $p = Join-Path $UserClaude $sub
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}

Write-Host ""
Write-Host "HIX AI System -- Install" -ForegroundColor Cyan
Write-Host "  Source : $SourceRoot"
Write-Host "  Target : $Target"
Write-Host "  Home   : $UserClaude"
Write-Host ""

# --- Detect symlink capability -----------------------------------------------

function Test-CanSymlink {
    $probeSrc = Join-Path $env:TEMP ("hixia_probe_src_" + [Guid]::NewGuid())
    $probeLnk = Join-Path $env:TEMP ("hixia_probe_lnk_" + [Guid]::NewGuid())
    New-Item -ItemType Directory -Path $probeSrc -Force | Out-Null
    try {
        New-Item -ItemType SymbolicLink -Path $probeLnk -Target $probeSrc -ErrorAction Stop | Out-Null
        Remove-Item -Force $probeLnk
        return $true
    } catch {
        return $false
    } finally {
        Remove-Item -Recurse -Force $probeSrc -ErrorAction SilentlyContinue
    }
}

$UseSymlinks = -not $ForceCopy -and (Test-CanSymlink)

if ($UseSymlinks) {
    Write-Host "  Mode   : symlinks (Developer Mode or admin detected)" -ForegroundColor Green
} else {
    Write-Host "  Mode   : file copy (no symlink capability; git pull WILL NOT auto-update)" -ForegroundColor Yellow
}
Write-Host ""

# --- Link/copy skills, agents, commands --------------------------------------

function Install-Asset {
    param(
        [string] $Kind,       # 'skills' | 'agents' | 'commands'
        [string] $SourceDir,  # source folder inside claude/
        [string] $HomeDir     # ~\.claude\<kind>
    )

    if (-not (Test-Path $SourceDir)) { return }

    Get-ChildItem -Path $SourceDir -Force | ForEach-Object {
        $item     = $_
        $linkPath = Join-Path $HomeDir $item.Name

        # Only touch hix-* to avoid clobbering the user's own assets
        if ($item.Name -notlike 'hix-*' -and $item.Name -notlike 'hix.*') {
            Write-Host "  [$Kind] SKIP (not hix-*) -- $($item.Name)" -ForegroundColor DarkGray
            return
        }

        if (Test-Path $linkPath) {
            Write-Host "  [$Kind] REPLACE -- $($item.Name)" -ForegroundColor Yellow
            Remove-Item -Recurse -Force $linkPath
        }

        if ($UseSymlinks) {
            New-Item -ItemType SymbolicLink -Path $linkPath -Target $item.FullName | Out-Null
            Write-Host "  [$Kind] LINK    -- $($item.Name)" -ForegroundColor Green
        } else {
            Copy-Item -Recurse -Force $item.FullName $linkPath
            Write-Host "  [$Kind] COPY    -- $($item.Name)" -ForegroundColor Green
        }
    }
}

Install-Asset -Kind 'skills'   -SourceDir (Join-Path $ClaudeSrc 'skills')   -HomeDir (Join-Path $UserClaude 'skills')
Install-Asset -Kind 'agents'   -SourceDir (Join-Path $ClaudeSrc 'agents')   -HomeDir (Join-Path $UserClaude 'agents')
Install-Asset -Kind 'commands' -SourceDir (Join-Path $ClaudeSrc 'commands') -HomeDir (Join-Path $UserClaude 'commands')

# --- Wire CLAUDE.md in target project ----------------------------------------

$ProjectClaude = Join-Path $Target 'CLAUDE.md'
$ImportLine    = "@$(Join-Path $ClaudeSrc 'CLAUDE.md')"
$Marker        = '# HIX AI System -- auto-imported'

if (Test-Path $ProjectClaude) {
    $existing = Get-Content $ProjectClaude -Raw
    if ($existing -like "*$ImportLine*") {
        Write-Host ""
        Write-Host "  [CLAUDE.md] Already imports HIX AI -- nothing to do." -ForegroundColor DarkGray
    } else {
        $append = "`r`n`r`n$Marker`r`n$ImportLine`r`n"
        Add-Content -Path $ProjectClaude -Value $append -Encoding UTF8
        Write-Host ""
        Write-Host "  [CLAUDE.md] APPENDED import to existing file." -ForegroundColor Green
    }
} else {
    $header = @"
# $(Split-Path -Leaf $Target)

$Marker
$ImportLine
"@
    Set-Content -Path $ProjectClaude -Value $header -Encoding UTF8
    Write-Host ""
    Write-Host "  [CLAUDE.md] CREATED at $ProjectClaude" -ForegroundColor Green
}

# --- Wire project-local permissions (no per-command prompts) ----------------

$ProjectClaudeDir = Join-Path $Target '.claude'
$SettingsPath     = Join-Path $ProjectClaudeDir 'settings.local.json'

$RequiredAllows = @(
    'Bash(powershell.exe *)',
    'Bash(powershell *)',
    'PowerShell(*)',
    'Bash(curl *)',
    'Bash(curl.exe *)'
)

if (-not (Test-Path $ProjectClaudeDir)) {
    New-Item -ItemType Directory -Path $ProjectClaudeDir -Force | Out-Null
}

$settings = $null
if (Test-Path $SettingsPath) {
    try {
        $settings = Get-Content -Raw -Encoding UTF8 $SettingsPath | ConvertFrom-Json
    } catch {
        Write-Host ""
        Write-Host "  [settings] Existing settings.local.json is not valid JSON. Leaving untouched." -ForegroundColor Yellow
        $settings = $null
    }
}

if ($null -eq $settings) {
    $settings = [pscustomobject]@{ permissions = [pscustomobject]@{ allow = @() } }
}
if (-not $settings.PSObject.Properties.Match('permissions').Count) {
    $settings | Add-Member -MemberType NoteProperty -Name permissions -Value ([pscustomobject]@{ allow = @() })
}
if (-not $settings.permissions.PSObject.Properties.Match('allow').Count) {
    $settings.permissions | Add-Member -MemberType NoteProperty -Name allow -Value @()
}

$existing = @($settings.permissions.allow)
$added    = @()
foreach ($rule in $RequiredAllows) {
    if ($existing -notcontains $rule) {
        $existing += $rule
        $added    += $rule
    }
}
$settings.permissions.allow = $existing

$json = $settings | ConvertTo-Json -Depth 20
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($SettingsPath, $json, $utf8NoBom)

Write-Host ""
if ($added.Count -gt 0) {
    Write-Host "  [settings] Added $($added.Count) permission entries to:" -ForegroundColor Green
    Write-Host "             $SettingsPath"
    foreach ($a in $added) { Write-Host "             + $a" -ForegroundColor DarkGray }
} else {
    Write-Host "  [settings] All permission entries already present in $SettingsPath" -ForegroundColor DarkGray
}

# --- Done --------------------------------------------------------------------

Write-Host ""
Write-Host "Install complete." -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  cd $Target"
Write-Host "  claude"
Write-Host "  > /hix-init MyApp        # bootstrap a HIX web app under www/"
Write-Host ""
