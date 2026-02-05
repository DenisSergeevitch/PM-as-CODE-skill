#!/usr/bin/env pwsh
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$PMDir = ".pm"
$LockDir = Join-Path $PMDir ".collab-lock"
$LockInfo = Join-Path $LockDir "lock.env"
$ClaimsFile = Join-Path $PMDir "claims.tsv"
$PulseFile = Join-Path $PMDir "pulse.log"

$LockWaitSeconds = 120
$LockStaleSeconds = 900
$LockPollSeconds = 1

if ($env:PM_LOCK_WAIT_SECONDS) {
    $LockWaitSeconds = [int]$env:PM_LOCK_WAIT_SECONDS
}
if ($env:PM_LOCK_STALE_SECONDS) {
    $LockStaleSeconds = [int]$env:PM_LOCK_STALE_SECONDS
}
if ($env:PM_LOCK_POLL_SECONDS) {
    $LockPollSeconds = [int]$env:PM_LOCK_POLL_SECONDS
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PMTicket = Join-Path $ScriptDir "pm-ticket.ps1"
$script:LockToken = ""

function Write-Usage {
    @'
Usage:
  pm-collab.ps1 init
  pm-collab.ps1 claim <agent> <T-0001> [note]
  pm-collab.ps1 unclaim <agent> <T-0001>
  pm-collab.ps1 claims
  pm-collab.ps1 run <agent> -- <pm-ticket command...>
  pm-collab.ps1 lock-info
  pm-collab.ps1 unlock-stale

Examples:
  scripts/pm-collab.ps1 init
  scripts/pm-collab.ps1 claim agent-a T-0001 "taking API task"
  scripts/pm-collab.ps1 run agent-a -- move T-0001 in-progress
  scripts/pm-collab.ps1 run agent-a -- done T-0001 "src/api/auth.ts" "tests passed"
'@ | Write-Output
}

function Get-NowTs {
    (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}

function Sanitize([string]$Text) {
    if ($null -eq $Text) {
        return ""
    }
    $value = $Text -replace "`t", " " -replace "`r", " " -replace "`n", " "
    return $value
}

function Require-PMTicket {
    if (-not (Test-Path -LiteralPath $PMTicket -PathType Leaf)) {
        throw "error: missing $PMTicket"
    }
}

function Read-LockField([string]$Key) {
    if (-not (Test-Path -LiteralPath $LockInfo -PathType Leaf)) {
        return ""
    }
    foreach ($line in Get-Content -LiteralPath $LockInfo) {
        if ($line -match "^\Q$Key\E=(.*)$") {
            return $Matches[1]
        }
    }
    return ""
}

function Lock-AgeSeconds {
    if (-not (Test-Path -LiteralPath $LockDir -PathType Container)) {
        return 0
    }
    $item = Get-Item -LiteralPath $LockDir
    $age = [int]((Get-Date).ToUniversalTime() - $item.LastWriteTimeUtc).TotalSeconds
    if ($age -lt 0) {
        return 0
    }
    return $age
}

function Remove-LockDir {
    if (Test-Path -LiteralPath $LockInfo -PathType Leaf) {
        Remove-Item -LiteralPath $LockInfo -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $LockDir -PathType Container) {
        Remove-Item -LiteralPath $LockDir -Force -Recurse -ErrorAction SilentlyContinue
    }
}

function Lock-IsStale {
    if (-not (Test-Path -LiteralPath $LockDir -PathType Container)) {
        return $false
    }

    $host = Read-LockField "host"
    $pidRaw = Read-LockField "pid"
    $currentHost = [System.Net.Dns]::GetHostName()

    if ($pidRaw -ne "" -and $host -ne "" -and $host -eq $currentHost) {
        $pidVal = 0
        if ([int]::TryParse($pidRaw, [ref]$pidVal)) {
            $proc = Get-Process -Id $pidVal -ErrorAction SilentlyContinue
            if ($null -ne $proc) {
                return $false
            }
        }
    }

    $age = Lock-AgeSeconds
    return ($age -ge $LockStaleSeconds)
}

function Release-Lock {
    if ($script:LockToken -eq "") {
        return
    }

    if (Test-Path -LiteralPath $LockDir -PathType Container) {
        $token = Read-LockField "token"
        if ($token -ne "" -and $token -eq $script:LockToken) {
            Remove-LockDir
        }
    }
    $script:LockToken = ""
}

function Acquire-Lock([string]$Agent) {
    if (-not (Test-Path -LiteralPath $PMDir -PathType Container)) {
        New-Item -ItemType Directory -Path $PMDir | Out-Null
    }

    $deadline = (Get-Date).AddSeconds($LockWaitSeconds)
    while ($true) {
        try {
            New-Item -ItemType Directory -Path $LockDir -ErrorAction Stop | Out-Null
            $script:LockToken = "$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())-$PID-$(Get-Random)"
            $lockLines = @(
                "agent=$Agent"
                "pid=$PID"
                "host=$([System.Net.Dns]::GetHostName())"
                "token=$script:LockToken"
                "started=$(Get-NowTs)"
            )
            Set-Content -LiteralPath $LockInfo -Value $lockLines
            return
        } catch {
            if (Lock-IsStale) {
                Write-Warning "removing stale lock (age $(Lock-AgeSeconds)s)"
                Remove-LockDir
                continue
            }

            if ((Get-Date) -ge $deadline) {
                $owner = Read-LockField "agent"
                $host = Read-LockField "host"
                $pid = Read-LockField "pid"
                $started = Read-LockField "started"
                if ($owner -eq "") { $owner = "unknown" }
                if ($host -eq "") { $host = "unknown" }
                if ($pid -eq "") { $pid = "unknown" }
                if ($started -eq "") { $started = "unknown" }
                throw "error: lock timeout after ${LockWaitSeconds}s`nlock owner: $owner`nlock host: $host`nlock pid: $pid`nlock started: $started"
            }

            Start-Sleep -Seconds $LockPollSeconds
        }
    }
}

function Append-Pulse([string]$TaskId, [string]$Event, [string]$Details = "") {
    $safeDetails = Sanitize $Details
    Add-Content -LiteralPath $PulseFile -Value "$(Get-NowTs)|$TaskId|$Event|$safeDetails"
}

function Ensure-PMInitialized {
    $ticketsFile = Join-Path $PMDir "tickets.tsv"
    if (-not (Test-Path -LiteralPath $ticketsFile -PathType Leaf)) {
        throw "error: .pm not initialized. Run: scripts/pm-collab.ps1 init"
    }
}

function Ensure-ClaimsFile {
    if (-not (Test-Path -LiteralPath $PMDir -PathType Container)) {
        New-Item -ItemType Directory -Path $PMDir | Out-Null
    }
    if (-not (Test-Path -LiteralPath $ClaimsFile -PathType Leaf)) {
        Set-Content -LiteralPath $ClaimsFile -Value "id`tagent`tclaimed_at`tnote"
    }
}

function Read-Tickets {
    $ticketsFile = Join-Path $PMDir "tickets.tsv"
    if (-not (Test-Path -LiteralPath $ticketsFile -PathType Leaf)) {
        return @()
    }
    $lines = Get-Content -LiteralPath $ticketsFile
    if ($lines.Count -le 1) {
        return @()
    }
    $rows = @()
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -eq "") {
            continue
        }
        $parts = $lines[$i].Split("`t", 6)
        while ($parts.Count -lt 6) {
            $parts += ""
        }
        $rows += [pscustomobject]@{
            id      = $parts[0]
            state   = $parts[1]
            title   = $parts[2]
            deps    = $parts[3]
            created = $parts[4]
            updated = $parts[5]
        }
    }
    return $rows
}

