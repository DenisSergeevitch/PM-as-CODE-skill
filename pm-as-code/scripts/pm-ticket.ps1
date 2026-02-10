#!/usr/bin/env pwsh
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$PMRoot = ".pm"
$script:Scope = if ($env:PM_SCOPE) { $env:PM_SCOPE } else { "default" }

$script:PMDir = ""
$script:MetaFile = ""
$script:CoreFile = ""
$script:TicketsFile = ""
$script:CriteriaFile = ""
$script:EvidenceFile = ""
$script:PulseFile = ""
$script:ClaimsFile = ""

$script:NextTaskNum = 1
$script:PulseTail = 30
$script:NextLimit = 20
$script:EvidenceTail = 50
$script:ContextEvidenceTail = 10
$script:BloatTicketThreshold = 50

function Write-Usage {
    @'
Usage:
  pm-ticket.ps1 [--scope <name>] init
  pm-ticket.ps1 [--scope <name>] new <now|in-progress|blocked|next> "<title>" [deps]
  pm-ticket.ps1 [--scope <name>] move <T-0001> <now|in-progress|blocked|next|done> [note]
  pm-ticket.ps1 [--scope <name>] criterion-add <T-0001> "<criterion>"
  pm-ticket.ps1 [--scope <name>] criterion-check <T-0001> <index>
  pm-ticket.ps1 [--scope <name>] evidence <T-0001> "<path-or-link>" [note]
  pm-ticket.ps1 [--scope <name>] done <T-0001> "<path-or-link>" [note]
  pm-ticket.ps1 [--scope <name>] list [state]
  pm-ticket.ps1 [--scope <name>] render [status-file]
  pm-ticket.ps1 [--scope <name>] render-context <T-0001> [evidence-tail]
  pm-ticket.ps1 [--scope <name>] next-id

Scope resolution order:
1) --scope <name>
2) PM_SCOPE environment variable
3) default
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
    return ($Text -replace "`t", " " -replace "`r", " " -replace "`n", " ")
}

function Validate-ScopeName([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw "error: scope cannot be empty"
    }
    if ($Name -notmatch "^[A-Za-z0-9._-]+$") {
        throw "error: invalid scope '$Name' (allowed: letters, digits, ., _, -)"
    }
}

function Parse-GlobalOptions([string[]]$InputArgs) {
    $remaining = [System.Collections.Generic.List[string]]::new()
    $i = 0

    while ($i -lt $InputArgs.Count) {
        $arg = $InputArgs[$i]
        if ($arg -eq "--scope") {
            if ($i + 1 -ge $InputArgs.Count) {
                throw "error: --scope requires a value"
            }
            $script:Scope = $InputArgs[$i + 1]
            $i += 2
            continue
        }
        if ($arg.StartsWith("--scope=")) {
            $script:Scope = $arg.Substring(8)
            $i += 1
            continue
        }
        if ($arg -eq "-h" -or $arg -eq "--help") {
            Write-Usage
            exit 0
        }
        if ($arg -eq "--") {
            for ($j = $i + 1; $j -lt $InputArgs.Count; $j++) {
                $remaining.Add($InputArgs[$j])
            }
            $i = $InputArgs.Count
            break
        }

        for ($j = $i; $j -lt $InputArgs.Count; $j++) {
            $remaining.Add($InputArgs[$j])
        }
        $i = $InputArgs.Count
        break
    }

    Validate-ScopeName $script:Scope
    return @($remaining.ToArray())
}

function Set-ScopePaths {
    $script:PMDir = Join-Path $PMRoot ("scopes/" + $script:Scope)
    $script:MetaFile = Join-Path $script:PMDir "meta.env"
    $script:CoreFile = Join-Path $script:PMDir "core.md"
    $script:TicketsFile = Join-Path $script:PMDir "tickets.tsv"
    $script:CriteriaFile = Join-Path $script:PMDir "criteria.tsv"
    $script:EvidenceFile = Join-Path $script:PMDir "evidence.tsv"
    $script:PulseFile = Join-Path $script:PMDir "pulse.log"
    $script:ClaimsFile = Join-Path $script:PMDir "claims.tsv"
}

