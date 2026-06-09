#!/bin/bash
# auto-heal-template.sh — Self-healing harness template.
#
# Reads a failure memory log, matches against known auto-patch classes,
# applies fixes (with verification), and escalates unrecognized failures.
#
# Usage:
#   bash auto-heal-template.sh               # Dry-run (safe)
#   AUTO_HEAL=1 bash auto-heal-template.sh   # Apply fixes
#
# Requires:
#   - Failure memory at FAILURE_MEMORY path (JSONL)
#   - verify-action.sh in $HARNESS_DIR
#   - trajectory-logger.sh sourced

set -euo pipefail

HARNESS_DIR="${HARNESS_DIR:-./harness}"
FAILURE_MEMORY="${HARNESS_DIR}/failure-memory.jsonl"
HEAL_STATE="${HARNESS_DIR}/self-heal-state.json"
RATE_LIMIT_HOURS="${RATE_LIMIT_HOURS:-6}"

# Source trajectory logger if available
if [ -f "${HARNESS_DIR}/trajectory-logger.sh" ]; then
    source "${HARNESS_DIR}/trajectory-logger.sh"
fi

# ─── Configuration: Known Auto-Patch Classes ─────────────────────

# Format: "fingerprint_pattern|fix_command|verification_command|description"
# Add your known failure patterns here
AUTO_PATCH_CLASSES=(
    "model_timeout|echo 'Switching to fallback model'|echo 'Model fallback configured'|Add timeout-aware model routing"
    "vps_unreachable|echo 'Checking VPN/SSH connectivity'|echo 'Connectivity restored'|Restart SSH tunnel if down"
    "empty_response|echo 'Retrying with explicit format instruction'|echo 'Response received'|Retry with format prompt"
    "context_overflow|echo 'Compacting context window'|echo 'Context compacted'|Compact agent context"
)

# ─── Helpers ─────────────────────────────────────────────────────

is_rate_limited() {
    local fingerprint="$1"
    if [ ! -f "$HEAL_STATE" ]; then
        return 1
    fi
    local last_heal
    last_heal=$(python3 -c "
import json, sys
try:
    state = json.load(open('$HEAL_STATE'))
    print(state.get('$fingerprint', {}).get('last_heal', ''))
except:
    print('')
" 2>/dev/null)
    if [ -z "$last_heal" ]; then
        return 1
    fi
    # Check if within rate limit window
    local now
    now=$(date +%s)
    local then
    then=$(date -j -f '%Y-%m-%dT%H:%M:%SZ' "$last_heal" +%s 2>/dev/null || echo 0)
    local diff=$(( (now - then) / 3600 ))
    if [ "$diff" -lt "$RATE_LIMIT_HOURS" ]; then
        return 0
    fi
    return 1
}

record_heal_attempt() {
    local fingerprint="$1"
    local success="$2"
    local timestamp
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

    python3 -c "
import json, os
state = {}
if os.path.exists('$HEAL_STATE'):
    state = json.load(open('$HEAL_STATE'))
state['$fingerprint'] = {'last_heal': '$timestamp', 'success': '$success' == 'true'}
json.dump(state, open('$HEAL_STATE', 'w'), indent=2)
print(f'Recorded heal attempt: $fingerprint -> $success')
"
}

# ─── Main ────────────────────────────────────────────────────────

echo "=== SELF-HEAL: $(date) ==="

if [ ! -f "$FAILURE_MEMORY" ]; then
    echo "No failure memory found at $FAILURE_MEMORY. Nothing to heal."
    exit 0
fi

# Read open (unresolved) failures
python3 -c "
import json
with open('$FAILURE_MEMORY') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
            if not entry.get('resolved'):
                print(json.dumps(entry))
        except:
            pass
" > /tmp/open-failures.jsonl

OPEN_COUNT=$(wc -l < /tmp/open-failures.jsonl | tr -d ' ')
if [ "$OPEN_COUNT" -eq 0 ]; then
    echo "No open failures. System healthy."
    rm -f /tmp/open-failures.jsonl
    exit 0
fi

echo "Found $OPEN_COUNT open failure(s)."

HEALED=0
SKIPPED=0
UNRECOGNIZED=0

while IFS= read -r failure_line; do
    [ -z "$failure_line" ] && continue

    fingerprint=$(echo "$failure_line" | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('fingerprint','unknown'))" 2>/dev/null || echo "unknown")
    failure_type=$(echo "$failure_line" | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('failure_type','unknown'))" 2>/dev/null || echo "unknown")

    echo ""
    echo "--- Processing: $fingerprint ($failure_type) ---"

    # Rate limit check
    if is_rate_limited "$fingerprint"; then
        echo "  [SKIP] Rate-limited (last heal < ${RATE_LIMIT_HOURS}h ago)"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # Try matching auto-patch classes
    matched=false
    for pclass in "${AUTO_PATCH_CLASSES[@]}"; do
        IFS='|' read -r pattern fix verify desc <<< "$pclass"
        if [[ "$failure_type" == "$pattern" ]]; then
            echo "  [MATCH] Auto-patch class: $desc"

            if [ "${AUTO_HEAL:-0}" = "1" ]; then
                echo "  [FIX] Applying: $fix"
                eval "$fix"

                echo "  [VERIFY] Running: $verify"
                if eval "$verify"; then
                    echo "  [OK] Fix verified."
                    record_heal_attempt "$fingerprint" true

                    if type log_trajectory_success &>/dev/null; then
                        log_trajectory_success "auto-heal: $fingerprint" "" "auto-heal,verify" "patched: $desc"
                    fi
                else
                    echo "  [FAIL] Verification failed. Escalating."
                    record_heal_attempt "$fingerprint" false

                    if type log_trajectory_failure &>/dev/null; then
                        log_trajectory_failure "auto-heal: $fingerprint" "patch_failed" "" "auto-heal,verify" "verification failed after fix"
                    fi
                fi
            else
                echo "  [DRY-RUN] Would apply: $fix (set AUTO_HEAL=1 to enable)"
            fi

            HEALED=$((HEALED + 1))
            matched=true
            break
        fi
    done

    if [ "$matched" = false ]; then
        echo "  [UNRECOGNIZED] No auto-patch class for: $failure_type"
        echo "  [ESCALATE] Run council debate to diagnose this failure class"
        UNRECOGNIZED=$((UNRECOGNIZED + 1))
    fi
done < /tmp/open-failures.jsonl

rm -f /tmp/open-failures.jsonl

echo ""
echo "=== SELF-HEAL COMPLETE ==="
echo "  Healed: $HEALED"
echo "  Skipped (rate-limited): $SKIPPED"
echo "  Unrecognized (escalated): $UNRECOGNIZED"
echo ""

if [ "$UNRECOGNIZED" -gt 0 ]; then
    echo "ACTION REQUIRED: $UNRECOGNIZED failure class(es) need diagnosis. Run:"
    echo "  npx tsx council-debate.ts 'Diagnose failure class and recommend auto-patch'"
    exit 1
fi