function Ticket-Exists([string]$TaskId) {
    $rows = Read-Tickets
    return ($rows | Where-Object { $_.id -eq $TaskId }).Count -gt 0
}

function Ticket-State([string]$TaskId) {
    $rows = Read-Tickets
    $row = $rows | Where-Object { $_.id -eq $TaskId } | Select-Object -First 1
    if ($null -eq $row) {
        throw "error: task not found: $TaskId"
    }
    return $row.state
}

function Read-Claims {
    if (-not (Test-Path -LiteralPath $ClaimsFile -PathType Leaf)) {
        return @()
    }
    $lines = Get-Content -LiteralPath $ClaimsFile
    if ($lines.Count -le 1) {
        return @()
    }
    $rows = @()
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -eq "") {
            continue
        }
        $parts = $lines[$i].Split("`t", 4)
        while ($parts.Count -lt 4) {
            $parts += ""
        }
        $rows += [pscustomobject]@{
            id         = $parts[0]
            agent      = $parts[1]
            claimed_at = $parts[2]
            note       = $parts[3]
        }
    }
    return $rows
}

function Write-Claims([array]$Rows) {
    $out = @("id`tagent`tclaimed_at`tnote")
    foreach ($row in $Rows) {
        $out += "$($row.id)`t$($row.agent)`t$($row.claimed_at)`t$($row.note)"
    }
    Set-Content -LiteralPath $ClaimsFile -Value $out
}

