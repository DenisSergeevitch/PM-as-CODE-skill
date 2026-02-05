#!/usr/bin/env pwsh
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$PMDir = ".pm"
$MetaFile = Join-Path $PMDir "meta.env"
$CoreFile = Join-Path $PMDir "core.md"
$TicketsFile = Join-Path $PMDir "tickets.tsv"
$CriteriaFile = Join-Path $PMDir "criteria.tsv"
$EvidenceFile = Join-Path $PMDir "evidence.tsv"
$PulseFile = Join-Path $PMDir "pulse.log"

function Write-Usage {
    @'
Usage:
  pm-ticket.ps1 init
  pm-ticket.ps1 new <now|in-progress|blocked|next> "<title>" [deps]
  pm-ticket.ps1 move <T-0001> <now|in-progress|blocked|next|done> [note]
  pm-ticket.ps1 criterion-add <T-0001> "<criterion>"
  pm-ticket.ps1 criterion-check <T-0001> <index>
  pm-ticket.ps1 evidence <T-0001> "<path-or-link>" [note]
  pm-ticket.ps1 done <T-0001> "<path-or-link>" [note]
  pm-ticket.ps1 list [state]
  pm-ticket.ps1 render [status.md]
  pm-ticket.ps1 next-id
'@ | Write-Output
}

function Get-NowDate {
    (Get-Date).ToString("yyyy-MM-dd")
}

function Get-NowTimestamp {
    (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}

function Sanitize([string]$Text) {
    if ($null -eq $Text) {
        return ""
    }
    $value = $Text -replace "`t", " " -replace "`r", " " -replace "`n", " "
    return $value
}

function Require-PMDir {
    if (-not (Test-Path -LiteralPath $PMDir -PathType Container)) {
        throw "error: $PMDir not initialized. Run: pm-ticket.ps1 init"
    }
}

function Normalize-State([string]$State) {
    $raw = ""
    if ($null -ne $State) {
        $raw = $State.ToLowerInvariant()
    }
    switch ($raw) {
        "now" { return "NOW" }
        "in-progress" { return "IN_PROGRESS" }
        "inprogress" { return "IN_PROGRESS" }
        "doing" { return "IN_PROGRESS" }
        "blocked" { return "BLOCKED" }
        "next" { return "NEXT" }
        "todo" { return "NEXT" }
        "done" { return "DONE" }
        "closed" { return "DONE" }
        default { throw "error: invalid state '$State'" }
    }
}

function State-Heading([string]$State) {
    switch ($State) {
        "NOW" { return "Now (top priorities)" }
        "IN_PROGRESS" { return "In progress" }
        "BLOCKED" { return "Blocked" }
        "NEXT" { return "Next" }
        "DONE" { return "Done" }
        default { return "Unknown" }
    }
}

function Format-TaskId([int]$Num) {
    return ("T-{0:D4}" -f $Num)
}

function Ensure-BaseFiles {
    if (-not (Test-Path -LiteralPath $PMDir -PathType Container)) {
        New-Item -ItemType Directory -Path $PMDir | Out-Null
    }
    if (-not (Test-Path -LiteralPath $TicketsFile)) {
        Set-Content -LiteralPath $TicketsFile -Value "id`tstate`ttitle`tdeps`tcreated`tupdated"
    }
    if (-not (Test-Path -LiteralPath $CriteriaFile)) {
        Set-Content -LiteralPath $CriteriaFile -Value "id`tdone`ttext"
    }
    if (-not (Test-Path -LiteralPath $EvidenceFile)) {
        Set-Content -LiteralPath $EvidenceFile -Value "id`tdate`tlocation`tnote"
    }
    if (-not (Test-Path -LiteralPath $PulseFile)) {
        Set-Content -LiteralPath $PulseFile -Value @()
    }
}

function Load-Meta {
    Require-PMDir
    if (-not (Test-Path -LiteralPath $MetaFile)) {
        throw "error: missing $MetaFile"
    }
    $meta = @{}
    foreach ($line in Get-Content -LiteralPath $MetaFile) {
        if ($line -match "^\s*([A-Z_]+)=(.*)\s*$") {
            $meta[$Matches[1]] = $Matches[2]
        }
    }
    $script:NextTaskNum = 1
    $script:PulseTail = 30
    if ($meta.ContainsKey("NEXT_TASK_NUM")) {
        $script:NextTaskNum = [int]$meta["NEXT_TASK_NUM"]
    }
    if ($meta.ContainsKey("PULSE_TAIL")) {
        $script:PulseTail = [int]$meta["PULSE_TAIL"]
    }
}

function Save-Meta {
    $body = @(
        "NEXT_TASK_NUM=$script:NextTaskNum"
        "PULSE_TAIL=$script:PulseTail"
    )
    Set-Content -LiteralPath $MetaFile -Value $body
}

function Append-Pulse([string]$TaskId, [string]$Event, [string]$Details) {
    $safeDetails = Sanitize $Details
    $line = "$(Get-NowTimestamp)|$TaskId|$Event|$safeDetails"
    Add-Content -LiteralPath $PulseFile -Value $line
}

function Read-Tickets {
    if (-not (Test-Path -LiteralPath $TicketsFile)) {
        return @()
    }
    $lines = Get-Content -LiteralPath $TicketsFile
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

function Write-Tickets([array]$Rows) {
    $out = @("id`tstate`ttitle`tdeps`tcreated`tupdated")
    foreach ($row in $Rows) {
        $out += "$($row.id)`t$($row.state)`t$($row.title)`t$($row.deps)`t$($row.created)`t$($row.updated)"
    }
    Set-Content -LiteralPath $TicketsFile -Value $out
}

function Read-Criteria {
    if (-not (Test-Path -LiteralPath $CriteriaFile)) {
        return @()
    }
    $lines = Get-Content -LiteralPath $CriteriaFile
    if ($lines.Count -le 1) {
        return @()
    }
    $rows = @()
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -eq "") {
            continue
        }
        $parts = $lines[$i].Split("`t", 3)
        while ($parts.Count -lt 3) {
            $parts += ""
        }
        $rows += [pscustomobject]@{
            id   = $parts[0]
            done = $parts[1]
            text = $parts[2]
        }
    }
    return $rows
}

