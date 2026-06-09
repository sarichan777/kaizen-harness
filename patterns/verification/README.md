# Verification

## Problem

Agents claim success without evidence. "Fixed the bug" with no test run. "Deployed successfully" with no health check. "Updated the config" but the config is syntactically invalid.

Without verification, you're trusting the model's claims. Models are confidently wrong more often than you think.

## Solution

A standardized verification script that checks what matters: exit codes, stdout patterns, stderr emptiness. Every agent action should be followed by a verification step. No claim without evidence.

The script also detects common error patterns in output (segfaults, connection refused, syntax errors) and warns about them even when the exit code looks clean.

## What We Learned

We run 40+ verification checks every 20 minutes across our infrastructure. Some examples:

| Check | What It Catches |
|---|---|
| PM2 process health | Processes that appear running but are in error loop |
| SSL certificate expiry | Certificates expiring within 30 days (auto-renewed) |
| API key liveness | Keys that have been revoked or rate-limited |
| Website HTTP responses | 5xx errors, connection timeouts |
| Disk usage | Volumes filling silently |
| Docker container health | Containers running but unresponsive |
| Orphan prototype detection | Processes spawned by agents that were never cleaned up |

The key insight: verification checks discover things the agent didn't know to check. The harness looks for problems the agent didn't anticipate.

## Usage

```bash
# Basic check: did the command succeed?
./verify-action.sh --cmd "npm test" --desc "unit tests" --expect-exit 0

# Check that output contains expected text
./verify-action.sh --cmd "curl -s https://example.com" --desc "site reachable" --expect-exit 0 --expect-stdout "200"

# Ensure no errors were printed to stderr
./verify-action.sh --cmd "python script.py" --desc "data pipeline" --expect-stdout "success" --expect-stderr-empty

# Machine-readable output
./verify-action.sh --cmd "npm run build" --desc "build" --json

# With timeout (default 120s)
./verify-action.sh --cmd "long-running-task" --desc "heavy job" --timeout 300 --expect-exit 0
```

## Building Your Verification Suite

Start with 5 checks. Add one every time an agent makes a change you'd normally verify manually.

```bash
#!/bin/bash
# verify-all.sh — Your verification suite

source harness/trajectory-logger.sh 2>/dev/null

FAILURES=0

check() {
    local desc="$1"
    shift
    bash harness/verify-action.sh --desc "$desc" "$@"
    if [ $? -ne 0 ]; then
        FAILURES=$((FAILURES + 1))
        log_trajectory_failure "verify: $desc" "verification_failed" "" "verify-action"
    fi
}

# Infrastructure
check "site is up" --cmd "curl -sf https://your-site.com" --expect-exit 0
check "API responds" --cmd "curl -sf https://api.your-site.com/health" --expect-exit 0 --expect-stdout "ok"

# Processes
check "web server running" --cmd "pgrep -f 'node server.js'" --expect-exit 0
check "cron daemon" --cmd "pgrep cron" --expect-exit 0

# Tests
check "unit tests" --cmd "npm test" --expect-exit 0
check "type check" --cmd "npx tsc --noEmit" --expect-exit 0

# Disk
check "disk not full" --cmd "df / | tail -1 | awk '{print \$5}' | grep -v '100%'" --expect-exit 0

echo "Verification complete: $FAILURES failures"
exit $FAILURES
```

## Integration

- **Cron / LaunchAgent:** Run every N minutes. Log results to trajectory.
- **Post-agent-action:** Run after every agent action. If verification fails, trigger self-heal.
- **Pre-deploy:** Run as a deploy gate. If checks fail, block the deploy.
- **CI/CD:** Run as a pipeline step. Failed checks = failed build.

## Tradeoffs

- **Pro:** Framework-agnostic. Works with any agent system.
- **Pro:** Detects problems agents miss (error patterns in output).
- **Con:** You have to maintain the check list. Stale checks that never fail are noise.
- **Con:** False positives from flaky checks will erode trust. Make checks deterministic.
