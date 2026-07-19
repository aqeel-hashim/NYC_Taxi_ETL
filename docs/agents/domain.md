# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

This repository uses a multi-context layout.

## Before exploring, read these

- **`CONTEXT-MAP.md`** at the repo root; it points at one `CONTEXT.md` per context. Read each one relevant to the topic.
- **`docs/adr/`** for system-wide decisions that touch the work area.
- **`src/<context>/docs/adr/`** for relevant context-scoped decisions.

If any of these files don't exist, **proceed silently**. Don't flag their absence or suggest creating them upfront. The `/domain-modeling` skill, reached via `/grill-with-docs` and `/improve-codebase-architecture`, creates them lazily when terms or decisions are resolved.

## File structure

```text
/
├── CONTEXT-MAP.md
├── docs/adr/
└── src/
    ├── <context-a>/
    │   ├── CONTEXT.md
    │   └── docs/adr/
    └── <context-b>/
        ├── CONTEXT.md
        └── docs/adr/
```

## Use the glossary's vocabulary

When output names a domain concept, such as in an issue title, refactor proposal, hypothesis, or test name, use the term defined in the relevant `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If a needed concept isn't in the glossary, reconsider whether the language belongs to the project or note the genuine gap for `/domain-modeling`.

## Flag ADR conflicts

If output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders), but worth reopening because..._
