---
name: caveman-commit
description: >
  Ultra-compressed commit message generator. Cuts noise from commit messages while preserving
  intent and reasoning. Conventional Commits format. Subject ≤50 chars, body only when \"why\"
  isn't obvious. Use when user says \"write a commit\", \"commit message\", \"generate commit\",
  \"/commit\", or invokes /caveman-commit. Auto-triggers when staging changes.
---
Terse, exact commit messages. Conventional Commits. No fluff. Why > what.

## Rules

**Subject line:**
- `<type>(<scope>): <imperative summary>`; `<scope>` optional
- Types: `feat`, `fix`, `refactor`, `perf`, `docs`, `test`, `chore`, `build`, `ci`, `style`, `revert`
- Imperative: \\"add\\", \\"fix\\", \\"remove\\"; not \\"added\\", \\"adds\\", \\"adding\\"
- ≤50 chars preferred, 72 hard cap
- No trailing period
- Match project capitalization after colon

**Body (only if needed):**
- Skip when subject explains all
- Add only for non-obvious *why*, breaking changes, migration notes, linked issues
- Wrap at 72 chars
- Bullets `-` not `*`
- Issues/PRs last: `Closes #42`, `Refs #17`

**What NEVER goes in:**
- \\"This commit does X\\", \\"I\\", \\"we\\", \\"now\\", \\"currently\\"; diff shows what
- \\"As requested by...\\"; use Co-authored-by trailer
- \\"Generated with Claude Code\\" or AI attribution, unless user rule requires `Assisted-by`/AI-attribution trailer
- Emoji unless project convention requires
- File name when scope already names it

## Examples

Diff: new user-profile endpoint; body explains why
- ❌ \\"feat: add a new endpoint to get user profile information from the database\\"
- ✅
  ```
  feat(api): add GET /users/:id/profile

  Mobile client needs profile data without the full user payload
  to reduce LTE bandwidth on cold-launch screens.

  Closes #128
  ```

Diff: breaking API change
- ✅
  ```
  feat(api)!: rename /v1/orders to /v1/checkout

  BREAKING CHANGE: clients on /v1/orders must migrate to /v1/checkout
  before 2026-06-01. Old route returns 410 after that date.
  ```

## Auto-Clarity

Always include body for: breaking changes, security fixes, data migrations, anything reverting a prior commit. Never compress these into subject-only — future debuggers need the context.

## Boundaries

Only generates the commit message. Does not run `git commit`, stage files, or amend. Output message as paste-ready code block. \\"stop caveman-commit\\" or \\"normal mode\\": restore verbose commit style.