---
name: cavecrew
description: >
  Decision guide for delegating to caveman-style subagents. Tells the main
  thread WHEN to spawn `cavecrew-investigator` (locate code), `cavecrew-builder`
  (1-2 file edit), or `cavecrew-reviewer` (diff review) instead of doing the
  work inline or using vanilla `Explore`. Subagent output is caveman-compressed
  so the tool-result injected back into main context is ~60% smaller — main
  context lasts longer across long sessions.
  Trigger: "delegate to subagent", "use cavecrew", "spawn investigator/builder/reviewer",
  "save context", "compressed agent output".
---
Cavecrew = three caveman-output subagent presets. Same jobs as Anthropic defaults (`Explore`, edit-style agents, reviewer), but compressed tool results shrink main context.

## When to use cavecrew vs alternatives

| Task | Use |
|---|---|
| \"Find X definition / Y callers / Z uses\" | `cavecrew-investigator` |
| Same + suggestions/architecture | `Explore` (vanilla) |
| Surgical edit, ≤2 files, obvious scope | `cavecrew-builder` |
| New feature / 3+ files / cross-cutting refactor | Main thread or `feature-dev:code-architect` |
| Review diff, branch, or file for bugs | `cavecrew-reviewer` |
| Deep review with rationale + alternatives | `Code Reviewer` (vanilla) |
| Known one-line answer | Main thread, no subagent |

Rule: **want output in 1/3 tokens: cavecrew. Want prose: vanilla.**

## Why this exists (the real win)

Subagent results enter main context verbatim. Vanilla `Explore` returning 2k prose tokens costs 2k main-context tokens each time. `cavecrew-investigator` gives same finding in ~700. Across 20 delegations: context exhaustion vs task completion.

## Output contracts

Main thread may rely on:

**`cavecrew-investigator`**
```
<Header>:
- path:line — `symbol` — short note
totals: <counts>.
```
Or `No match.` Always path-first, line-attached, backticked symbols. Grep-safe with `path:\d+`.

**`cavecrew-builder`**
```
<path:line-range> — <change ≤10 words>.
verified: <re-read OK | mismatch @ path:line>.
```
Or: `too-big.` / `needs-confirm.` / `ambiguous.` / `regressed.` (terminal first token).

**`cavecrew-reviewer`**
```
path:line: <emoji> <severity>: <problem>. <fix>.
totals: N🔴 N🟡 N🔵 N❓
```
Or `No issues.` Findings sorted file → ascending line.

## Chaining patterns

**Locate → fix → verify** (common):
1. `cavecrew-investigator` returns sites.
2. Main thread selects 1-2; gives paths to `cavecrew-builder`.
3. `cavecrew-reviewer` audits diff.

**Parallel scout** (broad investigation):
Spawn 2-3 `cavecrew-investigator` calls together, different angles: defs, callers, tests. Main thread aggregates.

**Single-shot edit** (known site):
Skip investigator. Give exact path:line directly to `cavecrew-builder`.

## What NOT to do

- Don't use `cavecrew-builder` without known file. First investigator, else main thread wastes context.
- Don't chain `cavecrew-investigator → cavecrew-builder` for 5-file refactor. Builder returns `too-big.`; turn wasted.
- Don't ask `cavecrew-reviewer` for \"general feedback\". Findings only, no architecture opinions. Use `Code Reviewer`.
- Don't expect prose. Output structured, terse, maybe cryptic. If human reads directly, paraphrase.

## Auto-clarity (inherited)

Subagents switch caveman → normal English for security warnings, irreversible-action confirmations, or ambiguity-risk output. Then resume caveman.