# Self-Healing

## Problem

Agent systems break. Processes die. Configurations drift. APIs change. The default pattern: an agent detects a problem, reports it, and waits for a human to approve the fix.

This works for demos. It doesn't work for infrastructure that needs to stay up at 3 AM. Humans are the bottleneck in the repair loop.

## Solution

A self-healing system that:

1. Reads a failure memory log with structured failure entries
2. Matches failures against known fingerprint classes
3. Auto-patches what it recognizes (with post-fix verification)
4. Escalates unrecognized failures to council debate for consensus
5. Rate-limits by fingerprint to prevent patch loops (6-hour cooldown)

The system remembers its own repair history. If a patch fails, it records that too and escalates differently next time.

## What We Learned

We run a self-heal system (`self-heal.ts`) on a 20-minute interval across our infrastructure. We learned:

- **Fingerprinting matters more than classification.** Two failures that look similar ("process died") need different fingerprints if the root cause is different (OOM kill vs. macOS TCC kill vs. PM2 restart cascade). Same fix doesn't apply.
- **Rate limiting prevents cascading failures.** Without the 6-hour cooldown, a flaky fix would trigger re-patch → re-fail → re-patch endlessly. The rate limiter forces the system to escalate instead.
- **Verification after every fix is non-negotiable.** The first version of self-heal applied patches and assumed they worked. We added post-fix verification (run the tests, check the process is up) after a bad patch made things worse.
- **The self-heal is blind without a failure memory bridge.** We ran system audits that caught real failures (dead agents, unreachable websites, PM2 process crashes), but the audit results never reached the failure memory log. The self-heal had no way to see them. Adding a bridge that writes audit failures into the failure memory log closes the loop.
- **Misconfigured monitoring creates false positives.** One of our checks used the wrong process pattern (`ssh -R` instead of `ssh -L`), so it flagged the SSH tunnel as down every cycle even though it was running. Another check monitored a website that has no production deployment. Blindly auto-patching false positives would have been destructive. Validate your monitoring before wiring it to repair.
- **Not all fixes are code edits.** Some failures need operational actions: launching a process, reloading nginx, restarting a PM2 service. These are commands, not code diffs. The auto-patch logic needs to handle both classes.

## Auto-Patch Classes

Known failure patterns we auto-fix. Code-level patches change files. Operational patches run service commands.

### Code-level patches

| Failure Class | Fingerprint | Auto-Patch |
|---|---|---|
| `model_timeout` | API timeout on specific model | Switch to alternate model, add timeout threshold |
| `empty_response` | API returned empty body | Retry with explicit format instruction |
| `context_overflow` | Token limit exceeded | Compact context, reduce scope |

### Operational patches (process/service level)

| Failure Class | Fingerprint | Auto-Patch | Verify |
|---|---|---|---|
| `agent_down` | LaunchAgent process missing | `launchctl kickstart` | pgrep + port check |
| `http_failure` | Website returns non-200 | SSH reload nginx, restart backend | curl 200 on affected sites |
| `pm2_loop` | PM2 process restart cascade | SSH restart PM2 app, reset counter | grep for healthy state in log |

## Usage

The template is a shell script that wraps your heal logic. Configure it with your failure memory path and known auto-patch classes.

```bash
# Run self-heal in dry-run mode (safe)
bash auto-heal-template.sh

# Apply fixes (set AUTO_HEAL=1)
AUTO_HEAL=1 bash auto-heal-template.sh
```

## Integration

The self-heal system depends on:
- **Trajectory logger:** Records every auto-patch attempt (success or failure)
- **Verification script:** Post-fix verification to confirm the patch worked
- **Failure memory:** Structure with fingerprints and resolution status
- **Council debate:** For unrecognized failures that need diagnosis

## Tradeoffs

- **Pro:** Eliminates human intervention for routine failures
- **Pro:** Rate-limited to prevent runaway patching
- **Con:** Auto-patching is inherently risky. Start with dry-run mode.
- **Con:** Requires a failure memory with structured fingerprints to be useful
- **Con:** Wrong auto-patch can make things worse. Always verify after patching.
