# Council Debate

## Problem

Ask one model a hard architectural question and you get one answer. That answer has blind spots. The model doesn't know what it doesn't know. It presents one path confidently, even when alternatives are better.

A single Claude 4 prompt costs money and gives you a monoculture answer. You pay for the model, not the thinking.

## Solution

Run 3-6 models in parallel on the same question. Give each the same context. Let them disagree. Then synthesize the disagreements into a final recommendation that explicitly calls out tradeoffs.

The models are free (Groq, OpenRouter free tier, local Ollama). Only the synthesis step uses a paid model, and only after free models have done the exploration.

## What We Learned

We run council debates on every architectural decision for our agent infrastructure. The disagreements are the value:

- "Use Redis for caching" (3 seats agree, 2 say "just write to a file, don't add infrastructure")
- "Refactor into microservices" (2 seats for, 4 against — "monolith with clear module boundaries is sufficient at your scale")
- "Add a message queue" (council split 3-3, synthesis recommends "defer until request rate exceeds 100/min — current rate is 12/min")

Without the debate, we would have added Redis, split into microservices, and deployed a message queue. All unnecessary at our scale. The council saved us months of infrastructure work we didn't need.

The harness innovation is not "use multiple models." It's the structure: parallel analysis, explicit disagreement resolution, synthesis by a lead reviewer, trajectory logging of every council result.

## Usage

```bash
# Set up your API keys
export OPENROUTER_API_KEY="sk-or-..."
export GROQ_API_KEY="gsk_..."

# Run a council debate
npx tsx council-debate.ts "Should we use PostgreSQL or SQLite for the user database?"

# With a specific topic context file
npx tsx council-debate.ts --context docs/architecture.md "How should we handle authentication?"
```

## How It Works

1. **Context loading:** Enriches the question with relevant docs if provided
2. **Parallel seats:** Each model gets the same task with a direct system prompt: "Answer ONLY the task. Prefer concrete, actionable steps."
3. **Disagreement detection:** The synthesis step identifies where models disagreed and why
4. **Tradeoff surfacing:** The final output lists each option with pros, cons, and when it makes sense
5. **Trajectory logging:** Every council result gets logged with seat participation counts

## Customization

Edit the seat configuration in the template to match your available models and API keys:

- Replace model names with your preferred providers
- Add or remove seats based on how many free models you have access to
- Adjust per-seat character limits based on your context window budget

## Tradeoffs

- **Pro:** Better decisions than any single model, especially for architectural questions
- **Pro:** Nearly free (all free models, only synthesis uses paid)
- **Con:** Takes 30-90 seconds to run all seats in parallel
- **Con:** Some free model seats may fail (the template handles this gracefully)
- **Con:** Not useful for simple yes/no questions. Use for decisions with genuine tradeoffs.
