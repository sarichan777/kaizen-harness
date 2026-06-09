#!/bin/bash
# verify-action.sh — Standardized post-action verification.
#
# Usage:
#   bash verify-action.sh --cmd "your-command" --desc "description" [--expect-exit 0] [--expect-stdout "pattern"] [--expect-stderr-empty]
#   bash verify-action.sh --cmd "curl -s https://example.com" --desc "site reachable" --expect-exit 0 --expect-stdout "200"
#   bash verify-action.sh --cmd "npm test" --desc "unit tests" --expect-exit 0
#
# Returns 0 if all checks pass, 1 otherwise.
# Outputs structured JSON result to stdout when --json flag is set.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

CMD=""
DESC=""
EXPECT_EXIT=0
EXPECT_STDOUT=""
EXPECT_STDERR_EMPTY=false
JSON_OUTPUT=false
TIMEOUT_SECS=120

while [ $# -gt 0 ]; do
    case "$1" in
        --cmd) CMD="$2"; shift 2 ;;
        --desc) DESC="$2"; shift 2 ;;
        --expect-exit) EXPECT_EXIT="$2"; shift 2 ;;
        --expect-stdout) EXPECT_STDOUT="$2"; shift 2 ;;
        --expect-stderr-empty) EXPECT_STDERR_EMPTY=true; shift ;;
        --json) JSON_OUTPUT=true; shift ;;
        --timeout) TIMEOUT_SECS="$2"; shift 2 ;;
        *) echo "Unknown flag: $1"; exit 2 ;;
    esac
done

if [ -z "$CMD" ]; then
    echo "ERROR: --cmd is required"
    exit 2
fi

DESC="${DESC:-$CMD}"

# Run the command, capture output
TMP_STDOUT=$(mktemp /tmp/verify-action-stdout.XXXXXX)
TMP_STDERR=$(mktemp /tmp/verify-action-stderr.XXXXXX)
trap "rm -f $TMP_STDOUT $TMP_STDERR" EXIT

START_TIME=$(date +%s)

EXIT_CODE=0
if command -v timeout &>/dev/null; then
    timeout "$TIMEOUT_SECS" bash -c "$CMD" > "$TMP_STDOUT" 2> "$TMP_STDERR" || EXIT_CODE=$?
else
    bash -c "$CMD" > "$TMP_STDOUT" 2> "$TMP_STDERR" || EXIT_CODE=$?
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

STDOUT_CONTENT=$(cat "$TMP_STDOUT")
STDERR_CONTENT=$(cat "$TMP_STDERR")
STDOUT_LEN=$(echo "$STDOUT_CONTENT" | wc -c | tr -d ' ')
STDERR_LEN=$(echo "$STDERR_CONTENT" | wc -c | tr -d ' ')

PASS=true
CHECKS_PASSED=0
CHECKS_FAILED=0

check_exit_code() {
    if [ "$EXIT_CODE" -eq "$EXPECT_EXIT" ]; then
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
        echo -e "  ${GREEN}[PASS]${NC} Exit code: $EXIT_CODE (expected $EXPECT_EXIT)"
        return 0
    else
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
        PASS=false
        echo -e "  ${RED}[FAIL]${NC} Exit code: $EXIT_CODE (expected $EXPECT_EXIT)"
        return 1
    fi
}

check_stdout_pattern() {
    if echo "$STDOUT_CONTENT" | grep -qE "$EXPECT_STDOUT"; then
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
        echo -e "  ${GREEN}[PASS]${NC} stdout matches: '$EXPECT_STDOUT'"
        return 0
    else
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
        PASS=false
        echo -e "  ${RED}[FAIL]${NC} stdout does not match: '$EXPECT_STDOUT'"
        if [ -n "$STDOUT_CONTENT" ]; then
            echo "    stdout preview: $(echo "$STDOUT_CONTENT" | head -3)"
        fi
        return 1
    fi
}

check_stderr_empty() {
    if [ -z "$STDERR_CONTENT" ] || [ "$STDERR_LEN" -eq 0 ]; then
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
        echo -e "  ${GREEN}[PASS]${NC} stderr is empty"
        return 0
    else
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
        PASS=false
        echo -e "  ${RED}[FAIL]${NC} stderr not empty (${STDERR_LEN} bytes)"
        echo "    stderr preview: $(echo "$STDERR_CONTENT" | head -3)"
        return 1
    fi
}

check_error_patterns() {
    local errors_found=0
    for pattern in "FATAL ERROR" "Segmentation fault" "command not found" "Permission denied" \
                   "No such file" "Cannot find module" "SyntaxError" "ReferenceError" \
                   "ECONNREFUSED" "ETIMEDOUT" "heap out of memory"; do
        if echo "$STDOUT_CONTENT$STDERR_CONTENT" | grep -qi "$pattern"; then
            errors_found=$((errors_found + 1))
            if [ $errors_found -le 3 ]; then
                echo -e "  ${YELLOW}[WARN]${NC} Error pattern detected: '$pattern'"
            fi
        fi
    done
    if [ $errors_found -gt 3 ]; then
        echo -e "  ${YELLOW}[WARN]${NC} ...and $((errors_found - 3)) more error patterns"
    fi
}

echo "=== VERIFY: $DESC ==="
echo "  Command: $CMD"
echo "  Duration: ${DURATION}s"

check_exit_code

if [ -n "$EXPECT_STDOUT" ]; then
    check_stdout_pattern
fi

if [ "$EXPECT_STDERR_EMPTY" = true ]; then
    check_stderr_empty
fi

check_error_patterns

echo "  Checks: $CHECKS_PASSED passed, $CHECKS_FAILED failed"

if [ "$JSON_OUTPUT" = true ]; then
    PY_PASSED="False"
    if [ "$PASS" = true ]; then PY_PASSED="True"; fi
    python3 -c "
import json
result = {
    'desc': '${DESC//\'/\'\\\'\'}',
    'passed': ${PY_PASSED},
    'exit_code': ${EXIT_CODE},
    'expected_exit': ${EXPECT_EXIT},
    'duration_secs': ${DURATION},
    'checks_passed': ${CHECKS_PASSED},
    'checks_failed': ${CHECKS_FAILED},
    'stdout_len': ${STDOUT_LEN},
    'stderr_len': ${STDERR_LEN}
}
print(json.dumps(result))
"
fi

if [ "$PASS" = true ]; then
    echo -e "${GREEN}VERIFICATION PASSED${NC}"
    exit 0
else
    echo -e "${RED}VERIFICATION FAILED${NC}"
    exit 1
fi
