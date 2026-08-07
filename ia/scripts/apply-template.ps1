# apply-template.ps1
# Copy a HIX template into a target directory, replacing {{TOKEN}} placeholders
# in file contents AND path segments.
#
# ASCII only -- Windows PowerShell 5.1 reads .ps1 as Windows-1252.

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Template,

    [Parameter(Mandatory=$true)]
    [string]$Target,

    [string]$Name = '',

    [string]$Entity = '',

    [string]$RouteName = '',

    [string]$RouteUrl = '',

    [string]$RouteMethod = 'GET',

    [string]$MiddlewareName = '',

    [string]$ProbeUrl = '',

    [string]$Author = '',

    [string]$HixPath = '',

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Info    ($msg) { Write-Host "[apply-template] $msg" -ForegroundColor Cyan }
function Warn    ($msg) { Write-Host "[apply-template] $msg" -ForegroundColor Yellow }
function Fail    ($msg) { Write-Host "[apply-template] ERROR: $msg" -ForegroundColor Red; exit 1 }
function Success ($msg) { Write-Host "[apply-template] $msg" -ForegroundColor Green }

# ---- Locate template ---------------------------------------------------------

$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$iaRoot      = Split-Path -Parent $scriptDir
$templateDir = Join-Path $iaRoot "templates\$Template"

if (-not (Test-Path $templateDir)) {
    Fail "Template not found: $templateDir"
}
Info "Template: $templateDir"

# ---- Prepare target ----------------------------------------------------------

$Target = [System.IO.Path]::GetFullPath($Target)

# Kind: 'project' if template starts with 'project-', 'module' if 'module-'
if ($Template -like 'project-*') { $kind = 'project' }
elseif ($Template -like 'module-*') { $kind = 'module' }
else { $kind = 'other' }

if (Test-Path $Target) {
    # Only project templates require an empty target -- modules are meant
    # to overlay onto an existing project's www/.
    if ($kind -eq 'project') {
        $entries = Get-ChildItem -Force $Target -ErrorAction SilentlyContinue
        if ($entries -and -not $Force) {
            Fail "Target exists and is not empty: $Target (use -Force to overwrite)"
        }
    }
} else {
    New-Item -ItemType Directory -Path $Target | Out-Null
}
Info "Target: $Target"

# ---- Compute tokens ----------------------------------------------------------

$tokens = @{}

# Common
$tokens['{{DATE}}'] = (Get-Date -Format 'yyyy-MM-dd')
$tokens['{{YEAR}}'] = (Get-Date -Format 'yyyy')

if ([string]::IsNullOrEmpty($Author)) {
    try {
        $gitAuthor = git config user.name 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($gitAuthor)) {
            $Author = $gitAuthor.Trim()
        }
    } catch { }
    if ([string]::IsNullOrEmpty($Author)) { $Author = 'Developer' }
}
$tokens['{{AUTHOR}}'] = $Author

if ($kind -eq 'project') {
    if ([string]::IsNullOrWhiteSpace($Name)) {
        Fail "-Name is required for project templates"
    }
    $tokens['{{PROJECT_NAME}}']       = $Name
    $tokens['{{PROJECT_NAME_LOWER}}'] = $Name.ToLower()

    if ([string]::IsNullOrEmpty($HixPath)) {
        if ($env:HIX_PATH) { $HixPath = $env:HIX_PATH }
        else { $HixPath = 'c:\HIX.PROJECT\hix.pro' }
    }
    $tokens['{{HIX_PATH}}'] = $HixPath
}