function Scoped-RelPath([string]$FileName) {
    return ".pm/scopes/$script:Scope/$FileName"
}

function Get-RecommendedPmTicketCommand {
    return "scripts\pm-ticket.cmd --scope $script:Scope <command>"
}

function Migrate-LegacyDefaultScope {
    if ($script:Scope -ne "default") {
        return
    }

    if (Test-Path -LiteralPath $script:PMDir -PathType Container) {
        return
    }

    $legacyFiles = @(
        "meta.env",
        "core.md",
        "tickets.tsv",
        "criteria.tsv",
        "evidence.tsv",
        "pulse.log",
        "claims.tsv"
    )

    $legacyFound = $false
    foreach ($f in $legacyFiles) {
        if (Test-Path -LiteralPath (Join-Path $PMRoot $f) -PathType Leaf) {
            $legacyFound = $true
            break
        }
    }

    if (-not $legacyFound) {
        return
    }

    New-Item -ItemType Directory -Path $script:PMDir -Force | Out-Null
    foreach ($f in $legacyFiles) {
        $oldPath = Join-Path $PMRoot $f
        $newPath = Join-Path $script:PMDir $f
        if (Test-Path -LiteralPath $oldPath -PathType Leaf) {
            Move-Item -LiteralPath $oldPath -Destination $newPath -Force
        }
    }
}

function Require-PMDir {
    Migrate-LegacyDefaultScope
    if (-not (Test-Path -LiteralPath $script:PMDir -PathType Container)) {
        throw "error: $script:PMDir not initialized. Run: pm-ticket.ps1 --scope $script:Scope init"
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
    if (-not (Test-Path -LiteralPath $script:PMDir -PathType Container)) {
        New-Item -ItemType Directory -Path $script:PMDir | Out-Null
    }
    if (-not (Test-Path -LiteralPath $script:TicketsFile -PathType Leaf)) {
        Set-Content -LiteralPath $script:TicketsFile -Value "id`tstate`ttitle`tdeps`tcreated`tupdated"
    }
    if (-not (Test-Path -LiteralPath $script:CriteriaFile -PathType Leaf)) {
        Set-Content -LiteralPath $script:CriteriaFile -Value "id`tdone`ttext"
    }
    if (-not (Test-Path -LiteralPath $script:EvidenceFile -PathType Leaf)) {
        Set-Content -LiteralPath $script:EvidenceFile -Value "id`tdate`tlocation`tnote"
    }
    if (-not (Test-Path -LiteralPath $script:PulseFile -PathType Leaf)) {
        Set-Content -LiteralPath $script:PulseFile -Value @()
    }
}

function Read-MetaHashtable {
    $meta = @{}
    foreach ($line in Get-Content -LiteralPath $script:MetaFile) {
        if ($line -match "^\s*([A-Z_]+)=(.*)\s*$") {
            $meta[$Matches[1]] = $Matches[2]
        }
    }
    return $meta
}

function Parse-IntOrDefault([hashtable]$Meta, [string]$Key, [int]$Default) {
    if (-not $Meta.ContainsKey($Key)) {
        return $Default
    }
    $parsed = 0
    if ([int]::TryParse($Meta[$Key], [ref]$parsed)) {
        return $parsed
    }
    return $Default
}

function Load-Meta {
    Require-PMDir
    if (-not (Test-Path -LiteralPath $script:MetaFile -PathType Leaf)) {
        throw "error: missing $script:MetaFile"
    }

    $meta = Read-MetaHashtable
    $script:NextTaskNum = Parse-IntOrDefault $meta "NEXT_TASK_NUM" 1
    $script:PulseTail = Parse-IntOrDefault $meta "PULSE_TAIL" 30
    $script:NextLimit = Parse-IntOrDefault $meta "NEXT_LIMIT" 20
    $script:EvidenceTail = Parse-IntOrDefault $meta "EVIDENCE_TAIL" 50
    $script:ContextEvidenceTail = Parse-IntOrDefault $meta "CONTEXT_EVIDENCE_TAIL" 10
    $script:BloatTicketThreshold = Parse-IntOrDefault $meta "BLOAT_TICKET_THRESHOLD" 50

    if ($script:NextTaskNum -lt 1) { $script:NextTaskNum = 1 }
    if ($script:PulseTail -lt 0) { $script:PulseTail = 30 }
    if ($script:NextLimit -lt 0) { $script:NextLimit = 20 }
    if ($script:EvidenceTail -lt 0) { $script:EvidenceTail = 50 }
    if ($script:ContextEvidenceTail -lt 0) { $script:ContextEvidenceTail = 10 }
    if ($script:BloatTicketThreshold -lt 0) { $script:BloatTicketThreshold = 50 }
}

function Save-Meta {
    $body = @(
        "NEXT_TASK_NUM=$script:NextTaskNum"
        "PULSE_TAIL=$script:PulseTail"
        "NEXT_LIMIT=$script:NextLimit"
        "EVIDENCE_TAIL=$script:EvidenceTail"
        "CONTEXT_EVIDENCE_TAIL=$script:ContextEvidenceTail"
        "BLOAT_TICKET_THRESHOLD=$script:BloatTicketThreshold"
    )
    Set-Content -LiteralPath $script:MetaFile -Value $body
}

function Append-Pulse([string]$TaskId, [string]$Event, [string]$Details) {
    $safeDetails = Sanitize $Details
    Add-Content -LiteralPath $script:PulseFile -Value "$(Get-NowTimestamp)|$TaskId|$Event|$safeDetails"
}

function Read-Tickets {
    if (-not (Test-Path -LiteralPath $script:TicketsFile -PathType Leaf)) {
        return @()
    }
    $lines = Get-Content -LiteralPath $script:TicketsFile
    if ($lines.Count -le 1) {
        return @()
    }
    $rows = @()
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -eq "") { continue }
        $parts = $lines[$i].Split("`t", 6)
        while ($parts.Count -lt 6) { $parts += "" }
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
    Set-Content -LiteralPath $script:TicketsFile -Value $out
}

