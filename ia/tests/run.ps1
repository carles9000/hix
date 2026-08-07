# run.ps1
# HIX IA -- declarative test runner.
# Compiles a HIX project, launches its .exe on a free port, iterates every
# *.test.json in the given directory, and reports pass/fail.
#
# ASCII only -- Windows PowerShell 5.1 reads .ps1 as Windows-1252.
#
# Usage:
#   .\run.ps1 -Project <path> -Tests <path> [-Port <n>] [-TimeoutMs <n>]
#             [-SkipBuild] [-KeepRunning] [-Verbose]

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)] [string] $Project,
    [Parameter(Mandatory=$true)] [string] $Tests,

    [int]    $Port      = 0,
    [int]    $TimeoutMs = 15000,
    [string] $BuildScript = 'go.bat',
    [string] $BuildArgs   = 'build',
    [string] $ServeArgs   = 'serve',

    [switch] $SkipBuild,
    [switch] $KeepRunning
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'helpers.ps1')

function Info    ($m) { Write-Host "[run] $m" -ForegroundColor Cyan }
function OK      ($m) { Write-Host "[run] $m" -ForegroundColor Green }
function WarnMsg ($m) { Write-Host "[run] $m" -ForegroundColor Yellow }
function FailMsg ($m) { Write-Host "[run] ERROR: $m" -ForegroundColor Red }

# ---- Validate inputs ---------------------------------------------------------

$Project = (Resolve-Path -LiteralPath $Project).Path
$Tests   = (Resolve-Path -LiteralPath $Tests).Path

if (-not (Test-Path -LiteralPath $Project -PathType Container)) {
    FailMsg "Project path not found: $Project"; exit 2
}
if (-not (Test-Path -LiteralPath $Tests -PathType Container)) {
    FailMsg "Tests path not found: $Tests"; exit 2
}

$testFiles = Get-ChildItem -LiteralPath $Tests -Filter '*.test.json' -File -ErrorAction SilentlyContinue
if (-not $testFiles -or $testFiles.Count -eq 0) {
    WarnMsg "No *.test.json files found in $Tests -- nothing to do."
    exit 0
}

# ---- Build -------------------------------------------------------------------

$buildPath = Join-Path $Project $BuildScript
if (-not (Test-Path -LiteralPath $buildPath -PathType Leaf)) {
    FailMsg "Build script not found: $buildPath"; exit 2
}

if (-not $SkipBuild) {
    Info "Building project via $BuildScript $BuildArgs ..."
    # Redirect via Start-Process to temp files -- avoids the PS 5.1 gotcha
    # where "2>&1" on a native command wraps stderr as ErrorRecord and can
    # corrupt $LASTEXITCODE handling.
    $outLog = [System.IO.Path]::GetTempFileName()
    $errLog = [System.IO.Path]::GetTempFileName()
    $buildProc = Start-Process -FilePath 'cmd.exe' `
                               -ArgumentList @('/c', "`"$buildPath`" $BuildArgs") `
                               -WorkingDirectory $Project `
                               -NoNewWindow `
                               -Wait -PassThru `
                               -RedirectStandardOutput $outLog `
                               -RedirectStandardError  $errLog
    if ($buildProc.ExitCode -ne 0) {
        FailMsg "Build failed (exit $($buildProc.ExitCode))."
        Get-Content -LiteralPath $outLog -ErrorAction SilentlyContinue |
            ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
        Get-Content -LiteralPath $errLog -ErrorAction SilentlyContinue |
            ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        Remove-Item -LiteralPath $outLog, $errLog -Force -ErrorAction SilentlyContinue
        exit 3
    }
    Remove-Item -LiteralPath $outLog, $errLog -Force -ErrorAction SilentlyContinue
} else {
    Info "Skipping build (--SkipBuild)."
}

# ---- Locate exe --------------------------------------------------------------

$exeName = Get-ProjectExeName -ProjectPath $Project
if (-not $exeName) {
    FailMsg "No .exe found in $Project after build."
    exit 3
}
$exePath = Join-Path $Project $exeName
Info "Using executable: $exeName"

# ---- Pick a port and patch hix.json -----------------------------------------

if ($Port -le 0) {
    $Port = Find-FreePort
}
Info "Using port: $Port"

$originalHixJson = Set-HixJsonPort -ProjectPath $Project -Port $Port
$baseUrl = "http://127.0.0.1:$Port"

# ---- Run --------------------------------------------------------------------

$proc = $null
$pass = 0
$fail = 0
$results = @()