function Write-Criteria([array]$Rows) {
    $out = @("id`tdone`ttext")
    foreach ($row in $Rows) {
        $out += "$($row.id)`t$($row.done)`t$($row.text)"
    }
    Set-Content -LiteralPath $CriteriaFile -Value $out
}

function Read-Evidence {
    if (-not (Test-Path -LiteralPath $EvidenceFile)) {
        return @()
    }
    $lines = Get-Content -LiteralPath $EvidenceFile
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
            id       = $parts[0]
            date     = $parts[1]
            location = $parts[2]
            note     = $parts[3]
        }
    }
    return $rows
}

function Ticket-Exists([string]$TaskId) {
    $rows = Read-Tickets
    return ($rows | Where-Object { $_.id -eq $TaskId }).Count -gt 0
}

function Cmd-Init {
    Ensure-BaseFiles
    if (-not (Test-Path -LiteralPath $MetaFile)) {
        $script:NextTaskNum = 1
        $script:PulseTail = 30
        Save-Meta
    }
    if (-not (Test-Path -LiteralPath $CoreFile)) {
        @'
## CORE context (keep short; must stay true)

### Objective
<One sentence: what winning means.>

### Current phase
<Discovery | Build | Beta | Launch | Maintenance>

### Constraints (if any)
- <constraint 1>
- <constraint 2>

### Success metrics (if known)
- <metric 1>
- <metric 2>

### Scope boundaries (if helpful)
- In scope: <...>
- Out of scope: <...>
'@ | Set-Content -LiteralPath $CoreFile
    }
    Append-Pulse "SYSTEM" "INIT" "Initialized .pm ledger"
    Cmd-Render "status.md"
}

function Cmd-New([string]$StateInput, [string]$TitleInput, [string]$DepsInput = "") {
    Load-Meta
    Ensure-BaseFiles
    $state = Normalize-State $StateInput
    $title = Sanitize $TitleInput
    $deps = Sanitize $DepsInput
    $today = Get-NowDate
    $taskId = Format-TaskId $script:NextTaskNum
    Add-Content -LiteralPath $TicketsFile -Value "$taskId`t$state`t$title`t$deps`t$today`t$today"
    $script:NextTaskNum++
    Save-Meta
    Append-Pulse $taskId "CREATE" "state=$state title=$title"
    Write-Output $taskId
}

function Cmd-Move([string]$TaskId, [string]$StateInput, [string]$Note = "") {
    Load-Meta
    $newState = Normalize-State $StateInput
    $safeNote = Sanitize $Note
    $rows = Read-Tickets
    $found = $false
    foreach ($row in $rows) {
        if ($row.id -eq $TaskId) {
            $row.state = $newState
            $row.updated = Get-NowDate
            $found = $true
            break
        }
    }
    if (-not $found) {
        throw "error: task not found: $TaskId"
    }
    Write-Tickets $rows
    $details = "state=$newState"
    if ($safeNote -ne "") {
        $details = "$details - $safeNote"
    }
    Append-Pulse $TaskId "MOVE" $details
}

