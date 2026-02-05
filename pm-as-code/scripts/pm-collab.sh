#!/usr/bin/env bash
set -euo pipefail

PM_DIR=".pm"
LOCK_DIR="$PM_DIR/.collab-lock"
LOCK_INFO="$LOCK_DIR/lock.env"
CLAIMS_FILE="$PM_DIR/claims.tsv"
PULSE_FILE="$PM_DIR/pulse.log"

LOCK_WAIT_SECONDS="${PM_LOCK_WAIT_SECONDS:-120}"
LOCK_STALE_SECONDS="${PM_LOCK_STALE_SECONDS:-900}"
LOCK_POLL_SECONDS="${PM_LOCK_POLL_SECONDS:-1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PM_TICKET="$SCRIPT_DIR/pm-ticket.sh"
LOCK_TOKEN=""

usage() {
  cat <<'EOF'
Usage:
  pm-collab.sh init
  pm-collab.sh claim <agent> <T-0001> [note]
  pm-collab.sh unclaim <agent> <T-0001>
  pm-collab.sh claims
  pm-collab.sh run <agent> -- <pm-ticket command...>
  pm-collab.sh lock-info
  pm-collab.sh unlock-stale

Examples:
  scripts/pm-collab.sh init
  scripts/pm-collab.sh claim agent-a T-0001 "taking API task"
  scripts/pm-collab.sh run agent-a -- move T-0001 in-progress
  scripts/pm-collab.sh run agent-a -- done T-0001 "src/api/auth.ts" "tests passed"
EOF
}

now_ts() {
  date "+%F %T"
}

sanitize() {
  local s="${1:-}"
  s="${s//$'\t'/ }"
  s="${s//$'\n'/ }"
  printf '%s' "$s"
}

require_pm_ticket() {
  if [[ ! -x "$PM_TICKET" ]]; then
    echo "error: missing executable $PM_TICKET" >&2
    exit 1
  fi
}

stat_mtime() {
  local path="$1"
  if stat -f %m "$path" >/dev/null 2>&1; then
    stat -f %m "$path"
  else
    stat -c %Y "$path"
  fi
}

read_lock_field() {
  local key="$1"
  [[ -f "$LOCK_INFO" ]] || return 1
  awk -F'=' -v k="$key" '$1 == k { print substr($0, index($0, "=") + 1); exit }' "$LOCK_INFO"
}

lock_age_seconds() {
  local mtime now
  mtime="$(stat_mtime "$LOCK_DIR" 2>/dev/null || true)"
  [[ -n "$mtime" ]] || {
    echo 0
    return
  }
  now="$(date +%s)"
  echo $((now - mtime))
}

remove_lock_dir() {
  rm -f "$LOCK_INFO" 2>/dev/null || true
  rmdir "$LOCK_DIR" 2>/dev/null || rm -rf "$LOCK_DIR"
}

lock_is_stale() {
  [[ -d "$LOCK_DIR" ]] || return 1

  local host pid current_host age
  host="$(read_lock_field host || true)"
  pid="$(read_lock_field pid || true)"
  current_host="$(hostname)"

  if [[ -n "$pid" && -n "$host" && "$host" == "$current_host" ]]; then
    if kill -0 "$pid" 2>/dev/null; then
      return 1
    fi
  fi

  age="$(lock_age_seconds)"
  ((age >= LOCK_STALE_SECONDS))
}

release_lock() {
  if [[ -z "$LOCK_TOKEN" ]]; then
    return
  fi
  if [[ -d "$LOCK_DIR" ]]; then
    local token
    token="$(read_lock_field token || true)"
    if [[ -n "$token" && "$token" == "$LOCK_TOKEN" ]]; then
      remove_lock_dir
    fi
  fi
  LOCK_TOKEN=""
  trap - EXIT INT TERM
}