try {
    # Launch via the project's build script in "serve" mode so the child
    # process inherits the same env (PATH, hix, hbdir) used at compile time.
    # Direct app.exe launch fails when the exe depends on DLLs from %hix%
    # or %hbdir% (libcrypto, libssl, libcurl).
    Info "Starting $BuildScript $ServeArgs on $baseUrl ..."
    $proc = Start-Process -FilePath 'cmd.exe' `
                          -ArgumentList @('/c', "`"$buildPath`" $ServeArgs") `
                          -WorkingDirectory $Project `
                          -WindowStyle Hidden `
                          -PassThru

    if (-not (Wait-ForHttp -Url "$baseUrl/" -TimeoutMs $TimeoutMs)) {
        FailMsg "Server did not respond on $baseUrl within $TimeoutMs ms."
        exit 4
    }
    OK "Server is up."

    foreach ($file in $testFiles) {
        $testName = $file.Name
        $rawJson  = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
        try {
            $t = $rawJson | ConvertFrom-Json
        } catch {
            FailMsg "$testName -- invalid JSON: $($_.Exception.Message)"
            $fail++
            $results += [pscustomobject]@{ Name=$testName; Pass=$false; Reason='invalid JSON' }
            continue
        }

        $method  = $t.request.method
        $path    = $t.request.path
        $headers = @{}
        if ($t.request.headers) {
            $t.request.headers.PSObject.Properties | ForEach-Object {
                $headers[$_.Name] = [string]$_.Value
            }
        }
        $body = $null
        if ($t.request.PSObject.Properties.Match('body').Count -gt 0 -and $t.request.body -ne $null) {
            $body = [string]$t.request.body
        }

        $url = "$baseUrl$path"
        $resp = $null
        $respStatus = 0
        $respCT = ''
        $respBody = ''

        # Use HttpWebRequest directly so we get full control over redirect handling
        # (Invoke-WebRequest in PS 5.1 auto-follows 3xx unless MaximumRedirection=0,
        # and that path throws InvalidOperationException instead of surfacing the response).
        try {
            $req = [System.Net.HttpWebRequest]::Create($url)
            $req.Method            = $method
            $req.AllowAutoRedirect = $false
            $req.Timeout           = 10000
            $req.UserAgent         = 'hix-ia-runner/1.0'
            foreach ($k in $headers.Keys) {
                $lk = $k.ToLowerInvariant()
                if ($lk -eq 'content-type') {
                    $req.ContentType = [string]$headers[$k]
                } elseif ($lk -eq 'accept') {
                    $req.Accept = [string]$headers[$k]
                } else {
                    $req.Headers.Add($k, [string]$headers[$k])
                }
            }
            if ($body -ne $null) {
                $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$body)
                $req.ContentLength = $bytes.Length
                $rs = $req.GetRequestStream()
                $rs.Write($bytes, 0, $bytes.Length)
                $rs.Close()
            }

            try {
                $resp = $req.GetResponse()
            } catch [System.Net.WebException] {
                $resp = $_.Exception.Response
                if ($resp -eq $null) { throw }
            }

            $respStatus = [int]$resp.StatusCode
            $respCT     = [string]$resp.ContentType
            try {
                $stream = $resp.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream)
                $respBody = $reader.ReadToEnd()
                $reader.Close()
            } catch { $respBody = '' }
            $resp.Close()
        } catch {
            FailMsg "$testName -- request error: $($_.Exception.Message)"
            $fail++
            $results += [pscustomobject]@{ Name=$testName; Pass=$false; Reason=$_.Exception.Message }
            continue
        }

        # ---- Assertions ------------------------------------------------------
        $expected = $t.expect
        $problems = @()

        $wantStatus = 200
        if ($expected -and $expected.PSObject.Properties.Match('status').Count -gt 0) {
            $wantStatus = [int]$expected.status
        }
        if ($respStatus -ne $wantStatus) {
            $problems += "status: got $respStatus, want $wantStatus"
        }

        if ($expected -and $expected.content_type_contains) {
            $needle = [string]$expected.content_type_contains
            if ($respCT -notlike "*$needle*") {
                $problems += "content-type: '$respCT' does not contain '$needle'"
            }
        }

        if ($expected -and $expected.body_contains) {
            foreach ($needle in $expected.body_contains) {
                $s = [string]$needle
                if ($respBody -notlike "*$s*") {
                    $problems += "body_contains: missing '$s'"
                }
            }
        }

        if ($expected -and $expected.body_matches) {
            $rx = [string]$expected.body_matches
            if ($respBody -notmatch $rx) {
                $problems += "body_matches: regex did not match /$rx/"
            }
        }

        if ($problems.Count -eq 0) {
            OK "PASS -- $($t.name) [$testName]"
            $pass++
            $results += [pscustomobject]@{ Name=$testName; Pass=$true; Reason='' }
        } else {
            FailMsg "FAIL -- $($t.name) [$testName]"
            foreach ($p in $problems) {
                Write-Host "        $p" -ForegroundColor Red
            }
            $fail++
            $results += [pscustomobject]@{ Name=$testName; Pass=$false; Reason=($problems -join '; ') }
        }
    }
} finally {
    if (-not $KeepRunning) {
        Info "Stopping server ..."
        $procId = if ($proc) { $proc.Id } else { 0 }
        Stop-ProjectExe -ProcessId $procId -ExeName $exeName
    } else {
        WarnMsg "Leaving server running (--KeepRunning). PID = $($proc.Id)."
    }
    Restore-HixJson -ProjectPath $Project -OriginalContent $originalHixJson
}

# ---- Report -----------------------------------------------------------------

$total = $pass + $fail
Write-Host ''
Write-Host "======================================================================"
Write-Host " HIX IA -- Test summary"
Write-Host "======================================================================"
Write-Host (" Total : {0}" -f $total)
Write-Host (" Pass  : {0}" -f $pass) -ForegroundColor Green
Write-Host (" Fail  : {0}" -f $fail) -ForegroundColor $([console]::ForegroundColor)
Write-Host "======================================================================"

if ($fail -gt 0) {
    Write-Host ''
    Write-Host 'Failures:' -ForegroundColor Red
    $results | Where-Object { -not $_.Pass } | ForEach-Object {
        Write-Host ("  - {0} :: {1}" -f $_.Name, $_.Reason) -ForegroundColor Red
    }
}

exit $fail
