# Kaizen Harness

**Self-improving AI agent infrastructure.** Trajectory logging, retrospective optimization, council debates, self-healing, and verification. The harness makes the model reliable.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## The model is the engine. The harness is everything else.

Memory. Verification. Failure recovery. Tool selection. Cost controls. Governance. The system that surrounds the model and determines whether it produces something useful or something you need to babysit.

A Stanford/Tsinghua study found the same model can be **6x more effective** with a good harness. Mitchell Hashimoto put it precisely:

> "When an AI agent makes a mistake, don't rerun the prompt. Change the system so that entire class of mistakes stops happening."

This repo contains the harness patterns we built and run 24/7. Not research. Working infrastructure.

## Architecture

Six components, each solving a specific failure class:

```
┌────────────────────────────────────────────┐
│               AGENT HARNESS                │
├────────────┬───────────────┬───────────────┤
│ TRAJECTORY │ RETROSPECTIVE │   COUNCIL     │
│   LOGGER   │ OPTIMIZATION  │   DEBATES     │
│ (memory)   │ (RHO loop)    │ (multi-model) │
├────────────┼───────────────┼───────────────┤
│   SELF-    │ VERIFICATION  │    TOOL       │
│  HEALING   │   PIPELINE    │   REGISTRY    │
│ (auto-fix) │ (governance)  │ (with hooks)  │
└────────────┴───────────────┴───────────────┘
```

### 1. Trajectory Logger
Structured append-only log of every agent action: task, model, tools used, success/failure, failure type, harness version. This is the memory the harness needs to learn from.

### 2. RHO (Retrospective Harness Optimization)
Reads the trajectory log, groups failures by type, detects repeating patterns, and generates harness improvement recommendations. Over time, proposes and applies rule changes, verification additions, and tool upgrades so the same failure class stops happening.

### 3. Council Debates
For architectural decisions and hard problems, we run 3-6 free models in parallel, let them disagree, then synthesize. A single-prompt answer has one blind spot. A debate surfaces tradeoffs. Same models, better decisions.

### 4. Self-Healing
Reads a failure memory log, matches failures against known fingerprint classes, auto-patches what it recognizes. Unrecognized failures go to council debate for consensus. Rate-limited by fingerprint (6-hour cooldown) to prevent patch loops.

### 5. Verification Pipeline
Over 40 health checks across machines: process health, disk usage, SSL expiry, HTTP responses, API key liveness. If a check fails and auto-heal is enabled, the script attempts repair and re-checks. The harness doesn't just detect problems, it closes the loop.

### 6. Tool Registry with Verification Hooks
Formal inventory of every agent script with health checks, safety levels, and dependencies. Tools declare what they need and what they produce. The registry verifies tools before the agent uses them.

## Quick Start

Clone and try a single pattern:

```bash
git clone https://github.com/sarichan777/kaizen-harness.git
cd kaizen-harness

# Add trajectory logging to any agent
source patterns/trajectory-logger/trajectory-logger.sh
log_trajectory "my test task" "gpt-4" "curl,grep" "success" "" "everything worked"

# Run a council debate on any question
npx tsx patterns/council-debate/council-debate.ts "Should I use Redis or just write to a file?"
```

See [GETTING-STARTED.md](docs/GETTING-STARTED.md) for the full walkthrough.

## Patterns

Each directory has a README explaining why the pattern exists, what problem it solves, and a reusable template:

| Pattern | What It Solves |
|---|---|
| [trajectory-logger](patterns/trajectory-logger/) | Agents have no memory of their own failures |
| [council-debate](patterns/council-debate/) | Single-model answers miss tradeoffs |
| [self-healing](patterns/self-healing/) | Agents break silently and wait for humans |
| [verification](patterns/verification/) | Agents claim success without evidence |

## Why This Matters

Read [WHY-HARNESS.md](docs/WHY-HARNESS.md) for the full case, backed by research:

- **Stanford/Tsinghua study:** Same model, 6x variance depending on harness quality
- **UC Berkeley system-scaling framework:** LLM + memory + context + skill routing + orchestration + verification/governance. The model is 1 of 6 pieces.
- **RHO paper (Microsoft Research):** Agents that improve their own harness from past failures

## License

MIT — use these patterns, adapt them, ship them. See [LICENSE](LICENSE).
