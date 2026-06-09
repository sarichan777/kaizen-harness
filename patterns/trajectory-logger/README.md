# Trajectory Logger

## Problem

Agents act. They succeed or fail. Without a structured log of those actions, you can't diagnose why things break. You're guessing based on the last failure you remember.

Most agent systems log nothing beyond terminal output. When something goes wrong, you scroll through chat history trying to reconstruct what happened. This doesn't scale past 10 actions.

## Solution

An append-only JSONL log of every agent action: task description, model used, tools called, success/failure, failure type, harness version. Source-once, log from everywhere.

The harness version in every entry lets you correlate improvements with outcomes. When you add a new verification check or auto-patch class, you can measure whether the failure rate actually dropped for that harness version.

## What We Learned

We log every action across 3 machines, 14+ agent scripts, and council debates. After two weeks of logging:

- **model_timeout** appeared 3x more often on free OpenRouter models than local Ollama. We added a timeout-aware model router that prefers models with consistent response times.
- **empty_response** clustered around specific API endpoints. We added pre-flight checks for those endpoints before the agent calls them.
- **context_overflow** spiked when agents were asked to read research documents. That led to the muncher-first rule.

None of these patterns were visible without the log.

## Usage

```bash
source trajectory-logger.sh

# Log a successful action
log_trajectory "fix login bug" "claude-4-sonnet" "read,edit,test" "success" "" "tested with 3 edge cases"

# Log a failure
log_trajectory "deploy to staging" "gpt-4" "ssh,rsync" "fail" "vps_unreachable" "connection timed out after 30s"

# Convenience wrappers
log_trajectory_success "add rate limiter" "claude-4-sonnet" "read,edit,test"
log_trajectory_failure "query database" "connection_error" "deepseek-v4" "pg_query,curl"
```

## Integration

The trajectory log is read by:

- **analyze-failures.ts** — Detects repeating failure patterns and generates recommendations
- **RHO loop** — Uses failure history to propose harness improvements
- **Self-heal system** — Fingerprints failures and matches against known auto-patch classes

## File Format

```jsonl
{"timestamp":"2026-06-08T12:00:00Z","task":"council debate on caching","model":"council(4ok/6seats)","tools":"callOpenRouter,callOllama","success":"success","failure_type":"","harness_version":"1.0.0","notes":"resolved tradeoff, chose file-based cache"}
{"timestamp":"2026-06-08T12:01:00Z","task":"verify automation","model":"","tools":"curl,ssh,pgrep","success":"fail","failure_type":"vps_unreachable","harness_version":"1.0.0","notes":"VPS offline, 3 checks skipped"}
```

## Tradeoffs

- **Pro:** Zero dependencies beyond bash and python3. Works on macOS/Linux.
- **Pro:** Append-only, one line per action. Easy to tail, grep, and parse.
- **Con:** No built-in query interface. Use the analyzer script or jq.
- **Con:** JSONL is not a database. For very large systems, consider SQLite or a proper observability stack.
