#!/bin/bash
# trajectory-logger.sh — Structured agent action logging.
#
# Usage:
#   source trajectory-logger.sh
#   log_trajectory "task" "model" "tools" "success" "" "notes"
#   log_trajectory "council debate" "deepseek-v4" "callOpenRouter,callOllama" "success" "" "resolved tradeoff"
#   log_trajectory "verify automation" "" "curl,ssh,pgrep" "fail" "vps_unreachable" "VPS offline"
#
# Log entries written to trajectories.jsonl (one JSON object per line).
# Every entry includes harness_version for correlating improvements with outcomes.

set -euo pipefail

HARNESS_DIR="${HARNESS_DIR:-./harness}"
TRAJECTORY_LOG="${HARNESS_DIR}/trajectories.jsonl"
VERSION_FILE="${HARNESS_DIR}/HARNESS-VERSION.json"

mkdir -p "$HARNESS_DIR"

# Initialize version file if missing
if [ ! -f "$VERSION_FILE" ]; then
    echo '{"harness_version":"0.1.0","initialized":"'"$(date -u '+%Y-%m-%dT%H:%M:%SZ')"'"}' > "$VERSION_FILE"
fi

get_harness_version() {
    if [ -f "$VERSION_FILE" ]; then
        python3 -c "import json,sys; print(json.load(open('$VERSION_FILE')).get('harness_version','0.0.0'))" 2>/dev/null || echo "0.0.0"
    else
        echo "0.0.0"
    fi
}

# log_trajectory task model tools success failure_type notes
log_trajectory() {
    local task="${1:-unknown_task}"
    local model="${2:-}"
    local tools="${3:-}"
    local success="${4:-unknown}"
    local failure_type="${5:-}"
    local notes="${6:-}"

    local timestamp
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    local harness_version
    harness_version=$(get_harness_version)

    # Build JSON entry without jq dependency
    local entry
    entry=$(cat <<ENTRY
{"timestamp":"$timestamp","task":$(printf '%s' "$task" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'),"model":$(printf '%s' "$model" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'),"tools":$(printf '%s' "$tools" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'),"success":$(printf '%s' "$success" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'),"failure_type":$(printf '%s' "$failure_type" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'),"harness_version":"$harness_version","notes":$(printf '%s' "$notes" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')}
ENTRY
)
    echo "$entry" >> "$TRAJECTORY_LOG"

    # Keep log manageable (last 10,000 entries)
    if [ "$(wc -l < "$TRAJECTORY_LOG" 2>/dev/null || echo 0)" -gt 10000 ]; then
        tail -n 10000 "$TRAJECTORY_LOG" > "${TRAJECTORY_LOG}.tmp" && mv "${TRAJECTORY_LOG}.tmp" "$TRAJECTORY_LOG"
    fi
}

log_trajectory_success() {
    log_trajectory "$1" "${2:-}" "${3:-}" "success" "" "${4:-}"
}

log_trajectory_failure() {
    log_trajectory "$1" "${3:-}" "${4:-}" "fail" "$2" "${5:-}"
}