acquire_lock() {
  local agent="$1"
  local now deadline

  mkdir -p "$PM_DIR"
  deadline=$(( $(date +%s) + LOCK_WAIT_SECONDS ))

  while true; do
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      LOCK_TOKEN="$(date +%s)-$$-${RANDOM}"
      cat >"$LOCK_INFO" <<EOF
agent=$agent
pid=$$
host=$(hostname)
token=$LOCK_TOKEN
started=$(now_ts)
EOF
      trap release_lock EXIT INT TERM
      return 0
    fi

    if lock_is_stale; then
      echo "warn: removing stale lock (age $(lock_age_seconds)s)" >&2
      remove_lock_dir
      continue
    fi

    now="$(date +%s)"
    if ((now >= deadline)); then
      echo "error: lock timeout after ${LOCK_WAIT_SECONDS}s" >&2
      echo "lock owner: $(read_lock_field agent || echo unknown)" >&2
      echo "lock host: $(read_lock_field host || echo unknown)" >&2
      echo "lock pid: $(read_lock_field pid || echo unknown)" >&2
      echo "lock started: $(read_lock_field started || echo unknown)" >&2
      return 1
    fi

    sleep "$LOCK_POLL_SECONDS"
  done
}

append_pulse() {
  local task_id="$1"
  local event="$2"
  local details
  details="$(sanitize "${3:-}")"
  printf '%s|%s|%s|%s\n' "$(now_ts)" "$task_id" "$event" "$details" >>"$PULSE_FILE"
}

ensure_pm_initialized() {
  if [[ ! -f "$PM_DIR/tickets.tsv" ]]; then
    echo "error: .pm not initialized. Run: scripts/pm-collab.sh init" >&2
    exit 1
  fi
}

ensure_claims_file() {
  mkdir -p "$PM_DIR"
  if [[ ! -f "$CLAIMS_FILE" ]]; then
    printf 'id\tagent\tclaimed_at\tnote\n' >"$CLAIMS_FILE"
  fi
}

ticket_exists() {
  local task_id="$1"
  awk -F'\t' -v id="$task_id" 'NR > 1 && $1 == id { found=1 } END { exit(found ? 0 : 1) }' "$PM_DIR/tickets.tsv"
}

ticket_state() {
  local task_id="$1"
  awk -F'\t' -v id="$task_id" 'NR > 1 && $1 == id { print $2; found=1; exit } END { if (!found) exit 1 }' "$PM_DIR/tickets.tsv"
}

claim_owner() {
  local task_id="$1"
  awk -F'\t' -v id="$task_id" 'NR > 1 && $1 == id { print $2; exit }' "$CLAIMS_FILE"
}

remove_claim() {
  local task_id="$1"
  local tmp
  tmp="$(mktemp)"
  awk -F'\t' -v OFS='\t' -v id="$task_id" 'NR == 1 || $1 != id { print }' "$CLAIMS_FILE" >"$tmp"
  mv "$tmp" "$CLAIMS_FILE"
}

task_id_from_pm_command() {
  local pm_cmd="${1:-}"
  local maybe_id="${2:-}"
  case "$pm_cmd" in
    move|criterion-add|criterion-check|evidence|done)
      printf '%s' "$maybe_id"
      ;;
    *)
      ;;
  esac
}

is_mutating_pm_command() {
  case "${1:-}" in
    init|new|move|criterion-add|criterion-check|evidence|done|render)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

ensure_task_claimed_by_agent() {
  local agent="$1"
  local task_id="$2"
  local owner

  owner="$(claim_owner "$task_id" || true)"
  if [[ -z "$owner" ]]; then
    echo "error: $task_id is not claimed. Run: scripts/pm-collab.sh claim $agent $task_id" >&2
    exit 1
  fi
  if [[ "$owner" != "$agent" ]]; then
    echo "error: $task_id is claimed by '$owner' (agent '$agent' cannot modify it)" >&2
    exit 1
  fi
}

cmd_init() {
  acquire_lock "SYSTEM"
  "$PM_TICKET" init
  ensure_claims_file
  append_pulse "SYSTEM" "COLLAB_INIT" "collab lock and claims enabled"
  "$PM_TICKET" render status.md
}

cmd_claim() {
  local agent="$1"
  local task_id="$2"
  local note
  local owner state

  note="$(sanitize "${3:-}")"
  acquire_lock "$agent"
  ensure_pm_initialized
  ensure_claims_file

  if ! ticket_exists "$task_id"; then
    echo "error: task not found: $task_id" >&2
    exit 1
  fi

  state="$(ticket_state "$task_id")"
  if [[ "$state" == "DONE" ]]; then
    echo "error: cannot claim completed task $task_id" >&2
    exit 1
  fi

  owner="$(claim_owner "$task_id" || true)"
  if [[ -n "$owner" ]]; then
    if [[ "$owner" == "$agent" ]]; then
      echo "$task_id already claimed by $agent"
      return
    fi
    echo "error: $task_id already claimed by $owner" >&2
    exit 1
  fi

  printf '%s\t%s\t%s\t%s\n' "$task_id" "$agent" "$(now_ts)" "$note" >>"$CLAIMS_FILE"
  append_pulse "$task_id" "CLAIM" "agent=$agent${note:+ note=$note}"
  "$PM_TICKET" render status.md
  echo "$task_id claimed by $agent"
}

