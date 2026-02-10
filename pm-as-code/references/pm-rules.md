# PM-as-Code Rules

## Table of Contents

- [Non-negotiables](#non-negotiables)
- [Canon and Scope](#canon-and-scope)
- [ID System](#id-system)
- [Task Standard](#task-standard)
- [Required status.md Sections](#required-statusmd-sections)
- [Mandatory Update Rule](#mandatory-update-rule)
- [Session Protocol](#session-protocol)
- [Append-Only Rule](#append-only-rule)
- [Compact Ledger Mode](#compact-ledger-mode)
- [Concurrency Policy](#concurrency-policy)

## Non-negotiables

- Keep all work items as checkboxes:
  - `- [ ]` not done
  - `- [x]` done
- Keep no hidden tasks in prose. If it is actionable, represent it as a checkbox.
- Give every task an ID and reference tasks by ID everywhere.
- Keep `status.md` in repo root.
- Treat `status.md` as a rendered snapshot; do not hand-edit it.
- Keep `status.md` alive by re-rendering it after task completion.
- Keep Pulse Log append-only. Never delete or rewrite prior entries.
- Resolve uncertainty by recording updates in docs, not by chat memory.
- Route all state writes through `scripts/pm-ticket.*` (single-agent) or `scripts/pm-collab.*` (multi-agent).

## Canon and Scope

- Treat `status.md` as the canonical human entrypoint and session snapshot.
- Keep optional docs linked from `status.md` when used.
- Keep optional docs consistent with `status.md`; resolve contradictions immediately.

Optional docs when project scale requires:
- `backlog.md`
- `decisions/ADR-xxxx.md`
- `risks.md`
- `notes/`

## ID System

- Tasks: `T-0001`, `T-0002`, ...
- Optional epics: `E-01`, `E-02`, ...
- Optional decisions: `ADR-0001`, `ADR-0002`, ...
- Optional risks: `RISK-01`, `RISK-02`, ...

Keep counters in `status.md`:
- `Next Task ID: T-00xx`
- Optional: `Next ADR ID: ADR-00xx`
- Optional: `Next Risk ID: RISK-xx`

Issue IDs strictly:
1. Use `scripts/pm-ticket.* next-id` or `new` to allocate from counter.
2. Persist counter updates via script command.
3. Render `status.md` from ledger after changes.

## Task Standard

Task line format:
- `[ ] T-0007 - <one-line outcome>`

Allowed short suffixes:
- owner, due date, dependencies, links

Definition of Ready:
- one-line outcome exists
- acceptance criteria exist
- dependencies are noted if relevant

Definition of Done:
- task checkbox is `[x]`
- acceptance criteria are `[x]`
- evidence is recorded
- current state lists are updated
- Pulse Log entry is appended

## Required status.md Sections

Keep these sections in this exact order:
1. Header + Last updated
2. CORE context
3. Current state (`Now`, `In progress`, `Blocked`, `Next`)
4. Acceptance criteria (for active tasks)
5. Evidence index
6. Pulse Log (append-only)

## Mandatory Update Rule

Every time a task is finished:
- mark task `[x]`
- check acceptance criteria `[x]`
- add evidence
- update `Now / In progress / Blocked / Next`
- append Pulse Log entry

No exceptions.

## Session Protocol

Start of session:
1. Read `status.md` first.
2. Confirm objective clarity, `Now` accuracy, and at least one active task ID.
3. Ensure scope is initialized via `scripts/pm-ticket.* init`.
4. If missing, create new task, add acceptance criteria, and place in `Now` or `Next` via script command.

While working:
- Keep changes factual and structured.
- Add new task IDs immediately for discovered work via script command.
- Move blocked tasks to `Blocked` and record explicit blocker reason via script command.

Finish task:
1. Mark task `[x]` via script command.
2. Mark acceptance criteria `[x]` via script command.
3. Add evidence via script command.
4. Update state lists via script command.
5. Append Pulse Log entry via script command.
6. Render `status.md` via script.

## Append-Only Rule

- Never remove or rewrite old Pulse Log entries.
- If prior entry was wrong, append a correcting entry.
- You may refine CORE context wording, but preserve historical truth in Pulse Log.

## Compact Ledger Mode

Use compact ledger mode as the default workflow.

Rules:
- Keep source-of-truth state in `.pm/scopes/<scope>/`:
  - `tickets.tsv`
  - `criteria.tsv`
  - `evidence.tsv`
  - `pulse.log`
- In ledger mode, `.pm/scopes/<scope>/*` is the machine system of record and `status.md` is rendered from it.
- Keep `.pm/scopes/<scope>/pulse.log` append-only and never rewrite historical entries.
- Render `status.md` from ledger state after task changes.
- Keep `status.md` concise by showing recent pulse entries while linking scoped pulse logs as full history.
- Configure bounded rendering in `.pm/scopes/<scope>/meta.env`:
  - `NEXT_LIMIT` (default 20)
  - `EVIDENCE_TAIL` (default 50)
  - `PULSE_TAIL` (default 30)
- Use scope selection (`--scope` or `PM_SCOPE`) to isolate teams/swarm lanes.
- Use `scripts/pm-ticket.sh` (Bash) or `scripts/pm-ticket.ps1` / `scripts/pm-ticket.cmd` (Windows) for all ledger operations to keep format stable.
- For multi-agent locking, use `scripts/pm-collab.sh` (Bash) or `scripts/pm-collab.ps1` / `scripts/pm-collab.cmd` (Windows).
- Generated snapshots must not be hand-edited; use ticket/collab scripts and re-render.

## Concurrency Policy

For concurrent updates, default to no-confirm auto-merge behavior:
- Never write directly to `status.md`.
- Execute mutations through `pm-collab ... run` so lock + claim serialize writes.
- Re-render after updates and continue without confirmation prompts for non-conflicting work.

Escalate only for same-task ambiguity:
- target ID missing
- duplicated ID
- target criteria block cannot be mapped safely

When escalated:
- create `Resolve status conflict for <ID>` task
- move original task to `Blocked` with explicit blocker note
