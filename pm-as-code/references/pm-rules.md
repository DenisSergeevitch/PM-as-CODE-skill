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

## Non-negotiables

- Keep all work items as checkboxes:
  - `- [ ]` not done
  - `- [x]` done
- Keep no hidden tasks in prose. If it is actionable, represent it as a checkbox.
- Give every task an ID and reference tasks by ID everywhere.
- Keep `status.md` in repo root.
- Keep `status.md` alive by updating it every task completion.
- Keep Pulse Log append-only. Never delete or rewrite prior entries.
- Resolve uncertainty by recording updates in docs, not by chat memory.

## Canon and Scope

- Treat `status.md` as canonical project truth.
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
1. Read next ID from counter.
2. Increment counter immediately.
3. Add task checkbox in `status.md`.

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
3. If missing, create new task, add acceptance criteria, and place in `Now` or `Next`.

While working:
- Keep changes factual and structured.
- Add new task IDs immediately for discovered work.
- Move blocked tasks to `Blocked` and record explicit blocker reason.

Finish task:
1. Mark task `[x]`.
2. Mark acceptance criteria `[x]`.
3. Add evidence.
4. Update state lists.
5. Append Pulse Log entry.

## Append-Only Rule

- Never remove or rewrite old Pulse Log entries.
- If prior entry was wrong, append a correcting entry.
- You may refine CORE context wording, but preserve historical truth in Pulse Log.

## Compact Ledger Mode

Use compact mode for long-running projects when `status.md` becomes too large.

Rules:
- Keep source-of-truth state in `.pm/`:
  - `.pm/tickets.tsv`
  - `.pm/criteria.tsv`
  - `.pm/evidence.tsv`
  - `.pm/pulse.log`
- Keep `.pm/pulse.log` append-only and never rewrite historical entries.
- Render `status.md` from ledger state after task changes.
- Keep `status.md` concise by showing recent pulse entries while linking `.pm/pulse.log` as full history.
- Use `scripts/pm-ticket.sh` (Bash) or `scripts/pm-ticket.ps1` / `scripts/pm-ticket.cmd` (Windows) for all ledger operations to keep format stable.
