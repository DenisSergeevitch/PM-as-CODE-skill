# Compact Ticket System (No Dependencies)

Use this as the default write path for all project updates.
Read `status.md`, but never edit it manually.

## What It Stores

- `.pm/scopes/<scope>/meta.env`: counters and render settings.
- `.pm/scopes/<scope>/core.md`: stable core context block.
- `.pm/scopes/<scope>/tickets.tsv`: task ID, state, title, deps, timestamps.
- `.pm/scopes/<scope>/criteria.tsv`: acceptance criteria by task ID.
- `.pm/scopes/<scope>/evidence.tsv`: completion evidence records.
- `.pm/scopes/<scope>/pulse.log`: append-only event log.
- `.pm/scopes/<scope>/claims.tsv` (optional): claim ownership in multi-agent mode.
- `status.md` plus `status.<scope>.md`: rendered snapshots/index.

`status.md` remains the human entrypoint. `.pm/scopes/<scope>/*` is the machine system of record.
All mutations must go through `scripts/pm-ticket.*` or `scripts/pm-collab.*`, then render snapshots.

## Scope / Team Namespace

Use a scope for each team/swarm lane:

- CLI: `--scope <name>`
- Env fallback: `PM_SCOPE=<name>`
- Default when omitted: `default`

Scope data lives in `.pm/scopes/<scope>/...`.

Rendering behavior:

- Only `default` scope exists: `status.md` is the full snapshot.
- Multiple scopes or non-default-only scopes: `status.md` is a compact index linking to `status.<scope>.md`.
- Rendered snapshots include a generated banner; do not hand-edit.

## Render Bounds

Configure these keys in `.pm/scopes/<scope>/meta.env`:

- `NEXT_LIMIT` (default `20`): max `Next` items shown in `status.md`
- `EVIDENCE_TAIL` (default `50`): max recent evidence lines shown
- `PULSE_TAIL` (default `30`): max recent pulse lines shown
- `BLOAT_TICKET_THRESHOLD` (default `50`): when total tickets reach this count, rendered header adds a CLI warning and recommended OS command

Set a value to `0` to disable that limit.

## Commands

macOS/Linux (Bash):

```bash
scripts/pm-ticket.sh init
scripts/pm-ticket.sh new next "Implement OAuth callback flow"
scripts/pm-ticket.sh criterion-add T-0001 "Callback route validates state"
scripts/pm-ticket.sh move T-0001 in-progress
scripts/pm-ticket.sh criterion-check T-0001 1
scripts/pm-ticket.sh evidence T-0001 "src/auth/callback.ts" "state validation added"
scripts/pm-ticket.sh done T-0001 "src/auth/callback.ts" "manual test passed"
scripts/pm-ticket.sh render status.md
```

Scoped Bash example:

```bash
scripts/pm-ticket.sh --scope backend init
scripts/pm-ticket.sh --scope backend new next "Implement OAuth callback flow"
scripts/pm-ticket.sh --scope backend render
scripts/pm-ticket.sh --scope backend render-context T-0001 8
```

Scoped PowerShell example:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\pm-ticket.ps1 --scope backend init
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\pm-ticket.ps1 --scope backend new next "Implement OAuth callback flow"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\pm-ticket.ps1 --scope backend render
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\pm-ticket.ps1 --scope backend render-context T-0001 8
```

Windows (PowerShell):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\pm-ticket.ps1 init
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\pm-ticket.ps1 new next "Implement OAuth callback flow"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\pm-ticket.ps1 criterion-add T-0001 "Callback route validates state"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\pm-ticket.ps1 move T-0001 in-progress
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\pm-ticket.ps1 criterion-check T-0001 1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\pm-ticket.ps1 evidence T-0001 "src\auth\callback.ts" "state validation added"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\pm-ticket.ps1 done T-0001 "src\auth\callback.ts" "manual test passed"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\pm-ticket.ps1 render status.md
```

Windows (CMD wrapper):

```cmd
scripts\pm-ticket.cmd init
scripts\pm-ticket.cmd new next "Implement OAuth callback flow"
scripts\pm-ticket.cmd criterion-add T-0001 "Callback route validates state"
scripts\pm-ticket.cmd move T-0001 in-progress
scripts\pm-ticket.cmd criterion-check T-0001 1
scripts\pm-ticket.cmd evidence T-0001 "src\auth\callback.ts" "state validation added"
scripts\pm-ticket.cmd done T-0001 "src\auth\callback.ts" "manual test passed"
scripts\pm-ticket.cmd render status.md
```

## Multi-Agent Commands (No Git)

Use these when two or more agents share the same filesystem workspace.

macOS/Linux (Bash):

```bash
scripts/pm-collab.sh init
scripts/pm-collab.sh claim agent-a T-0001 "API work"
scripts/pm-collab.sh run agent-a -- move T-0001 in-progress
scripts/pm-collab.sh run agent-a -- criterion-check T-0001 1
scripts/pm-collab.sh run agent-a -- done T-0001 "src/api/auth.ts" "tests passed"
scripts/pm-collab.sh claims
scripts/pm-collab.sh unclaim agent-a T-0001
```

Windows (PowerShell):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\pm-collab.ps1 init
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\pm-collab.ps1 claim agent-a T-0001 "API work"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\pm-collab.ps1 run agent-a -- move T-0001 in-progress
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\pm-collab.ps1 run agent-a -- criterion-check T-0001 1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\pm-collab.ps1 run agent-a -- done T-0001 "src\api\auth.ts" "tests passed"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\pm-collab.ps1 claims
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\pm-collab.ps1 unclaim agent-a T-0001
```

Windows (CMD wrapper):

```cmd
scripts\pm-collab.cmd init
scripts\pm-collab.cmd claim agent-a T-0001 "API work"
scripts\pm-collab.cmd run agent-a -- move T-0001 in-progress
scripts\pm-collab.cmd run agent-a -- criterion-check T-0001 1
scripts\pm-collab.cmd run agent-a -- done T-0001 "src\api\auth.ts" "tests passed"
scripts\pm-collab.cmd claims
scripts\pm-collab.cmd unclaim agent-a T-0001
```

## States

- `now`
- `in-progress`
- `blocked`
- `next`
- `done`

## Recommended Workflow

1. Initialize once with `init`.
2. Create tasks with `new`.
3. Add acceptance criteria immediately.
4. Update state with `move`.
5. Record evidence and close with `done`.
6. Re-render `status.md` after task changes.
7. Use `render-context` for bounded teammate handoffs per task.

## Recommended Workflow (Multi-Agent, No Git)

1. Initialize with `scripts/pm-collab.sh init` or `scripts\pm-collab.cmd init`.
2. Each agent claims one task before modifying it.
3. Each agent performs write operations through `scripts/pm-collab.sh run <agent> -- ...` or `scripts\pm-collab.cmd run <agent> -- ...`.
4. Keep tasks exclusive by claim owner to avoid duplicate work.
5. Complete with `done` (claim is auto-released) or manually `unclaim`.

## Why This Saves Context

- `status.md` stays small and scannable.
- Full history stays in scoped `.pm/scopes/<scope>/pulse.log`.
- Structured TSV files avoid verbose prose growth.

## Why Multi-Agent Mode Works

- Serializes write operations with a scoped lock (`.pm/scopes/<scope>/.collab-lock`).
- Prevents conflicting edits by enforcing per-task claims.
- Keeps coordination data in `.pm/scopes/<scope>/claims.tsv` and scoped Pulse Log.
- Renderer annotates claimed tasks (for non-DONE states) to reduce duplicate work.
