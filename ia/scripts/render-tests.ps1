# render-tests.ps1
# Copy *.test.json files from a source folder to a target folder, substituting
# {{ENTITY}} / {{ENTITY_LOWER}} / {{ENTITY_PLURAL_LOWER}} tokens in the JSON body
# AND in the file name.
#
# Used by skills that ship parametric test templates (hix-add-crud, etc.).
#
# ASCII only -- Windows PowerShell 5.1 reads .ps1 as Windows-1252.

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Source,

    [Parameter(Mandatory=$true)]
    [string]$Target,

    [string]$Entity = '',

    [string]$RouteName = '',

    [string]$RouteUrl = '',

    [string]$RouteMethod = 'GET',

    [string]$MiddlewareName = '',

    [string]$ProbeUrl = '',

    [string]$ScreenName = '',

    [string]$ScreenUrl = '',

    [string]$ScreenTitle = '',

    [string]$Prefix = '',

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Info    ($msg) { Write-Host "[render-tests] $msg" -ForegroundColor Cyan }
function Fail    ($msg) { Write-Host "[render-tests] ERROR: $msg" -ForegroundColor Red; exit 1 }
function Success ($msg) { Write-Host "[render-tests] $msg" -ForegroundColor Green }

if (-not (Test-Path $Source)) {
    Fail "Source folder not found: $Source"
}

if (-not (Test-Path $Target)) {
    New-Item -ItemType Directory -Path $Target | Out-Null
}

# ---- Tokens ------------------------------------------------------------------
#
# Populate whichever token set the caller provided. Each skill uses one
# variant. Missing args stay unset so an unrelated template that doesn't
# reference them still renders cleanly.

$tokens = @{}

if (-not [string]::IsNullOrWhiteSpace($Entity)) {
    $tokens['{{ENTITY}}']       = $Entity
    $tokens['{{ENTITY_LOWER}}'] = $Entity.ToLower()
    $plural = $Entity.ToLower()
    if ($plural -notmatch 's$') { $plural = $plural + 's' }
    $tokens['{{ENTITY_PLURAL_LOWER}}'] = $plural
}

if (-not [string]::IsNullOrWhiteSpace($RouteName)) {
    $tokens['{{ROUTE_NAME}}']       = $RouteName
    $tokens['{{ROUTE_NAME_LOWER}}'] = $RouteName.ToLower()
    $tokens['{{ROUTE_URL}}']        = $RouteUrl
    $tokens['{{ROUTE_METHOD}}']     = $RouteMethod.ToUpper()
}

if (-not [string]::IsNullOrWhiteSpace($MiddlewareName)) {
    $mwLower = $MiddlewareName.ToLower()
    if ([string]::IsNullOrWhiteSpace($ProbeUrl)) {
        $ProbeUrl = "/__mw_probe_$mwLower"
    }
    $tokens['{{MIDDLEWARE_NAME}}']       = $MiddlewareName
    $tokens['{{MIDDLEWARE_NAME_LOWER}}'] = $mwLower
    $tokens['{{PROBE_URL}}']             = $ProbeUrl
}

if (-not [string]::IsNullOrWhiteSpace($ScreenName)) {
    if ([string]::IsNullOrWhiteSpace($ScreenTitle)) {
        $ScreenTitle = $ScreenName
    }
    $tokens['{{SCREEN_NAME}}']       = $ScreenName
    $tokens['{{SCREEN_NAME_LOWER}}'] = $ScreenName.ToLower()
    $tokens['{{SCREEN_URL}}']        = $ScreenUrl
    $tokens['{{SCREEN_TITLE}}']      = $ScreenTitle
}

if ($tokens.Count -eq 0) {
    Fail "No token args supplied. Pass -Entity or -RouteName or -MiddlewareName or -ScreenName."
}

Info "Source: $Source"
Info "Target: $Target"
foreach ($k in $tokens.Keys | Sort-Object) {
    Info "  $k = $($tokens[$k])"
}
if ($Prefix) { Info "Prefix: $Prefix" }

function Replace-Tokens {
    param([string]$text)
    foreach ($k in $tokens.Keys) {
        $text = $text.Replace($k, $tokens[$k])
    }
    return $text
}

# ---- Copy + replace ----------------------------------------------------------

$files = Get-ChildItem -File $Source -Filter '*.test.json'
if (-not $files) {
    Fail "No *.test.json files found in $Source"
}

$count = 0
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

foreach ($file in $files) {
    # Rewrite tokens in file name (and prepend $Prefix if given)
    $newName = Replace-Tokens $file.Name
    if ($Prefix) { $newName = $Prefix + $newName }

    $destPath = Join-Path $Target $newName

    if ((Test-Path $destPath) -and -not $Force) {
        Fail "Destination exists: $destPath (use -Force to overwrite)"
    }

    $content    = Get-Content -Raw -LiteralPath $file.FullName -Encoding UTF8
    $newContent = Replace-Tokens $content

    [System.IO.File]::WriteAllText($destPath, $newContent, $utf8NoBom)

    Info "  wrote $newName"
    $count++
}

Success "Rendered $count test file(s) to $Target"

exit 0