function Read-Criteria {
    if (-not (Test-Path -LiteralPath $script:CriteriaFile -PathType Leaf)) {
        return @()
    }
    $lines = Get-Content -LiteralPath $script:CriteriaFile
    if ($lines.Count -le 1) {
        return @()
    }
    $rows = @()
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -eq "") { continue }
        $parts = $lines[$i].Split("`t", 3)
        while ($parts.Count -lt 3) { $parts += "" }
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
    Set-Content -LiteralPath $script:CriteriaFile -Value $out
}

function Read-Evidence {
    if (-not (Test-Path -LiteralPath $script:EvidenceFile -PathType Leaf)) {
        return @()
    }
    $lines = Get-Content -LiteralPath $script:EvidenceFile
    if ($lines.Count -le 1) {
        return @()
    }
    $rows = @()
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -eq "") { continue }
        $parts = $lines[$i].Split("`t", 4)
        while ($parts.Count -lt 4) { $parts += "" }
        $rows += [pscustomobject]@{
            id       = $parts[0]
            date     = $parts[1]
            location = $parts[2]
            note     = $parts[3]
        }
    }
    return $rows
}

function Read-ClaimsMap {
    $claims = @{}
    if (-not (Test-Path -LiteralPath $script:ClaimsFile -PathType Leaf)) {
        return $claims
    }
    $lines = Get-Content -LiteralPath $script:ClaimsFile
    if ($lines.Count -le 1) {
        return $claims
    }
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -eq "") { continue }
        $parts = $lines[$i].Split("`t", 4)
        while ($parts.Count -lt 4) { $parts += "" }
        if ($parts[0] -ne "") {
            $claims[$parts[0]] = $parts[1]
        }
    }
    return $claims
}