cmd_unclaim() {
  local agent="$1"
  local task_id="$2"
  local owner

  acquire_lock "$agent"
  ensure_pm_initialized
  ensure_claims_file

  owner="$(claim_owner "$task_id" || true)"
  if [[ -z "$owner" ]]; then
    echo "error: task is not claimed: $task_id" >&2
    exit 1
  fi
  if [[ "$owner" != "$agent" ]]; then
    echo "error: $task_id is claimed by $owner (not $agent)" >&2
    exit 1
  fi

  remove_claim "$task_id"
  append_pulse "$task_id" "UNCLAIM" "agent=$agent"
  "$PM_TICKET" render status.md
  echo "$task_id released by $agent"
}

cmd_claims() {
  ensure_pm_initialized
  ensure_claims_file
  awk -F'\t' '
    NR == 1 { next }
    { printf "%s\t%s\t%s\t%s\n", $1, $2, $3, $4; found=1 }
    END { if (!found) print "(none)" }
  ' "$CLAIMS_FILE"
}

cmd_lock_info() {
  if [[ ! -d "$LOCK_DIR" ]]; then
    echo "lock: free"
    return
  fi
  echo "lock: held"
  echo "owner: $(read_lock_field agent || echo unknown)"
  echo "host: $(read_lock_field host || echo unknown)"
  echo "pid: $(read_lock_field pid || echo unknown)"
  echo "started: $(read_lock_field started || echo unknown)"
  echo "age_seconds: $(lock_age_seconds)"
}

cmd_unlock_stale() {
  if [[ ! -d "$LOCK_DIR" ]]; then
    echo "lock already free"
    return
  fi
  if lock_is_stale; then
    remove_lock_dir
    echo "stale lock removed"
    return
  fi
  echo "error: lock is active and not stale" >&2
  exit 1
}

cmd_run() {
  local agent="$1"
  shift
  local pm_cmd task_id

  if [[ "${1:-}" == "--" ]]; then
    shift
  fi
  if [[ $# -lt 1 ]]; then
    usage
    exit 1
  fi

  pm_cmd="$1"
  task_id="$(task_id_from_pm_command "${1:-}" "${2:-}")"

  acquire_lock "$agent"
  if [[ "$pm_cmd" != "init" ]]; then
    ensure_pm_initialized
    ensure_claims_file
  fi

  if [[ -n "$task_id" ]]; then
    ensure_task_claimed_by_agent "$agent" "$task_id"
  fi

  "$PM_TICKET" "$@"

  if [[ -n "$task_id" && "$pm_cmd" == "done" ]]; then
    if [[ "$(claim_owner "$task_id" || true)" == "$agent" ]]; then
      remove_claim "$task_id"
      append_pulse "$task_id" "UNCLAIM" "auto-release on done by $agent"
    fi
  fi

  if is_mutating_pm_command "$pm_cmd" && [[ "$pm_cmd" != "render" ]]; then
    "$PM_TICKET" render status.md
  fi
}

main() {
  require_pm_ticket

  if [[ $# -lt 1 ]]; then
    usage
    exit 1
  fi

  local cmd="$1"
  shift

  case "$cmd" in
    init)
      cmd_init
      ;;
    claim)
      [[ $# -lt 2 ]] && { usage; exit 1; }
      cmd_claim "$1" "$2" "${3:-}"
      ;;
    unclaim)
      [[ $# -lt 2 ]] && { usage; exit 1; }
      cmd_unclaim "$1" "$2"
      ;;
    claims)
      cmd_claims
      ;;
    run)
      [[ $# -lt 2 ]] && { usage; exit 1; }
      cmd_run "$@"
      ;;
    lock-info)
      cmd_lock_info
      ;;
    unlock-stale)
      cmd_unlock_stale
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
