# cavecrew

Decision guide: when delegate caveman subagents vs work inline.

## What it does

Guides main thread: caveman subagent or vanilla. Win: subagent results enter main context verbatim; caveman output ~1/3 vanilla size. Across 20 delegations, avoids context exhaustion.

Three subagents:

| Subagent | Job | Use when |
|----------|-----|----------|
| `cavecrew-investigator` | Locate code (read-only) | \"Where X defined / what calls Y / list Z uses\" |
| `cavecrew-builder` | Surgical edit, 1-2 files | Obvious scope, ≤2 files. Refuses 3+ files. |
| `cavecrew-reviewer` | Diff/file review | One-line findings, severity emoji |

Use vanilla `Explore` or `Code Reviewer` for prose, architecture commentary, rationale. Use main thread for one-line answers and 3+ file refactors.

Decision guide, not slash command. Activates when delegation mentioned.

## How to invoke

Triggers: \"delegate to subagent\", \"use cavecrew\", \"spawn investigator\", \"save context\", \"compressed agent output\".

## Example chaining

Locate → fix → verify (common):

1. `cavecrew-investigator` returns sites (`path:line — symbol — note`)
2. Main picks 1-2 sites; gives paths to `cavecrew-builder`
3. `cavecrew-reviewer` audits diff

Parallel scout: spawn 2-3 `cavecrew-investigator` calls one message, different angles (defs, callers, tests). Main aggregates.

## Model overrides

Default: `cavecrew-reviewer` and `cavecrew-investigator` pin `model: haiku` in frontmatter; `cavecrew-builder` lacks `model:` line (uses API session default). Set shell env vars before launching Claude Code to override:

| Env var | Agent |
|---|---|
| `CAVECREW_REVIEWER_MODEL` | `cavecrew-reviewer` |
| `CAVECREW_BUILDER_MODEL` | `cavecrew-builder` |
| `CAVECREW_INVESTIGATOR_MODEL` | `cavecrew-investigator` |

Example — reviewer on sonnet, others default:

```sh
export CAVECREW_REVIEWER_MODEL=sonnet
```

Use same model strings as Claude Code agent frontmatter (e.g. `haiku`, `sonnet`, `opus`).

Overrides patch only installed agent frontmatter `model:` line; prompt untouched, still receives upstream updates. Plugin installs only; standalone hooks lack local agent files. Unset/blank = no change. Patch persists until plugin update/reinstall.

## See also

- [`SKILL.md`](./SKILL.md) — full decision matrix, output contracts
- [`agents/cavecrew-investigator.md`](../../agents/cavecrew-investigator.md)
- [`agents/cavecrew-builder.md`](../../agents/cavecrew-builder.md)
- [`agents/cavecrew-reviewer.md`](../../agents/cavecrew-reviewer.md)
- [Caveman README](../../README.md) — repo overview