function Ticket-Exists([string]$TaskId) {
    $rows = Read-Tickets
    return ($rows | Where-Object { $_.id -eq $TaskId }).Count -gt 0
}

function Discover-Scopes {
    $scopesDir = Join-Path $PMRoot "scopes"
    if (-not (Test-Path -LiteralPath $scopesDir -PathType Container)) {
        return @()
    }
    $scopes = Get-ChildItem -LiteralPath $scopesDir -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name |
        ForEach-Object { $_.Name }
    if ($null -eq $scopes) {
        return @()
    }
    return @($scopes)
}

function Default-StatusOutputPath {
    $scopes = Discover-Scopes
    if ($scopes.Count -eq 0) {
        if ($script:Scope -eq "default") {
            return "status.md"
        }
        return "status.$script:Scope.md"
    }
    if ($scopes.Count -eq 1 -and $scopes[0] -eq "default" -and $script:Scope -eq "default") {
        return "status.md"
    }
    return "status.$script:Scope.md"
}

function Render-StatusIndex([string[]]$Scopes) {
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("# status.md")
    $lines.Add("## Scope Index")
    $lines.Add("")
    $lines.Add("Last updated: $(Get-NowDate)")
    $lines.Add("")
    $lines.Add("Multiple PM scopes are available. Open a scope snapshot:")
    $lines.Add("")

    foreach ($scopeName in $Scopes) {
        $snapshot = "status.$scopeName.md"
        if (Test-Path -LiteralPath $snapshot -PathType Leaf) {
            $lines.Add("- [$scopeName]($snapshot)")
        } else {
            $lines.Add("- $scopeName (missing snapshot: $snapshot)")
        }
    }

    $lines.Add("")
    $lines.Add("> Ledger roots: .pm/scopes/<scope>/")
    Set-Content -LiteralPath "status.md" -Value $lines
}

function Render-StatusIndexIfNeeded {
    $scopes = Discover-Scopes
    if ($scopes.Count -eq 0) {
        return
    }
    if ($scopes.Count -eq 1 -and $scopes[0] -eq "default") {
        return
    }
    Render-StatusIndex $scopes
}

function Cmd-Init {
    Ensure-BaseFiles
    if (-not (Test-Path -LiteralPath $script:MetaFile -PathType Leaf)) {
        $script:NextTaskNum = 1
        $script:PulseTail = 30
        $script:NextLimit = 20
        $script:EvidenceTail = 50
        $script:ContextEvidenceTail = 10
        $script:BloatTicketThreshold = 50
        Save-Meta
    }
    if (-not (Test-Path -LiteralPath $script:CoreFile -PathType Leaf)) {
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
'@ | Set-Content -LiteralPath $script:CoreFile
    }
    Append-Pulse "SYSTEM" "INIT" "Initialized scoped ledger ($script:Scope)"
    Cmd-Render
}

