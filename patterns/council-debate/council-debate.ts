#!/usr/bin/env npx tsx
/**
 * council-debate.ts — Multi-model council for architectural decisions.
 *
 * Runs 3-6 models in parallel on the same question, surfaces disagreements,
 * and synthesizes a final recommendation with explicit tradeoffs.
 *
 * Usage:
 *   npx tsx council-debate.ts "Should we use Redis or SQLite for caching?"
 *   npx tsx council-debate.ts --context docs/architecture.md "Best auth approach?"
 *
 * Prerequisites:
 *   - OPENROUTER_API_KEY environment variable
 *   - GROQ_API_KEY environment variable (optional, for additional seats)
 *   - Ollama running locally (optional, for privacy-preserving seat)
 */

import { execSync } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';

// ─── Configuration ───────────────────────────────────────────────

const COUNCIL_SEATS: CouncilSeat[] = [
  {
    name: 'Seat-1-Free',
    provider: 'openrouter',
    model: 'google/gemini-2.5-flash-lite:free',
    enabled: !!process.env.OPENROUTER_API_KEY,
  },
  {
    name: 'Seat-2-Alternate',
    provider: 'openrouter',
    model: 'mistralai/mistral-nemo:free',
    enabled: !!process.env.OPENROUTER_API_KEY,
  },
  {
    name: 'Seat-3-Groq',
    provider: 'groq',
    model: 'llama-3.3-70b-versatile',
    enabled: !!process.env.GROQ_API_KEY,
  },
  {
    name: 'Seat-4-Ollama',
    provider: 'ollama',
    model: process.env.COUNCIL_OLLAMA_MODEL || 'qwen2.5:14b',
    enabled: true, // Assumes local Ollama
  },
  {
    name: 'Seat-5-DeepSeek',
    provider: 'openrouter',
    model: 'deepseek/deepseek-chat-v4:free',
    enabled: !!process.env.OPENROUTER_API_KEY,
  },
];

const SYNTHESIS_MODEL = {
  provider: 'openrouter' as const,
  model: process.env.COUNCIL_SYNTHESIS_MODEL || 'google/gemini-2.5-flash-lite:free',
};

const SEAT_MAX_CHARS = parseInt(process.env.COUNCIL_SEAT_MAX || '1200', 10);

// ─── Types ───────────────────────────────────────────────────────

interface CouncilSeat {
  name: string;
  provider: 'openrouter' | 'groq' | 'ollama';
  model: string;
  enabled: boolean;
}

interface SeatResult {
  seat: string;
  model: string;
  response: string;
  error?: string;
}

// ─── Model Calling ───────────────────────────────────────────────

async function callOpenRouter(model: string, prompt: string): Promise<string> {
  const apiKey = process.env.OPENROUTER_API_KEY;
  if (!apiKey) throw new Error('OPENROUTER_API_KEY not set');

  const response = await fetch('https://openrouter.ai/api/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model,
      messages: [
        { role: 'system', content: 'Answer ONLY the task below. Prefer concrete, actionable steps. Keep your response under 400 words.' },
        { role: 'user', content: prompt },
      ],
      max_tokens: 600,
      temperature: 0.7,
    }),
  });

  if (!response.ok) {
    throw new Error(`OpenRouter ${model}: ${response.status} ${response.statusText}`);
  }

  const data = await response.json();
  return data.choices?.[0]?.message?.content || '(empty response)';
}

async function callGroq(model: string, prompt: string): Promise<string> {
  const apiKey = process.env.GROQ_API_KEY;
  if (!apiKey) throw new Error('GROQ_API_KEY not set');

  const response = await fetch('https://api.groq.com/openai/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model,
      messages: [
        { role: 'system', content: 'Answer ONLY the task below. Prefer concrete, actionable steps. Keep your response under 400 words.' },
        { role: 'user', content: prompt },
      ],
      max_tokens: 600,
      temperature: 0.7,
    }),
  });

  if (!response.ok) {
    throw new Error(`Groq ${model}: ${response.status} ${response.statusText}`);
  }

  const data = await response.json();
  return data.choices?.[0]?.message?.content || '(empty response)';
}

async function callOllama(model: string, prompt: string): Promise<string> {
  const response = await fetch('http://localhost:11434/api/generate', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model,
      prompt: `Answer ONLY the task below. Prefer concrete, actionable steps. Keep your response under 400 words.\n\n${prompt}`,
      stream: false,
      options: { num_predict: 600, temperature: 0.7 },
    }),
  });

  if (!response.ok) {
    throw new Error(`Ollama ${model}: ${response.status} ${response.statusText}`);
  }

  const data = await response.json();
  return data.response || '(empty response)';
}

