<#
.SYNOPSIS
    Uninstall HIX AI System from a Claude Code environment.

.DESCRIPTION
    Removes:
      1. All hix-* symlinks/copies under ~\.claude\{skills,agents,commands}\
      2. The HIX AI import block from the target project's CLAUDE.md
         (if the file becomes empty afterwards it is deleted).

.PARAMETER Target
    Absolute path to the project whose CLAUDE.md should be cleaned.

.EXAMPLE
    .\uninstall.ps1 -Target C:\MyProject
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Target
)

$ErrorActionPreference = 'Stop'

$Target = (Resolve-Path $Target -ErrorAction SilentlyContinue).Path
if (-not $Target) { throw "Target path does not exist." }

$UserClaude = Join-Path $env:USERPROFILE '.claude'

Write-Host ""
Write-Host "HIX AI System -- Uninstall" -ForegroundColor Cyan
Write-Host "  Target : $Target"
Write-Host ""

# --- Remove hix-* assets from ~\.claude\ ------------------------------------

foreach ($kind in @('skills', 'agents', 'commands')) {
    $dir = Join-Path $UserClaude $kind
    if (-not (Test-Path $dir)) { continue }

    Get-ChildItem -Path $dir -Force | Where-Object {
        $_.Name -like 'hix-*' -or $_.Name -like 'hix.*'
    } | ForEach-Object {
        Remove-Item -Recurse -Force $_.FullName
        Write-Host "  [$kind] REMOVED -- $($_.Name)" -ForegroundColor Yellow
    }
}

# --- Clean CLAUDE.md ---------------------------------------------------------

$ProjectClaude = Join-Path $Target 'CLAUDE.md'
if (Test-Path $ProjectClaude) {
    $lines = Get-Content $ProjectClaude
    $filtered = @()
    $skip = $false
    foreach ($line in $lines) {
        if ($line -like '*# HIX AI System -- auto-imported*') { $skip = $true; continue }
        if ($skip -and $line -like '@*hix*ia*claude*CLAUDE.md*') { $skip = $false; continue }
        if ($skip -and $line.Trim() -eq '') { continue }
        $skip = $false
        $filtered += $line
    }
    $cleaned = ($filtered -join "`r`n").Trim()
    if ([string]::IsNullOrWhiteSpace($cleaned)) {
        Remove-Item -Force $ProjectClaude
        Write-Host "  [CLAUDE.md] DELETED (was empty after cleanup)" -ForegroundColor Yellow
    } else {
        Set-Content -Path $ProjectClaude -Value $cleaned -Encoding UTF8
        Write-Host "  [CLAUDE.md] CLEANED (kept user content)" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Uninstall complete." -ForegroundColor Cyan
Write-Host ""