if ($kind -eq 'module') {
    # Dispatch per module variant. Each variant declares its required
    # arg + which tokens it computes. Only one variant is expected per
    # invocation, but populating unused ones with placeholders is
    # harmless because the template files won't reference them.
    switch -Wildcard ($Template) {
        'module-crud' {
            if ([string]::IsNullOrWhiteSpace($Entity)) {
                Fail "-Entity is required for template 'module-crud'"
            }
            $tokens['{{ENTITY}}']              = $Entity
            $tokens['{{ENTITY_LOWER}}']        = $Entity.ToLower()
            $plural = $Entity.ToLower()
            if ($plural -notmatch 's$') { $plural = $plural + 's' }
            $tokens['{{ENTITY_PLURAL_LOWER}}'] = $plural
            break
        }
        'module-route' {
            if ([string]::IsNullOrWhiteSpace($RouteName)) {
                Fail "-RouteName is required for template 'module-route'"
            }
            if ([string]::IsNullOrWhiteSpace($RouteUrl)) {
                Fail "-RouteUrl is required for template 'module-route'"
            }
            if (-not ($RouteUrl.StartsWith('/'))) {
                Fail "-RouteUrl must start with '/': got '$RouteUrl'"
            }
            $allowed = @('GET','POST','PUT','DELETE','PATCH')
            $m = $RouteMethod.ToUpper()
            if ($allowed -notcontains $m) {
                Fail "-RouteMethod must be one of GET|POST|PUT|DELETE|PATCH: got '$RouteMethod'"
            }
            $tokens['{{ROUTE_NAME}}']       = $RouteName
            $tokens['{{ROUTE_NAME_LOWER}}'] = $RouteName.ToLower()
            $tokens['{{ROUTE_URL}}']        = $RouteUrl
            $tokens['{{ROUTE_METHOD}}']     = $m
            break
        }
        'module-middleware' {
            if ([string]::IsNullOrWhiteSpace($MiddlewareName)) {
                Fail "-MiddlewareName is required for template 'module-middleware'"
            }
            $mwLower = $MiddlewareName.ToLower()
            if ([string]::IsNullOrWhiteSpace($ProbeUrl)) {
                $ProbeUrl = "/__mw_probe_$mwLower"
            }
            if (-not ($ProbeUrl.StartsWith('/'))) {
                Fail "-ProbeUrl must start with '/': got '$ProbeUrl'"
            }
            $tokens['{{MIDDLEWARE_NAME}}']       = $MiddlewareName
            $tokens['{{MIDDLEWARE_NAME_LOWER}}'] = $mwLower
            $tokens['{{PROBE_URL}}']             = $ProbeUrl
            break
        }
        default {
            Fail "Unknown module template: '$Template'. Known: module-crud, module-route, module-middleware."
        }
    }
}

Info "Tokens:"
foreach ($k in $tokens.Keys | Sort-Object) {
    Info "  $k = $($tokens[$k])"
}

# ---- Replace helper ----------------------------------------------------------

function Replace-Tokens {
    param([string]$text)
    foreach ($k in $tokens.Keys) {
        $text = $text.Replace($k, $tokens[$k])
    }
    return $text
}

# ---- Walk template -----------------------------------------------------------

$files = Get-ChildItem -Recurse -File $templateDir
$count = 0
$skipped = 0

foreach ($file in $files) {
    $relative = $file.FullName.Substring($templateDir.Length).TrimStart('\','/')

    # Skip .gitkeep sentinels (only needed to preserve empty dirs in git)
    if ((Split-Path -Leaf $relative) -eq '.gitkeep') {
        $skipped++
        continue
    }

    # For module templates, the top-level README.md documents the template
    # itself and must not be copied into the target project's www/.
    if ($kind -eq 'module' -and $relative -eq 'README.md') {
        $skipped++
        continue
    }

    # Rewrite path segments (support tokens in file/dir names)
    $newRelative = Replace-Tokens $relative
    $destPath    = Join-Path $Target $newRelative
    $destDir     = Split-Path -Parent $destPath

    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    # Read + replace + write (UTF-8, no BOM)
    $content    = Get-Content -Raw -LiteralPath $file.FullName -Encoding UTF8
    $newContent = Replace-Tokens $content

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($destPath, $newContent, $utf8NoBom)

    Info "  wrote $newRelative"
    $count++
}

# ---- Done --------------------------------------------------------------------

Success "Applied template '$Template' to $Target"
Success "Files written: $count (skipped .gitkeep: $skipped)"

if ($kind -eq 'project') {
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  cd $Target"
    Write-Host "  .\go.bat"
    Write-Host ""
}
if ($kind -eq 'module') {
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  The module files are in $Target"
    Write-Host "  Merge them into your project's www/ tree, then rebuild."
    Write-Host ""
}

exit 0
