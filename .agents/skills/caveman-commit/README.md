# caveman-commit

Terse Conventional Commits. Why > what.

## What it does

Makes Conventional Commits messages. Subject ≤50 chars, hard cap 72. Imperative. Body only if *why* unclear or breaking change. No AI credit, \"this commit does X\", emoji unless project uses. Body mandatory for breaking changes, security fixes, data migrations, reverts — future debuggers need context.

Outputs message only. No stage, commit, amend.

## How to invoke

```
/caveman-commit
```

Also triggers on \"write a commit\", \"commit message\", \"generate commit\".

## Example output

Diff: user profile endpoint.

```
feat(api): add GET /users/:id/profile

Mobile client needs profile data without the full user payload
to reduce LTE bandwidth on cold-launch screens.

Closes #128
```

Diff: breaking API rename.

```
feat(api)!: rename /v1/orders to /v1/checkout

BREAKING CHANGE: clients on /v1/orders must migrate to /v1/checkout
before 2026-06-01. Old route returns 410 after that date.
```

## See also

- [`SKILL.md`](./SKILL.md) — full LLM instructions
- [Caveman README](../../README.md) — repo overview