async function callModel(seat: CouncilSeat, prompt: string): Promise<SeatResult> {
  try {
    let response: string;
    switch (seat.provider) {
      case 'openrouter':
        response = await callOpenRouter(seat.model, prompt);
        break;
      case 'groq':
        response = await callGroq(seat.model, prompt);
        break;
      case 'ollama':
        response = await callOllama(seat.model, prompt);
        break;
      default:
        throw new Error(`Unknown provider: ${seat.provider}`);
    }

    // Truncate to seat max
    const truncated = response.length > SEAT_MAX_CHARS
      ? response.substring(0, SEAT_MAX_CHARS) + '...'
      : response;

    return { seat: seat.name, model: seat.model, response: truncated };
  } catch (err: any) {
    return { seat: seat.name, model: seat.model, response: '', error: err.message };
  }
}

// ─── Synthesis ───────────────────────────────────────────────────

async function synthesize(question: string, results: SeatResult[]): Promise<string> {
  const successfulResults = results.filter(r => !r.error && r.response);
  const failedSeats = results.filter(r => r.error);

  const opinions = successfulResults
    .map((r, i) => `### Opinion ${i + 1} (${r.seat} / ${r.model})\n${r.response}`)
    .join('\n\n');

  const failures = failedSeats.length > 0
    ? `\n\n(Note: ${failedSeats.length} seat(s) failed: ${failedSeats.map(s => s.seat).join(', ')})\n`
    : '';

  const synthesisPrompt = `You are synthesizing a council debate on the question:

"${question}"

The council had ${successfulResults.length} responses. Identify where they agree, where they disagree, and produce a final recommendation with explicit tradeoffs. If models disagree, explain why and what conditions would favor each approach.

Council opinions:

${opinions}
${failures}
Output format:
1. **Areas of agreement**
2. **Areas of disagreement** (explain why)
3. **Final recommendation** with tradeoffs
4. **When to reconsider** (conditions that would change the recommendation)`;

  // Use synthesis model (typically the best available free model)
  if (SYNTHESIS_MODEL.provider === 'openrouter') {
    return callOpenRouter(SYNTHESIS_MODEL.model, synthesisPrompt);
  }
  return callGroq(SYNTHESIS_MODEL.model, synthesisPrompt);
}

// ─── Main ────────────────────────────────────────────────────────

async function main() {
  const args = process.argv.slice(2);
  let question = '';
  let contextFile = '';

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--context' && i + 1 < args.length) {
      contextFile = args[++i];
    } else if (!question) {
      question += args[i] + ' ';
    }
  }
  question = question.trim();

  if (!question) {
    console.error('Usage: npx tsx council-debate.ts [--context file] "your question"');
    process.exit(1);
  }

  // Load context if provided
  if (contextFile && fs.existsSync(contextFile)) {
    const context = fs.readFileSync(contextFile, 'utf-8').substring(0, 2000);
    question = `Context:\n${context}\n\nQuestion: ${question}`;
  }

  const activeSeats = COUNCIL_SEATS.filter(s => s.enabled);
  if (activeSeats.length < 2) {
    console.error('Need at least 2 active council seats. Set OPENROUTER_API_KEY or GROQ_API_KEY.');
    process.exit(1);
  }

  console.log(`\n=== COUNCIL DEBATE ===`);
  console.log(`Question: ${question.length > 200 ? question.substring(0, 200) + '...' : question}`);
  console.log(`Seats: ${activeSeats.map(s => `${s.name} (${s.model})`).join(', ')}`);
  console.log(`Running ${activeSeats.length} models in parallel...\n`);

  // Run all seats in parallel
  const startTime = Date.now();
  const promises = activeSeats.map(seat => callModel(seat, question));
  const results = await Promise.all(promises);
  const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);

  // Report per-seat results
  console.log(`--- Seat Results (${elapsed}s) ---\n`);
  for (const result of results) {
    if (result.error) {
      console.log(`[FAIL] ${result.seat} (${result.model}): ${result.error}\n`);
    } else {
      const preview = result.response.length > 300 ? result.response.substring(0, 300) + '...' : result.response;
      console.log(`[OK]   ${result.seat} (${result.model}):\n${preview}\n`);
    }
  }

  const okCount = results.filter(r => !r.error).length;
  const totalCount = results.length;

  // Synthesize
  console.log(`--- Synthesis (${okCount}/${totalCount} seats contributing) ---\n`);

  if (okCount === 0) {
    console.log('All seats failed. Cannot synthesize.\n');
    process.exit(1);
  }

  try {
    const synthesis = await synthesize(question, results);
    console.log(synthesis);
    console.log(`\nCouncil complete. ${okCount}/${totalCount} seats, ${elapsed}s total.\n`);
  } catch (err: any) {
    console.log(`Synthesis failed: ${err.message}`);
    console.log('\nRaw seat responses above.\n');
  }
}

main().catch(err => {
  console.error(`Council debate crashed: ${err.message}`);
  process.exit(1);
});
