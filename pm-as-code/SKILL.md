---
name: pm-as-code
description: Strict Markdown project management with status.md as canonical truth, checkbox-only work items, task IDs, acceptance criteria, evidence tracking, and append-only pulse history. Includes a no-dependency Bash ticket ledger for long-running repos to keep status.md compact. Use when maintaining repo order, managing execution state across sessions, or replacing chat-memory planning with durable project docs.
---

# PM as Code

## Overview

Use `status.md` at repo root as the default project truth. Keep every actionable as a checkbox task with an ID so work state survives sessions without relying on chat memory.

For long-running projects, prefer compact ledger mode:
- store full machine-readable history in `.pm/*` files
- render `status.md` as a compact snapshot from ledger state
- keep full pulse history append-only in `.pm/pulse.log`
- for multi-agent/no-Git setups, serialize writes with `scripts/pm-collab.sh`

## Run Session Protocol

1. Read `status.md` first.
2. Confirm objective clarity, `Now` accuracy, and at least one active task ID.
3. If missing, issue the next task ID, increment the counter, add the task, and add acceptance criteria.
4. Keep discoveries explicit by creating new task IDs immediately.
5. Move blocked work to `Blocked` with the blocker written explicitly.
6. Close tasks only with the completion checklist in this file.

## Enforce Non-Negotiables

- Keep all actionables as checkboxes: `- [ ]` or `- [x]`.
- Keep no hidden tasks in paragraphs.
- Give every task an ID and refer to tasks by ID everywhere.
- Keep `status.md` in repo root.
- Keep Pulse Log append-only; never rewrite history.
- Resolve ambiguity by updating docs, not by memory.

## Keep Required status.md Layout

Maintain sections in this exact order:
1. Header + Last updated
2. CORE context
3. Current state (`Now`, `In progress`, `Blocked`, `Next`)
4. Acceptance criteria
5. Evidence index
6. Pulse Log (append-only)

Use `references/status-template.md` when bootstrapping or repairing structure.

## Use Strict ID Issuance

- Task IDs: `T-0001`, `T-0002`, ...
- Optional IDs: epics `E-01`, decisions `ADR-0001`, risks `RISK-01`
- Keep counters in `status.md`:
  - `Next Task ID: T-00xx`
  - optional `Next ADR ID: ADR-00xx`
  - optional `Next Risk ID: RISK-xx`
- On task creation: consume the next ID, increment counter immediately, then add task checkbox.

## Enforce Ready/Done Gates

Ready gate:
- Keep a one-line outcome.
- Keep acceptance criteria keyed by task ID.
- Record dependencies when present.

Done gate:
- Mark task checkbox `[x]`.
- Mark acceptance criteria `[x]`.
- Add evidence (path or link plus short note).
- Update `Now`, `In progress`, `Blocked`, and `Next`.
- Append a Pulse Log entry.

Use this closeout checklist every completion:
- [ ] Mark task done.
- [ ] Mark criteria done.
- [ ] Add evidence.
- [ ] Update state lists.
- [ ] Append Pulse Log entry.

## Manage Optional Docs

Create optional docs only when scale requires them:
- `backlog.md`
- `decisions/ADR-xxxx.md`
- `risks.md`
- `notes/`

Keep them consistent with `status.md`. If any contradiction appears, fix immediately.

Use `references/optional-doc-templates.md` for file templates.

## Use Compact Ledger Mode (No Dependencies)

Use platform-native ticket scripts when `status.md` growth starts harming context:
- Bash: `scripts/pm-ticket.sh`
- PowerShell: `scripts/pm-ticket.ps1`
- CMD wrapper: `scripts/pm-ticket.cmd`

Typical flow:
1. `scripts/pm-ticket.sh init`
2. `scripts/pm-ticket.sh new next "Define authentication boundaries"`
3. `scripts/pm-ticket.sh criterion-add T-0001 "Document API auth requirements"`
4. `scripts/pm-ticket.sh move T-0001 in-progress`
5. `scripts/pm-ticket.sh done T-0001 "docs/auth.md" "Reviewed with team"`
6. `scripts/pm-ticket.sh render status.md`

Windows flow:
1. `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\pm-ticket.ps1 init`
2. `scripts\pm-ticket.cmd new next "Define authentication boundaries"`
3. `scripts\pm-ticket.cmd criterion-add T-0001 "Document API auth requirements"`
4. `scripts\pm-ticket.cmd move T-0001 in-progress`
5. `scripts\pm-ticket.cmd done T-0001 "docs\auth.md" "Reviewed with team"`
6. `scripts\pm-ticket.cmd render status.md`

Compact mode rules:
- Treat `.pm/pulse.log` as full append-only history.
- Treat `.pm/tickets.tsv`, `.pm/criteria.tsv`, and `.pm/evidence.tsv` as source data.
- Treat rendered `status.md` as canonical human snapshot.
- Re-render after each meaningful task update.

## Use Multi-Agent Mode (No Git Required)

When multiple agents share one working directory, do not edit `status.md` directly.
Use lock + claim workflow via `scripts/pm-collab.sh`.

1. Initialize once:
   - `scripts/pm-collab.sh init`
2. Claim before changing a task:
   - `scripts/pm-collab.sh claim agent-a T-0003 "working on auth"`
3. Run all write commands through the lock wrapper:
   - `scripts/pm-collab.sh run agent-a -- move T-0003 in-progress`
   - `scripts/pm-collab.sh run agent-a -- criterion-check T-0003 1`
   - `scripts/pm-collab.sh run agent-a -- done T-0003 "src/auth.ts" "tests passed"`
4. Release if unfinished:
   - `scripts/pm-collab.sh unclaim agent-a T-0003`

Rules:
- One task can be claimed by only one agent at a time.
- `run` rejects task mutations when the task is unclaimed or claimed by another agent.
- Writes are serialized with a lock to avoid race conditions in `.pm/*` and `status.md`.
- `done` auto-releases the claim.

## Reference Files

- `references/pm-rules.md`: Full strict policy and session protocol.
- `references/status-template.md`: Required root `status.md` template.
- `references/optional-doc-templates.md`: Optional `backlog.md`, ADR, and `risks.md` templates.
- `references/compact-ticket-system.md`: No-dependency Bash ticket ledger and command reference.
- `scripts/pm-collab.sh`: Locking and claim wrapper for multi-agent/no-Git collaboration.