function Claim-Owner([string]$TaskId) {
    $rows = Read-Claims
    $row = $rows | Where-Object { $_.id -eq $TaskId } | Select-Object -First 1
    if ($null -eq $row) {
        return ""
    }
    return $row.agent
}

function Remove-Claim([string]$TaskId) {
    $rows = Read-Claims
    $filtered = @($rows | Where-Object { $_.id -ne $TaskId })
    Write-Claims $filtered
}

function TaskId-FromPMCommand([string]$PMCmd, [string]$MaybeId = "") {
    switch ($PMCmd) {
        "move" { return $MaybeId }
        "criterion-add" { return $MaybeId }
        "criterion-check" { return $MaybeId }
        "evidence" { return $MaybeId }
        "done" { return $MaybeId }
        default { return "" }
    }
}

function Is-MutatingPMCommand([string]$PMCmd) {
    switch ($PMCmd) {
        "init" { return $true }
        "new" { return $true }
        "move" { return $true }
        "criterion-add" { return $true }
        "criterion-check" { return $true }
        "evidence" { return $true }
        "done" { return $true }
        "render" { return $true }
        default { return $false }
    }
}

function Ensure-TaskClaimedByAgent([string]$Agent, [string]$TaskId) {
    $owner = Claim-Owner $TaskId
    if ($owner -eq "") {
        throw "error: $TaskId is not claimed. Run: scripts/pm-collab.ps1 claim $Agent $TaskId"
    }
    if ($owner -ne $Agent) {
        throw "error: $TaskId is claimed by '$owner' (agent '$Agent' cannot modify it)"
    }
}

function Get-PowerShellExe {
    if ($PSVersionTable.PSEdition -eq "Core") {
        $path = (Get-Process -Id $PID).Path
        if ($path) {
            return $path
        }
    }
    return "powershell.exe"
}

function Invoke-PMTicket([string[]]$Args) {
    $psExe = Get-PowerShellExe
    & $psExe -NoProfile -ExecutionPolicy Bypass -File $PMTicket @Args
    if ($LASTEXITCODE -ne 0) {
        throw "error: pm-ticket failed with exit code $LASTEXITCODE"
    }
}

function Cmd-Init {
    Acquire-Lock "SYSTEM"
    try {
        Invoke-PMTicket @("init")
        Ensure-ClaimsFile
        Append-Pulse "SYSTEM" "COLLAB_INIT" "collab lock and claims enabled"
        Invoke-PMTicket @("render", "status.md")
    } finally {
        Release-Lock
    }
}

function Cmd-Claim([string]$Agent, [string]$TaskId, [string]$Note = "") {
    $safeNote = Sanitize $Note

    Acquire-Lock $Agent
    try {
        Ensure-PMInitialized
        Ensure-ClaimsFile

        if (-not (Ticket-Exists $TaskId)) {
            throw "error: task not found: $TaskId"
        }

        $state = Ticket-State $TaskId
        if ($state -eq "DONE") {
            throw "error: cannot claim completed task $TaskId"
        }

        $owner = Claim-Owner $TaskId
        if ($owner -ne "") {
            if ($owner -eq $Agent) {
                Write-Output "$TaskId already claimed by $Agent"
                return
            }
            throw "error: $TaskId already claimed by $owner"
        }

        Add-Content -LiteralPath $ClaimsFile -Value "$TaskId`t$Agent`t$(Get-NowTs)`t$safeNote"
        $details = "agent=$Agent"
        if ($safeNote -ne "") {
            $details = "$details note=$safeNote"
        }
        Append-Pulse $TaskId "CLAIM" $details
        Invoke-PMTicket @("render", "status.md")
        Write-Output "$TaskId claimed by $Agent"
    } finally {
        Release-Lock
    }
}

function Cmd-Unclaim([string]$Agent, [string]$TaskId) {
    Acquire-Lock $Agent
    try {
        Ensure-PMInitialized
        Ensure-ClaimsFile

        $owner = Claim-Owner $TaskId
        if ($owner -eq "") {
            throw "error: task is not claimed: $TaskId"
        }
        if ($owner -ne $Agent) {
            throw "error: $TaskId is claimed by $owner (not $Agent)"
        }

        Remove-Claim $TaskId
        Append-Pulse $TaskId "UNCLAIM" "agent=$Agent"
        Invoke-PMTicket @("render", "status.md")
        Write-Output "$TaskId released by $Agent"
    } finally {
        Release-Lock
    }
}

