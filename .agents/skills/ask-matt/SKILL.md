---
name: ask-matt
description: Ask which skill or flow fits your situation. A router over the skills in this repo.
disable-model-invocation: true
---
# Ask Matt

Can't remember every skill? Ask.

A **flow** = path through skills. Most follow one **main flow**; two **on-ramps** join it. Rest standalone or underlying vocabulary.

## The main flow: idea → ship

Usual route from idea to build.

1. **`/grill-with-docs`** — sharpen idea through interview. With **codebase**, start here: stateful, saves learning in `CONTEXT.md` + ADRs. No codebase? Use `/grill-me` (Standalone). Both use `/grilling`; `grill-with-docs` leaves paper trail.
2. **Branch — can every question be settled in conversation?** If runnable answer needed (state, business logic, visible UI), prototype via **`/handoff`** both ways (Crossing sessions):
   - **`/handoff`** out; open fresh session using file,
   - **`/prototype`** answer question with throwaway code,
   - **`/handoff`** findings back; reference from original idea thread.
3. **Branch — multi-session build?**
   - **Yes** → **`/to-spec`** (thread → spec), then **`/to-tickets`** (tracer-bullet tickets, each declaring **blocking edges**). Local tracker: one file/ticket under `.scratch/<feature>/issues/`, manually work blockers-first. Real tracker: native blocking links; grab any unblocked ticket. Run **`/implement`** per ticket, **clearing context between each one**.
   - **No** → **`/implement`** here, same context window.

   Either way, **`/implement`** drives **`/tdd`** internally, one red-green slice at time, then runs **`/code-review`**: two-axis diff review (Standards + Spec), before commit. Use **`/tdd`** alone for concrete test-first behaviour without full spec. Use **`/code-review`** alone to review branch/PR against fixed point.

### Context hygiene

Keep steps 1–3 in **one unbroken context window**. Don't compact/clear before `/to-tickets`; grilling, spec, tickets share thinking. Each `/implement` starts fresh from ticket.

Limit = **[smart zone](https://www.aihero.dev/ai-coding-dictionary/smart-zone)**: window (~120k tokens on state-of-the-art models) where reasoning stays sharp. Near limit before `/to-tickets`? Don't continue degraded; `/handoff`, then fresh thread.

## On-ramps

Starting situations generating work, then joining main flow.

- **Bugs and requests piling up** → **`/triage`**. Moves issues through triage roles, producing agent-ready issues for **`/implement`**.

  Triage only issues **you didn't create**: raw bug reports, incoming features, other arrivals. `/to-tickets` tickets already agent-ready; **don't triage them**.

- **Something's broken** → **`/diagnosing-bugs`**. For hard bugs: resistant, intermittent flakes, regressions between known-good states. No theory before **tight feedback loop**: one command already red on *this* bug. Then fix + regression test. Post-mortem hands to **`/improve-codebase-architecture`** when no good seam exists to lock bug down.

- **A huge, foggy effort — a greenfield project or a huge feature build, too big for one session** → **`/wayfinder`**, most demanding flow. When destination path invisible, charts **shared map** of **decision tickets** on issue tracker; resolves one-by-one, producing **decisions, not deliverables**, until path clears. **`/grill-with-docs`** sharpens one-session idea; wayfinder handles ideas too large to hold. Slower, denser: reserve for that, never well-scoped feature.

  When map clears, **it hands off, it doesn't build**. Join main flow at **`/to-spec`**, collapsing linked decisions into buildable plan; then `/to-tickets` + `/implement`. Map straight to `/implement` loses linked detail. Do so only if effort proved genuinely small: go straight to `/implement`.

## Codebase health

Upkeep, not feature work.

- **`/improve-codebase-architecture`** — run during spare moments; keep codebase agent-friendly. Surfaces **deepening opportunities**. Picking one _generates an idea_ for main flow at `/grill-with-docs`. Survey finds candidates; **`/codebase-design`** designs chosen candidate.

## Vocabulary underneath

Two model-invoked references beneath other skills; each source of truth for its vocabulary. Use directly when **words**, not process, are problem; or let skills invoke them.

- **`/domain-modeling`** — sharpen project *domain* language: challenge fuzzy terms, resolve overloaded words (\\"account\\" doing three jobs), record hard-to-reverse decisions as ADRs. `/grill-with-docs` uses it to keep `CONTEXT.md` clean glossary.
- **`/codebase-design`** — deep-module vocabulary (module, interface, depth, seam, adapter, leverage, locality) for module *shape*: much behaviour behind small interface at clean seam. `/tdd` + `/improve-codebase-architecture` use it.

## Crossing sessions

- **`/handoff`** — full thread or branch needed (e.g. `/prototype` session): compact conversation into markdown file. Don't continue there; **open a new session and reference that file**. Bridge between context windows, either direction. Use for **fresh session** with **current conversation preserved**.
- **`/compact`** (built-in) — remain in **same conversation**, summarizing earlier turns. Use at **intentional phase breaks** when verbatim history disposable. Never mid-phase; agent may lose direction. `/handoff` forks; `/compact` continues.

## Standalone

Outside main flow.

- **`/grill-me`** — same relentless interview as `/grill-with-docs`, for **no codebase**. Stateless: saves nothing locally, creates no `CONTEXT.md`. Sharpens plans/designs outside repos.
- **`/prototype`** — small throwaway program answering one design question: does state model work, what should UI look like? Throwaway immediately: keep answer, delete code. Main-flow step 2 detour; also use whenever paper can't settle design.
- **`/research`** — delegate reading to **background agent**. Investigates using **primary sources**, leaves cited Markdown file in repo. Keep working meanwhile. Feed result into main flow at `/grill-with-docs`; research informs thinking, doesn't replace it.
- **`/teach`** — learn concept across sessions, using current directory as stateful workspace.
- **`/writing-great-skills`** — reference for writing/editing skills well.

## Precondition

**`/setup-matt-pocock-skills`** — run before first engineering flow. Configures issue tracker, triage labels, doc layout expected by other skills. Custom issue trackers work.