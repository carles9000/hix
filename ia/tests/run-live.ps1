# run-live.ps1
# HIX IA -- declarative test runner for a *binary-first* HIX distribution.
# Reads the port from <root>\hix.json (regex, not ConvertFrom-Json -- hix.json
# ships with /* ... */ comments that break the JSON parser). If hix.exe is not
# already listening, starts it. Iterates every *.test.json in the given
# directory and reports pass/fail. NO build phase -- HIX hot-reloads .prg on
# each request.
#
# ASCII only -- Windows PowerShell 5.1 reads .ps1 as Windows-1252.
#
# Usage:
#   .\run-live.ps1 -Root <hix_root> -Tests <path>
#                  [-TimeoutMs <n>] [-Restart] [-KeepRunning]
#
# When to pass -Restart:
#   - After adding/removing a www/routes/*.json file
#   - After adding/removing a www/loaders/*.prg file
#   - After editing hix.json
#   Controllers, models and views hot-reload -- restart NOT needed.

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)] [string] $Root,
    [Parameter(Mandatory=$true)] [string] $Tests,

    [int]    $TimeoutMs   = 15000,
    [string] $ExeName     = 'hix.exe',

    [switch] $Restart,
    [switch] $KeepRunning
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'helpers.ps1')

function Info    ($m) { Write-Host "[run-live] $m" -ForegroundColor Cyan }
function OK      ($m) { Write-Host "[run-live] $m" -ForegroundColor Green }
function WarnMsg ($m) { Write-Host "[run-live] $m" -ForegroundColor Yellow }
function FailMsg ($m) { Write-Host "[run-live] ERROR: $m" -ForegroundColor Red }

# ---- Validate inputs ---------------------------------------------------------

$Root  = (Resolve-Path -LiteralPath $Root ).Path
$Tests = (Resolve-Path -LiteralPath $Tests).Path

if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    FailMsg "Root path not found: $Root"; exit 2
}
$exePath = Join-Path $Root $ExeName
if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
    FailMsg "$ExeName not found in $Root -- is this a HIX distribution?"; exit 2
}
$hixJson = Join-Path $Root 'hix.json'
if (-not (Test-Path -LiteralPath $hixJson -PathType Leaf)) {
    FailMsg "hix.json not found in $Root -- run /hix-init first."; exit 2
}
if (-not (Test-Path -LiteralPath $Tests -PathType Container)) {
    FailMsg "Tests path not found: $Tests"; exit 2
}

$testFiles = Get-ChildItem -LiteralPath $Tests -Filter '*.test.json' -File -ErrorAction SilentlyContinue
if (-not $testFiles -or $testFiles.Count -eq 0) {
    WarnMsg "No *.test.json files found in $Tests -- nothing to do."
    exit 0
}

# ---- Read port from hix.json (regex -- comments allowed) --------------------

$json = Get-Content -LiteralPath $hixJson -Raw -Encoding UTF8
$m = [regex]::Match($json, '"port"\s*:\s*(\d+)')
if (-not $m.Success) {
    FailMsg "Could not find server.port in $hixJson"; exit 2
}
$Port = [int]$m.Groups[1].Value
$baseUrl = "http://127.0.0.1:$Port"
Info "HIX root : $Root"
Info "Port     : $Port"
Info "Base URL : $baseUrl"

# ---- Check if hix.exe is already listening ----------------------------------

function Test-PortOpen {
    param([int] $Port)
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $c.Connect('127.0.0.1', $Port)
        $c.Close()
        return $true
    } catch {
        return $false
    }
}

$alreadyRunning = Test-PortOpen -Port $Port
$weStartedIt    = $false

if ($alreadyRunning -and $Restart) {
    Info "hix.exe is running -- stopping (--Restart)."
    Stop-ProjectExe -ProcessId 0 -ExeName $ExeName
    Start-Sleep -Milliseconds 800
    $alreadyRunning = $false
}

if (-not $alreadyRunning) {
    Info "Starting $ExeName from $Root ..."
    $proc = Start-Process -FilePath $exePath `
                          -WorkingDirectory $Root `
                          -WindowStyle Hidden `
                          -PassThru
    $weStartedIt = $true
    if (-not (Wait-ForHttp -Url "$baseUrl/" -TimeoutMs $TimeoutMs)) {
        FailMsg "Server did not respond on $baseUrl within $TimeoutMs ms."
        if ($weStartedIt) { Stop-ProjectExe -ProcessId $proc.Id -ExeName $ExeName }
        exit 4
    }
    OK "Server is up (pid=$($proc.Id))."
} else {
    OK "Reusing running hix.exe on port $Port."
}

# ---- Iterate tests ----------------------------------------------------------

$pass = 0
$fail = 0
$results = @()

try {
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
    if ($weStartedIt -and -not $KeepRunning) {
        Info "Stopping $ExeName (we started it) ..."
        Stop-ProjectExe -ProcessId 0 -ExeName $ExeName
    } elseif ($weStartedIt -and $KeepRunning) {
        WarnMsg "Leaving $ExeName running (--KeepRunning)."
    } else {
        Info "Leaving $ExeName running (it was already up)."
    }
}

# ---- Report -----------------------------------------------------------------

$total = $pass + $fail
Write-Host ''
Write-Host "======================================================================"
Write-Host " HIX IA (live) -- Test summary"
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
