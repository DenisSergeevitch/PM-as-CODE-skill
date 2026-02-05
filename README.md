# skills-i-use

My favorite coding-agent skills, versioned in one repo.

## Included skills

### `pm-as-code`
Project-management workflow for coding agents with:
- `status.md` as the single source of truth
- ticket IDs like `T-0001`
- acceptance criteria tracking
- append-only pulse log updates
- multi-agent no-Git mode via `scripts/pm-collab.sh` (lock + task claims)

Main file: `pm-as-code/SKILL.md`

## Install to Codex

```bash
git clone https://github.com/DenisSergeevitch/skills-i-use.git /tmp/skills-i-use && mkdir -p /Users/pro16/.codex/skills/ && cp -R /tmp/skills-i-use/pm-as-code /Users/pro16/.codex/skills/
```

## Install to Claude

```bash
git clone https://github.com/DenisSergeevitch/skills-i-use.git /tmp/skills-i-use && mkdir -p /Users/pro16/.claude/skills/ && cp -R /tmp/skills-i-use/pm-as-code /Users/pro16/.claude/skills/
```

## Update later

```bash
cd /tmp/skills-i-use
git pull
cp -R /tmp/skills-i-use/pm-as-code /Users/pro16/.codex/skills/
cp -R /tmp/skills-i-use/pm-as-code /Users/pro16/.claude/skills/
```
