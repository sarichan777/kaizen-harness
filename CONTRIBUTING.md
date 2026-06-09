# Contributing to Kaizen Harness

The harness is how you make AI agents reliable. If you've built a pattern that catches failures, saves time, or forces better decisions, this is where it belongs.

## What Makes a Good Harness Pattern

A harness pattern is a reusable piece of infrastructure that surrounds an AI agent and makes it more reliable. Not a prompt. Not a library. A **pattern** that sits between the agent and the world.

Good patterns address a specific failure class:

- "My agent says it fixed the bug but didn't test anything" → verification pattern
- "My agent made a bad architectural call because it only considered one option" → council debate pattern
- "My agent broke something at 3 AM and I didn't know until morning" → self-healing + monitoring pattern
- "My agent burned tokens on a task it had already failed twice" → memory + dedup pattern

## How to Propose a New Pattern

### 1. Fork and Branch

```bash
git clone https://github.com/sarichan777/kaizen-harness.git
cd kaizen-harness
git checkout -b pattern/your-pattern-name
```

### 2. Create the Pattern Directory

Every pattern lives in `patterns/<name>/` with this structure:

```
patterns/your-pattern/
├── README.md    # Required: explains the pattern
├── <main-file>  # Required: the reusable script/template
└── examples/    # Optional: usage examples
```

### 3. Write the Pattern README

Every pattern README must cover these sections:

| Section | What to Include |
|---|---|
| **Problem** | What specific failure class does this solve? When does it happen? |
| **Solution** | How does the pattern work? What does it do? |
| **What We Learned** | If you've used this in production, share what you discovered. If it's new, explain why you believe it works. |
| **Usage** | Copy-pasteable example. Someone should be able to `source` or run your pattern in 30 seconds. |
| **Code** | Brief reference to the main implementation file and key functions. |
| **Integration** | How does this fit with other harness components? (trajectory logger, verification, self-heal, council) |
| **Tradeoffs** | What does it cost? What are the downsides? When should you NOT use it? |

See existing patterns in the repo for examples: [council-debate](patterns/council-debate/), [verification](patterns/verification/), [trajectory-logger](patterns/trajectory-logger/).

### 4. Code Style

- **Shell scripts:** Use `bash` (not sh). Source-safe: work when sourced from another script. Clear function names. No global state unless declared at the top.
- **TypeScript:** Use `npx tsx` as the runner. Keep dependencies minimal. Type function signatures.
- **Markdown:** For all documentation. Use tables for structured data (checks, fingerprints, configurations).
- **Python:** Avoid unless absolutely necessary. Prefer bash for simple scripts, TypeScript for complex tools.

### 5. Testing Expectations

- Your pattern must include at least one runnable example in the README that someone can copy-paste and execute.
- If your pattern wraps or calls external services, handle failures gracefully. Missing API keys should produce a clear error message, not a cryptic stack trace.
- Test that your pattern works when sourced (bash) or imported (TypeScript) from another script.

### 6. Open a Pull Request

Push your branch and open a PR against `main`:

```bash
git push origin pattern/your-pattern-name
# Then open a PR at https://github.com/sarichan777/kaizen-harness
```

Your PR description should explain:
- What failure class this pattern solves
- How to test it (one-liner copy-paste command)
- Any dependencies or API keys needed

A maintainer will review and merge. PRs that follow the pattern template and include a working example get merged quickly.

## Pattern Ideas

Not sure what to contribute? Here are patterns we'd love to see:

- **Rate limiting for API calls** - Agents burn through rate limits without awareness. A pattern that tracks quota and backs off.
- **Memory compaction strategies** - Long-running agents accumulate context bloat. Patterns for summarizing and pruning.
- **Model fallback chains** - When one model fails, automatically try the next. With logging so you know how often each model fails.
- **Audit trail logging** - Every destructive action gets logged with justification, rollback plan, and approval gating.
- **Permission gating for destructive actions** - Agents shouldn't be able to `rm -rf` or `DROP TABLE` without explicit approval gates.
- **Drift detection for agent configurations** - Configs that were correct yesterday may be stale today. Detect drift and alert.
- **Cost budgeting and kill switches** - If an agent burns more than $X in API costs, stop it and escalate.

## Issue Workflow

1. **Find something to work on.** Browse [open issues](https://github.com/sarichan777/kaizen-harness/issues), especially those tagged `good first issue`.
2. **Claim it.** Comment on the issue to let others know you're working on it.
3. **Build it.** Follow the pattern template above.
4. **Submit a PR.** Link to the issue in your PR description (`Closes #123`).

## Code of Conduct

Be direct. Be helpful. Build things that work.

This is a harness for AI agents. The patterns here run in production. Contributions that address real failure modes with working code are always welcome.
