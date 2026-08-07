# helpers.ps1
# Dot-sourced helpers for run.ps1.
# ASCII only -- Windows PowerShell 5.1 reads .ps1 as Windows-1252.

# ---- Find-FreePort -----------------------------------------------------------
# Ask the OS for a free TCP port on the loopback interface.
# Returns an integer port number.

function Find-FreePort {
    $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    $listener.Stop()
    return $port
}

# ---- Wait-ForHttp ------------------------------------------------------------
# Poll a URL until it responds (any HTTP status counts as alive) or timeout.
# Returns $true if the server responded, $false on timeout.

function Wait-ForHttp {
    param(
        [Parameter(Mandatory=$true)] [string] $Url,
        [int] $TimeoutMs = 15000,
        [int] $IntervalMs = 250
    )
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    while ((Get-Date) -lt $deadline) {
        try {
            $null = Invoke-WebRequest -Uri $Url -TimeoutSec 1 -UseBasicParsing -ErrorAction Stop
            return $true
        } catch [System.Net.WebException] {
            # Server responded but with a non-2xx status -- still alive.
            if ($_.Exception.Response -ne $null) {
                return $true
            }
        } catch {
            # ignore -- keep polling
        }
        Start-Sleep -Milliseconds $IntervalMs
    }
    return $false
}

# ---- Stop-ProjectExe ---------------------------------------------------------
# Kill a process by id AND its children, plus any orphaned exe by name.
# Idempotent -- silences errors so it is safe in finally blocks.

function Stop-ProjectExe {
    param(
        [int]    $ProcessId,
        [string] $ExeName
    )
    if ($ProcessId -gt 0) {
        try {
            Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
        } catch { }
        # taskkill /T also kills children (worker threads, cmd wrappers, etc.)
        try {
            & taskkill.exe /F /PID $ProcessId /T 2>$null | Out-Null
        } catch { }
    }
    if ($ExeName) {
        try {
            & taskkill.exe /F /IM $ExeName /T 2>$null | Out-Null
        } catch { }
    }
}

# ---- Get-ProjectExeName ------------------------------------------------------
# Guess the name of the .exe produced by a HIX project.
# Priority:
#   1) File named "app.exe" in the project root.
#   2) The first *.exe in the project root.
# Returns filename (not path), or $null if none found.

function Get-ProjectExeName {
    param(
        [Parameter(Mandatory=$true)] [string] $ProjectPath
    )
    $app = Join-Path $ProjectPath 'app.exe'
    if (Test-Path -LiteralPath $app -PathType Leaf) {
        return 'app.exe'
    }
    $first = Get-ChildItem -LiteralPath $ProjectPath -Filter '*.exe' -File -ErrorAction SilentlyContinue |
             Select-Object -First 1
    if ($first) {
        return $first.Name
    }
    return $null
}

# ---- Set-HixJsonPort ---------------------------------------------------------
# Overwrite hix.json's server.port with a new value, returning the original
# JSON text so the caller can restore it later. If hix.json does not exist,
# creates a minimal one and returns $null (caller should delete on cleanup).

function Set-HixJsonPort {
    param(
        [Parameter(Mandatory=$true)] [string] $ProjectPath,
        [Parameter(Mandatory=$true)] [int]    $Port
    )
    $hixJson = Join-Path $ProjectPath 'hix.json'
    $original = $null

    if (Test-Path -LiteralPath $hixJson -PathType Leaf) {
        $original = Get-Content -LiteralPath $hixJson -Raw -Encoding UTF8
        $patched = $original
        # Replace "port": <number> under a server block. Naive but robust for
        # the standard hix.json emitted by HIX (single server block).
        $patched = [regex]::Replace(
            $patched,
            '("port"\s*:\s*)\d+',
            "`${1}$Port",
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )
        # ASCII-only, no BOM -- keep it identical to what HIX writes.
        [System.IO.File]::WriteAllText($hixJson, $patched, (New-Object System.Text.UTF8Encoding($false)))
    } else {
        $minimal = @"
{
  "server": { "host": "127.0.0.1", "port": $Port, "autostart": true },
  "paths":  { "root": "www" },
  "hixstyle": { "enabled": true }
}
"@
        [System.IO.File]::WriteAllText($hixJson, $minimal, (New-Object System.Text.UTF8Encoding($false)))
    }

    return $original
}

# ---- Restore-HixJson ---------------------------------------------------------
# Restore the original hix.json text (or delete the file if there was none).

function Restore-HixJson {
    param(
        [Parameter(Mandatory=$true)] [string] $ProjectPath,
        [string] $OriginalContent
    )
    $hixJson = Join-Path $ProjectPath 'hix.json'
    if ($OriginalContent -ne $null) {
        try {
            [System.IO.File]::WriteAllText($hixJson, $OriginalContent, (New-Object System.Text.UTF8Encoding($false)))
        } catch { }
    } else {
        try {
            Remove-Item -LiteralPath $hixJson -Force -ErrorAction SilentlyContinue
        } catch { }
    }
}