function Cmd-CriterionAdd([string]$TaskId, [string]$Text) {
    Load-Meta
    if (-not (Ticket-Exists $TaskId)) {
        throw "error: task not found: $TaskId"
    }
    $safeText = Sanitize $Text
    Add-Content -LiteralPath $CriteriaFile -Value "$TaskId`t0`t$safeText"
    Append-Pulse $TaskId "CRITERION_ADD" $safeText
}

function Cmd-CriterionCheck([string]$TaskId, [int]$Index) {
    Load-Meta
    $rows = Read-Criteria
    $count = 0
    $found = $false
    foreach ($row in $rows) {
        if ($row.id -eq $TaskId) {
            $count++
            if ($count -eq $Index) {
                $row.done = "1"
                $found = $true
                break
            }
        }
    }
    if (-not $found) {
        throw "error: criterion index not found for $TaskId: $Index"
    }
    Write-Criteria $rows
    Append-Pulse $TaskId "CRITERION_CHECK" "index=$Index"
}

function Cmd-Evidence([string]$TaskId, [string]$Location, [string]$Note = "") {
    Load-Meta
    if (-not (Ticket-Exists $TaskId)) {
        throw "error: task not found: $TaskId"
    }
    $safeLocation = Sanitize $Location
    $safeNote = Sanitize $Note
    Add-Content -LiteralPath $EvidenceFile -Value "$TaskId`t$(Get-NowDate)`t$safeLocation`t$safeNote"
    if ($safeNote -ne "") {
        Append-Pulse $TaskId "EVIDENCE" "$safeLocation - $safeNote"
    } else {
        Append-Pulse $TaskId "EVIDENCE" $safeLocation
    }
}

function Cmd-Done([string]$TaskId, [string]$Location, [string]$Note = "") {
    Cmd-Evidence $TaskId $Location $Note
    Cmd-Move $TaskId "done" "completed"
}

function Cmd-List([string]$State = "") {
    Load-Meta
    $rows = Read-Tickets
    $filter = ""
    if ($State -ne "") {
        $filter = Normalize-State $State
    }
    foreach ($row in $rows) {
        if ($filter -eq "" -or $row.state -eq $filter) {
            Write-Output "$($row.id)`t$($row.state)`t$($row.title)"
        }
    }
}

function Render-StateSection([array]$Rows, [string]$State, [System.Collections.Generic.List[string]]$OutLines) {
    $OutLines.Add("### $(State-Heading $State)")
    $filtered = $Rows | Where-Object { $_.state -eq $State }
    if ($filtered.Count -eq 0) {
        $OutLines.Add("- (none)")
    } else {
        foreach ($row in $filtered) {
            $dep = ""
            if ($row.deps -ne "") {
                $dep = " (deps: $($row.deps))"
            }
            $OutLines.Add("- [ ] $($row.id) - $($row.title)$dep")
        }
    }
    $OutLines.Add("")
}

