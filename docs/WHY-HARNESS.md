# Why Harness Engineering

## The model isn't the bottleneck

Every month brings a new model that scores 8% better on some benchmark. The AI industry is obsessed with model upgrades.

Meanwhile, a Stanford/Tsinghua study found the same model can be **6x more effective** depending on what's around it. Memory. Tool access. Verification. Failure recovery. The harness.

UC Berkeley researchers mapped what it takes to build an effective AI system:

> LLM + memory + context + skill routing + orchestration + verification/governance

The model is one piece of six. Getting any of the other five wrong undermines whatever model you paid for.

## The Hashimoto Principle

Mitchell Hashimoto (co-founder of HashiCorp) gave the clearest framing of harness engineering:

> "When an AI agent makes a mistake, don't rerun the prompt. Change the system so that entire class of mistakes stops happening."

Most people respond to an agent error by tweaking the prompt. The prompt is not the problem. The system that allowed the error to happen is the problem.

Examples of system-level fixes we made:

- **Agent silently stops running** → Wrapped all services as LaunchAgents that survive reboots and auto-restart on failure. Never diagnose this again.
- **Agent uses stale config** → Added memory verification rule: always check live state against cached state before acting. Config drift stopped.
- **Agent runs out of context window** → Built muncher-first exploration: semantic search finds exactly relevant code instead of dumping entire files. Context rot eliminated.
- **Paid model calls cost $40/day** → Enforced cost-first routing: free models for exploration, paid only for validation. API costs dropped 90%.

Each fix addresses the class of error, not the instance. That's harness engineering.

## The RHO Paper

Microsoft Research formalized this as RHO: **Retrospective Harness Optimization.** The insight: agents can improve their own harness by analyzing past failures.

The loop:
1. Log every action with structured failure types
2. Group failures into pattern classes
3. Diagnose root causes (council debate on each failure class)
4. Generate system-level improvements (rule changes, new verification steps, tool upgrades)
5. Apply and test the improvement
6. Verify the failure class stops appearing

We run a primitive RHO loop that has already produced concrete harness improvements. The trajectory logger records every agent action. The failure analyzer detects repeating patterns. The self-heal system fingerprints and patches known classes. Council debates diagnose new failure types.

The endgame: a harness that evolves itself.

## The Numbers

From running our harness system:

- **40+ verification checks** across 3 machines, every 20 minutes
- **6 model seats** in parallel council debates, all free models
- **Failure memory** with structured attribution (UC Berkeley / RHO taxonomy)
- **90% reduction** in paid API costs through model routing
- **Zero human intervention** for routine failures since LaunchAgent wrapping

These aren't research numbers. They're from infrastructure that runs 24/7.

## References

- [Stanford/Singhua: Same model, 6x variance study](https://arxiv.org/abs/2502.03885)
- [UC Berkeley: AI Agent System Scaling](https://arxiv.org/abs/2502.06754)
- [Microsoft Research: RHO (Retrospective Harness Optimization)](https://arxiv.org/abs/2502.11718)
- Mitchell Hashimoto on harness engineering (YouTube, 6.2K views)
