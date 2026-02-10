# status.md Template (Required)

## Table of Contents

- [status.md Template (Required)](#statusmd-template-required)
- [Completion rule](#completion-rule)

Use this as the required rendered structure for `/status.md` in repo root.
`status.md` should be produced by `scripts/pm-ticket.* render`, not hand-edited.

```md
# status.md
## Project Pulse

Last updated: YYYY-MM-DD

---

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

### Counters
- Next Task ID: T-0001
- (Optional) Next ADR ID: ADR-0001
- (Optional) Next Risk ID: RISK-01

---

## Current state (always keep accurate)

### Now (top priorities)
- [ ] T-0001 - <one-line outcome>
- [ ] T-0002 - <one-line outcome>

### In progress
- [ ] T-0003 - <one-line outcome> (started: YYYY-MM-DD)

### Blocked
- [ ] T-0004 - <one-line outcome> (blocked by: <what/why>)

### Next
- [ ] T-0005 - <one-line outcome>
- [ ] T-0006 - <one-line outcome>

---

## Acceptance criteria (required for active tasks)

### T-0001 acceptance criteria
- [ ] <criterion 1>
- [ ] <criterion 2>

### T-0002 acceptance criteria
- [ ] <criterion 1>

---

## Evidence index (keep it navigable)
> Add evidence when tasks are completed. Use links or precise paths.

- T-0001: <link or path + short note>
- T-0002: <link or path + short note>

---

## Pulse Log (append-only)
> RULE: Append a new entry EVERY time a task is finished.
> Keep it factual. Do not rewrite old entries.

### YYYY-MM-DD - Completed T-0000: <short title>
Completed:
- [x] T-0000 - <one-line outcome>

Acceptance criteria met:
- [x] <criterion 1>
- [x] <criterion 2>

Evidence:
- <link or precise path>

State changes:
- Now: <what moved in/out>
- Next: <what became next>

Blockers:
- <none> OR <what is blocked now>

Notes:
- <short, durable notes only>
```

Completion rule:
- keep section order unchanged
- append Pulse entries only
- run `scripts/pm-ticket.* render` after task updates