function Cmd-Claims {
    Ensure-PMInitialized
    Ensure-ClaimsFile
    $rows = Read-Claims
    if ($rows.Count -eq 0) {
        Write-Output "(none)"
        return
    }
    foreach ($row in $rows) {
        Write-Output "$($row.id)`t$($row.agent)`t$($row.claimed_at)`t$($row.note)"
    }
}

function Cmd-LockInfo {
    if (-not (Test-Path -LiteralPath $LockDir -PathType Container)) {
        Write-Output "lock: free"
        return
    }
    $owner = Read-LockField "agent"
    $host = Read-LockField "host"
    $pid = Read-LockField "pid"
    $started = Read-LockField "started"
    if ($owner -eq "") { $owner = "unknown" }
    if ($host -eq "") { $host = "unknown" }
    if ($pid -eq "") { $pid = "unknown" }
    if ($started -eq "") { $started = "unknown" }
    Write-Output "lock: held"
    Write-Output "owner: $owner"
    Write-Output "host: $host"
    Write-Output "pid: $pid"
    Write-Output "started: $started"
    Write-Output "age_seconds: $(Lock-AgeSeconds)"
}

function Cmd-UnlockStale {
    if (-not (Test-Path -LiteralPath $LockDir -PathType Container)) {
        Write-Output "lock already free"
        return
    }
    if (Lock-IsStale) {
        Remove-LockDir
        Write-Output "stale lock removed"
        return
    }
    throw "error: lock is active and not stale"
}

function Cmd-Run([string]$Agent, [string[]]$PMArgs) {
    $argsList = @($PMArgs)
    if ($argsList.Count -gt 0 -and $argsList[0] -eq "--") {
        if ($argsList.Count -eq 1) {
            throw "error: run requires a pm-ticket command"
        }
        $argsList = $argsList[1..($argsList.Count - 1)]
    }
    if ($argsList.Count -lt 1) {
        throw "error: run requires a pm-ticket command"
    }

    $pmCmd = $argsList[0]
    $taskId = ""
    if ($argsList.Count -ge 2) {
        $taskId = TaskId-FromPMCommand $pmCmd $argsList[1]
    } else {
        $taskId = TaskId-FromPMCommand $pmCmd ""
    }

    Acquire-Lock $Agent
    try {
        if ($pmCmd -ne "init") {
            Ensure-PMInitialized
            Ensure-ClaimsFile
        }

        if ($taskId -ne "") {
            Ensure-TaskClaimedByAgent $Agent $taskId
        }

        Invoke-PMTicket $argsList

        if ($taskId -ne "" -and $pmCmd -eq "done") {
            $owner = Claim-Owner $taskId
            if ($owner -eq $Agent) {
                Remove-Claim $taskId
                Append-Pulse $taskId "UNCLAIM" "auto-release on done by $Agent"
            }
        }

        if ((Is-MutatingPMCommand $pmCmd) -and $pmCmd -ne "render") {
            Invoke-PMTicket @("render", "status.md")
        }
    } finally {
        Release-Lock
    }
}

Require-PMTicket

if ($args.Count -lt 1) {
    Write-Usage
    exit 1
}

$command = $args[0]
$rest = @()
if ($args.Count -gt 1) {
    $rest = $args[1..($args.Count - 1)]
}

try {
    switch ($command) {
        "init" {
            Cmd-Init
        }
        "claim" {
            if ($rest.Count -lt 2) { throw "error: claim requires <agent> <task-id>" }
            $note = ""
            if ($rest.Count -ge 3) { $note = $rest[2] }
            Cmd-Claim $rest[0] $rest[1] $note
        }
        "unclaim" {
            if ($rest.Count -lt 2) { throw "error: unclaim requires <agent> <task-id>" }
            Cmd-Unclaim $rest[0] $rest[1]
        }
        "claims" {
            Cmd-Claims
        }
        "run" {
            if ($rest.Count -lt 2) { throw "error: run requires <agent> and command args" }
            $agent = $rest[0]
            $runArgs = @()
            if ($rest.Count -gt 1) {
                $runArgs = $rest[1..($rest.Count - 1)]
            }
            Cmd-Run $agent $runArgs
        }
        "lock-info" {
            Cmd-LockInfo
        }
        "unlock-stale" {
            Cmd-UnlockStale
        }
        default {
            Write-Usage
            throw "error: unknown command '$command'"
        }
    }
} catch {
    Write-Error $_
    exit 1
}