function Cmd-Render([string]$OutPath = "status.md") {
    Load-Meta
    $nextTaskId = Format-TaskId $script:NextTaskNum
    $tickets = Read-Tickets
    $criteria = Read-Criteria
    $evidence = Read-Evidence
    $lines = [System.Collections.Generic.List[string]]::new()

    $lines.Add("# status.md")
    $lines.Add("## Project Pulse")
    $lines.Add("")
    $lines.Add("Last updated: $(Get-NowDate)")
    $lines.Add("")
    $lines.Add("---")
    $lines.Add("")

    if (Test-Path -LiteralPath $CoreFile) {
        foreach ($line in Get-Content -LiteralPath $CoreFile) {
            $lines.Add($line)
        }
        $lines.Add("")
    } else {
        $lines.Add("## CORE context (keep short; must stay true)")
        $lines.Add("")
        $lines.Add("### Objective")
        $lines.Add("<One sentence: what winning means.>")
        $lines.Add("")
        $lines.Add("### Current phase")
        $lines.Add("<Discovery | Build | Beta | Launch | Maintenance>")
        $lines.Add("")
    }

    $lines.Add("### Counters")
    $lines.Add("- Next Task ID: $nextTaskId")
    $lines.Add("")
    $lines.Add("---")
    $lines.Add("")
    $lines.Add("## Current state (always keep accurate)")
    $lines.Add("")
    Render-StateSection $tickets "NOW" $lines
    Render-StateSection $tickets "IN_PROGRESS" $lines
    Render-StateSection $tickets "BLOCKED" $lines
    Render-StateSection $tickets "NEXT" $lines
    $lines.Add("---")
    $lines.Add("")
    $lines.Add("## Acceptance criteria (required for active tasks)")
    $lines.Add("")

    $active = $tickets | Where-Object { $_.state -ne "DONE" }
    if ($active.Count -eq 0) {
        $lines.Add("_No active tasks_")
    } else {
        foreach ($task in $active) {
            $lines.Add("### $($task.id) acceptance criteria")
            $taskCriteria = $criteria | Where-Object { $_.id -eq $task.id }
            if ($taskCriteria.Count -eq 0) {
                $lines.Add("- [ ] Add acceptance criteria")
            } else {
                foreach ($criterion in $taskCriteria) {
                    $mark = " "
                    if ($criterion.done -eq "1") {
                        $mark = "x"
                    }
                    $lines.Add("- [$mark] $($criterion.text)")
                }
            }
            $lines.Add("")
        }
    }

    $lines.Add("---")
    $lines.Add("")
    $lines.Add("## Evidence index (keep it navigable)")
    $lines.Add("> Source of truth: .pm/evidence.tsv")
    $lines.Add("")
    if ($evidence.Count -eq 0) {
        $lines.Add("- (none)")
    } else {
        foreach ($ev in $evidence) {
            $note = ""
            if ($ev.note -ne "") {
                $note = " - $($ev.note)"
            }
            $lines.Add("- $($ev.id): $($ev.location) ($($ev.date))$note")
        }
    }
    $lines.Add("")
    $lines.Add("---")
    $lines.Add("")
    $lines.Add("## Pulse Log (append-only)")
    $lines.Add("> Source of truth: .pm/pulse.log (full history)")
    $lines.Add("> Showing latest $script:PulseTail entries to keep status.md compact")
    $lines.Add("")

    if (-not (Test-Path -LiteralPath $PulseFile) -or (Get-Content -LiteralPath $PulseFile).Count -eq 0) {
        $lines.Add("- (no entries)")
    } else {
        $tail = Get-Content -LiteralPath $PulseFile | Select-Object -Last $script:PulseTail
        foreach ($entry in $tail) {
            $parts = $entry -split "\|", 4
            while ($parts.Count -lt 4) {
                $parts += ""
            }
            $lines.Add("- $($parts[0]) | $($parts[1]) | $($parts[2]) | $($parts[3])")
        }
    }

    Set-Content -LiteralPath $OutPath -Value $lines
}

function Cmd-NextId {
    Load-Meta
    Write-Output (Format-TaskId $script:NextTaskNum)
}

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
        "new" {
            if ($rest.Count -lt 2) { throw "error: new requires <state> and <title>" }
            $deps = ""
            if ($rest.Count -ge 3) { $deps = $rest[2] }
            Cmd-New $rest[0] $rest[1] $deps
        }
        "move" {
            if ($rest.Count -lt 2) { throw "error: move requires <id> and <state>" }
            $note = ""
            if ($rest.Count -ge 3) { $note = $rest[2] }
            Cmd-Move $rest[0] $rest[1] $note
        }
        "criterion-add" {
            if ($rest.Count -lt 2) { throw "error: criterion-add requires <id> and <criterion>" }
            Cmd-CriterionAdd $rest[0] $rest[1]
        }
        "criterion-check" {
            if ($rest.Count -lt 2) { throw "error: criterion-check requires <id> and <index>" }
            Cmd-CriterionCheck $rest[0] ([int]$rest[1])
        }
        "evidence" {
            if ($rest.Count -lt 2) { throw "error: evidence requires <id> and <path-or-link>" }
            $note = ""
            if ($rest.Count -ge 3) { $note = $rest[2] }
            Cmd-Evidence $rest[0] $rest[1] $note
        }
        "done" {
            if ($rest.Count -lt 2) { throw "error: done requires <id> and <path-or-link>" }
            $note = ""
            if ($rest.Count -ge 3) { $note = $rest[2] }
            Cmd-Done $rest[0] $rest[1] $note
        }
        "list" {
            if ($rest.Count -ge 1) {
                Cmd-List $rest[0]
            } else {
                Cmd-List
            }
        }
        "render" {
            if ($rest.Count -ge 1) {
                Cmd-Render $rest[0]
            } else {
                Cmd-Render
            }
        }
        "next-id" {
            Cmd-NextId
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