function Cmd-New([string]$StateInput, [string]$TitleInput, [string]$DepsInput = "") {
    Load-Meta
    Ensure-BaseFiles

    $state = Normalize-State $StateInput
    $title = Sanitize $TitleInput
    $deps = Sanitize $DepsInput
    $today = Get-NowDate
    $taskId = Format-TaskId $script:NextTaskNum

    Add-Content -LiteralPath $script:TicketsFile -Value "$taskId`t$state`t$title`t$deps`t$today`t$today"
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
    Add-Content -LiteralPath $script:CriteriaFile -Value "$TaskId`t0`t$safeText"
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
    Add-Content -LiteralPath $script:EvidenceFile -Value "$TaskId`t$(Get-NowDate)`t$safeLocation`t$safeNote"

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

function Render-StateSection(
    [array]$Rows,
    [string]$State,
    [int]$Limit,
    [hashtable]$ClaimsByTask,
    [string]$TicketHint,
    [System.Collections.Generic.List[string]]$OutLines
) {
    $OutLines.Add("### $(State-Heading $State)")
    $filtered = @($Rows | Where-Object { $_.state -eq $State })
    if ($filtered.Count -eq 0) {
        $OutLines.Add("- (none)")
        $OutLines.Add("")
        return
    }

    $shown = $filtered
    $hidden = 0
    if ($Limit -gt 0 -and $filtered.Count -gt $Limit) {
        $shown = @($filtered | Select-Object -First $Limit)
        $hidden = $filtered.Count - $Limit
    }

    foreach ($row in $shown) {
        $dep = ""
        if ($row.deps -ne "") {
            $dep = " (deps: $($row.deps))"
        }
        $claim = ""
        if ($State -ne "DONE" -and $ClaimsByTask.ContainsKey($row.id) -and $ClaimsByTask[$row.id] -ne "") {
            $claim = " (claimed: $($ClaimsByTask[$row.id]))"
        }
        $OutLines.Add("- [ ] $($row.id) - $($row.title)$dep$claim")
    }

    if ($hidden -gt 0) {
        $OutLines.Add("- ... +$hidden more (see $TicketHint)")
    }
    $OutLines.Add("")
}

function Cmd-Render([string]$OutPath = "") {
    Load-Meta

    $explicit = $OutPath -ne ""
    if (-not $explicit) {
        $OutPath = Default-StatusOutputPath
    }

    $nextTaskId = Format-TaskId $script:NextTaskNum
    $tickets = Read-Tickets
    $criteria = Read-Criteria
    $evidence = Read-Evidence
    $claimsByTask = Read-ClaimsMap

    $ticketHint = Scoped-RelPath "tickets.tsv"
    $evidenceHint = Scoped-RelPath "evidence.tsv"
    $pulseHint = Scoped-RelPath "pulse.log"
    $totalTickets = $tickets.Count

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("# status.md")
    $lines.Add("## Project Pulse")
    $lines.Add("")
    $lines.Add("Scope: $script:Scope")
    $lines.Add("Last updated: $(Get-NowDate)")
    $lines.Add("> Generated from $(Scoped-RelPath 'tickets.tsv'), $(Scoped-RelPath 'criteria.tsv'), $(Scoped-RelPath 'evidence.tsv'), and $(Scoped-RelPath 'pulse.log'); do not hand-edit.")
    $lines.Add("> Write policy: never edit status.md manually; use $(Get-RecommendedPmTicketCommand)")
    $lines.Add("> Bloat metric: $totalTickets tickets (threshold: $script:BloatTicketThreshold)")
    if ($script:BloatTicketThreshold -gt 0 -and $totalTickets -ge $script:BloatTicketThreshold) {
        $lines.Add("> Threshold reached: use pm-ticket CLI for updates.")
        $lines.Add("> Recommended command: $(Get-RecommendedPmTicketCommand)")
    }
    $lines.Add("")
    $lines.Add("---")
    $lines.Add("")

    if (Test-Path -LiteralPath $script:CoreFile -PathType Leaf) {
        foreach ($line in Get-Content -LiteralPath $script:CoreFile) {
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

    Render-StateSection $tickets "NOW" 0 $claimsByTask $ticketHint $lines
    Render-StateSection $tickets "IN_PROGRESS" 0 $claimsByTask $ticketHint $lines
    Render-StateSection $tickets "BLOCKED" 0 $claimsByTask $ticketHint $lines
    Render-StateSection $tickets "NEXT" $script:NextLimit $claimsByTask $ticketHint $lines

    if ($script:NextLimit -gt 0) {
        $lines.Add("> Next shows up to $script:NextLimit items; see $ticketHint for full backlog")
        $lines.Add("")
    }

    $lines.Add("---")
    $lines.Add("")
    $lines.Add("## Acceptance criteria (required for active tasks)")
    $lines.Add("")

    $active = @($tickets | Where-Object { $_.state -ne "DONE" })
    if ($active.Count -eq 0) {
        $lines.Add("_No active tasks_")
    } else {
        foreach ($task in $active) {
            $lines.Add("### $($task.id) acceptance criteria")
            $taskCriteria = @($criteria | Where-Object { $_.id -eq $task.id })
            if ($taskCriteria.Count -eq 0) {
                $lines.Add("- [ ] Add acceptance criteria")
            } else {
                foreach ($criterion in $taskCriteria) {
                    $mark = if ($criterion.done -eq "1") { "x" } else { " " }
                    $lines.Add("- [$mark] $($criterion.text)")
                }
            }
            $lines.Add("")
        }
    }

    $lines.Add("---")
    $lines.Add("")
    $lines.Add("## Evidence index (keep it navigable)")
    $lines.Add("> Source of truth: $evidenceHint")
    if ($script:EvidenceTail -gt 0) {
        $lines.Add("> Showing latest $script:EvidenceTail entries to keep status.md compact")
    }
    $lines.Add("")

    if ($evidence.Count -eq 0) {
        $lines.Add("- (none)")
    } else {
        $evidenceRows = @($evidence)
        $omittedEvidence = 0
        if ($script:EvidenceTail -gt 0 -and $evidence.Count -gt $script:EvidenceTail) {
            $evidenceRows = @($evidence | Select-Object -Last $script:EvidenceTail)
            $omittedEvidence = $evidence.Count - $script:EvidenceTail
        }
        foreach ($ev in $evidenceRows) {
            $note = ""
            if ($ev.note -ne "") {
                $note = " - $($ev.note)"
            }
            $lines.Add("- $($ev.id): $($ev.location) ($($ev.date))$note")
        }
        if ($omittedEvidence -gt 0) {
            $lines.Add("- ... +$omittedEvidence older entries (see $evidenceHint)")
        }
    }

    $lines.Add("")
    $lines.Add("---")
    $lines.Add("")
    $lines.Add("## Pulse Log (append-only)")
    $lines.Add("> Source of truth: $pulseHint (full history)")
    $lines.Add("> Showing latest $script:PulseTail entries to keep status.md compact")
    $lines.Add("")

    if (-not (Test-Path -LiteralPath $script:PulseFile -PathType Leaf)) {
        $lines.Add("- (no entries)")
    } else {
        $pulseLines = Get-Content -LiteralPath $script:PulseFile
        if ($pulseLines.Count -eq 0) {
            $lines.Add("- (no entries)")
        } else {
            $tail = $pulseLines | Select-Object -Last $script:PulseTail
            foreach ($entry in $tail) {
                $parts = $entry -split "\|", 4
                while ($parts.Count -lt 4) {
                    $parts += ""
                }
                $lines.Add("- $($parts[0]) | $($parts[1]) | $($parts[2]) | $($parts[3])")
            }
        }
    }

    Set-Content -LiteralPath $OutPath -Value $lines

    if (-not $explicit) {
        Render-StatusIndexIfNeeded
    }
}

function Cmd-RenderContext([string]$TaskId, [string]$EvidenceTailInput = "") {
    Load-Meta

    $tail = $script:ContextEvidenceTail
    if ($EvidenceTailInput -ne "") {
        $parsedTail = 0
        if (-not [int]::TryParse($EvidenceTailInput, [ref]$parsedTail) -or $parsedTail -lt 0) {
            throw "error: evidence-tail must be a non-negative integer"
        }
        $tail = $parsedTail
    }

    $task = Read-Tickets | Where-Object { $_.id -eq $TaskId } | Select-Object -First 1
    if ($null -eq $task) {
        throw "error: task not found: $TaskId"
    }

    $claims = Read-ClaimsMap
    $owner = if ($claims.ContainsKey($TaskId) -and $claims[$TaskId] -ne "") { $claims[$TaskId] } else { "" }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("# Context Pack")
    $lines.Add("")
    $lines.Add("Scope: $script:Scope")
    $lines.Add("Task ID: $($task.id)")
    $lines.Add("State: $($task.state)")
    $lines.Add("Title: $($task.title)")
    if ($task.deps -ne "") {
        $lines.Add("Dependencies: $($task.deps)")
    } else {
        $lines.Add("Dependencies: (none)")
    }
    if ($owner -ne "") {
        $lines.Add("Claimed by: $owner")
    } else {
        $lines.Add("Claimed by: (unclaimed)")
    }
    $lines.Add("Updated: $($task.updated)")
    $lines.Add("")

    $lines.Add("## Acceptance Criteria")
    $taskCriteria = @(Read-Criteria | Where-Object { $_.id -eq $TaskId })
    if ($taskCriteria.Count -eq 0) {
        $lines.Add("- [ ] Add acceptance criteria")
    } else {
        foreach ($criterion in $taskCriteria) {
            $mark = if ($criterion.done -eq "1") { "x" } else { " " }
            $lines.Add("- [$mark] $($criterion.text)")
        }
    }
    $lines.Add("")

    $lines.Add("## Latest Evidence")
    $taskEvidence = @(Read-Evidence | Where-Object { $_.id -eq $TaskId })
    if ($taskEvidence.Count -eq 0) {
        $lines.Add("- (none)")
    } else {
        $rows = $taskEvidence
        $omitted = 0
        if ($tail -gt 0 -and $taskEvidence.Count -gt $tail) {
            $rows = @($taskEvidence | Select-Object -Last $tail)
            $omitted = $taskEvidence.Count - $tail
        }
        foreach ($ev in $rows) {
            $note = ""
            if ($ev.note -ne "") {
                $note = " - $($ev.note)"
            }
            $lines.Add("- $($ev.id): $($ev.location) ($($ev.date))$note")
        }
        if ($omitted -gt 0) {
            $lines.Add("- ... +$omitted older entries (see $(Scoped-RelPath 'evidence.tsv'))")
        }
    }
    $lines.Add("")

    $lines.Add("## Paths")
    $lines.Add("- Tickets: $(Scoped-RelPath 'tickets.tsv')")
    $lines.Add("- Criteria: $(Scoped-RelPath 'criteria.tsv')")
    $lines.Add("- Evidence: $(Scoped-RelPath 'evidence.tsv')")
    $lines.Add("- Pulse: $(Scoped-RelPath 'pulse.log')")
    if (Test-Path -LiteralPath $script:ClaimsFile -PathType Leaf) {
        $lines.Add("- Claims: $(Scoped-RelPath 'claims.tsv')")
    }

    $lines | Write-Output
}

function Cmd-NextId {
    Load-Meta
    Write-Output (Format-TaskId $script:NextTaskNum)
}

$remainingArgs = Parse-GlobalOptions $args
Set-ScopePaths
Migrate-LegacyDefaultScope

if ($remainingArgs.Count -lt 1) {
    Write-Usage
    exit 1
}

$command = $remainingArgs[0]
$rest = @()
if ($remainingArgs.Count -gt 1) {
    $rest = $remainingArgs[1..($remainingArgs.Count - 1)]
}

try {
    switch ($command) {
        "init" {
            Cmd-Init
        }
        "new" {
            if ($rest.Count -lt 2) { throw "error: new requires <state> and <title>" }
            $deps = if ($rest.Count -ge 3) { $rest[2] } else { "" }
            Cmd-New $rest[0] $rest[1] $deps
        }
        "move" {
            if ($rest.Count -lt 2) { throw "error: move requires <id> and <state>" }
            $note = if ($rest.Count -ge 3) { $rest[2] } else { "" }
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
            $note = if ($rest.Count -ge 3) { $rest[2] } else { "" }
            Cmd-Evidence $rest[0] $rest[1] $note
        }
        "done" {
            if ($rest.Count -lt 2) { throw "error: done requires <id> and <path-or-link>" }
            $note = if ($rest.Count -ge 3) { $rest[2] } else { "" }
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
        "render-context" {
            if ($rest.Count -lt 1) { throw "error: render-context requires <task-id>" }
            $tail = if ($rest.Count -ge 2) { $rest[1] } else { "" }
            Cmd-RenderContext $rest[0] $tail
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
