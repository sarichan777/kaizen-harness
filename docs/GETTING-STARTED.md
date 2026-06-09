# Getting Started with Kaizen Harness

How to add harness engineering to an existing agent project. Start with the minimum viable harness, then add patterns as you hit failure classes.

## Minimum Viable Harness

Three things every agent system needs:

### 1. Trajectory Logger

Without a log, you're guessing why things fail.

```bash
# Copy the logger
cp patterns/trajectory-logger/trajectory-logger.sh ./harness/
source ./harness/trajectory-logger.sh

# Log every agent action
log_trajectory "fix login bug" "claude-4" "read,edit,test" "success" "" "tested manually"
log_trajectory "fix login bug" "" "read,edit" "fail" "empty_response" "API returned nothing"
```

After a week, you have data. Run the analyzer on it.

### 2. Verification Script

Stop trusting agent claims. Verify.

```bash
# Copy the verifier
cp patterns/verification/verify-action.sh ./harness/

# Verify what the agent claims to have done
./harness/verify-action.sh \
  --cmd "npm test" \
  --desc "tests pass after agent changes" \
  --expect-exit 0

./harness/verify-action.sh \
  --cmd "curl -s https://example.com" \
  --desc "site is up" \
  --expect-exit 0 \
  --expect-stdout "200"
```

Add a check every time an agent makes a change you'd normally verify manually. Over time, the verification script becomes the governance layer.

### 3. Failure Memory

A simple JSONL file where you record every failure with structure:

```json
{"timestamp":"2026-06-08T12:00:00Z","task":"fix login","failure_type":"empty_response","fingerprint":"api_endpoint_empty_response"}
```

The fingerprint is the key. Same fingerprint appearing within 6 hours = known problem, maybe rate-limit retries. Same fingerprint appearing across weeks = systemic issue, add a verification check.

## Adding Patterns as You Need Them

### When agents make bad architectural decisions

Add council debates. Run 3-6 free models in parallel on the decision. Let them disagree. Synthesize. Use a paid model only for final validation.

```bash
npx tsx patterns/council-debate/council-debate.ts "Should we use PostgreSQL or SQLite for the cache layer?"
```

### When agents break silently

Add self-healing. Copy the template, configure failure fingerprints, set up the auto-patch classes. The template includes rate limiting and escalation so you're not patching in a loop.

### When agents run over budget

Add cost-first routing. Enforce at the orchestration level: free models for exploration, muncher-first context loading, paid models only for validation. The model doesn't know what it costs. The harness does.

### When agents use stale information

Add the memory verification rule. Before acting on cached state, verify 2-3 key assertions against the live environment. If assertion fails, update cache first.

## Integration with Existing Agent Frameworks

These patterns are framework-agnostic. They work with:

- **Cursor / Claude Code:** Use the Cursor rules templates. The verification script and trajectory logger are bash — they work anywhere.
- **LangChain / CrewAI:** Wrap each agent action with trajectory logging. Add verification steps between chain nodes.
- **Custom agent loop:** Source the trajectory logger, call it after each action. Run the verification script as a post-step.
- **GitHub Actions / CI:** Run the verification script as a CI step before deploy. Log results to the trajectory.

## What Success Looks Like

- **Week 1:** Trajectory logger running, verification script with 5 checks.
- **Month 1:** Failure memory growing, starting to see patterns. Added 2 auto-patch classes.
- **Month 3:** Council debates on architectural decisions. Self-healing handles routine failures. Human intervention only for new failure classes.
- **Month 6:** RHO loop running. The harness proposes its own improvements.
