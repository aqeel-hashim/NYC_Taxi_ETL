# OpenCode Instructions

## Non-Negotiables

- Use `/caveman ultra` for all prose responses: maximum terseness, exact technical substance, no filler. Keep code, commit messages, and PR text normal.
- Before non-trivial work, ask one concise batch covering any unresolved scope, acceptance criteria, technology choices, or constraints. Skip only when request or repo already answers them; never guess user preference.
- Follow workflow in this order: design, architect, document, execute, review.
- Never push. User reviews work and pushes to remote.
- When branching is requested, use standard GitFlow: `main`, `develop`, `feature/*`, `release/*`, `hotfix/*`.

## Machine Context

- Fresh session should invoke project command `/bigpc` or `/smallpc`. If neither profile is stated, ask once before resource-heavy work; do not infer from repository files.
- Commands set conversation context only. Live `uname`, CPU/RAM/disk, and Docker-visible resources override profile expectations. Details: `docs/agents/machine-profiles.md`.
- `bigpc`: Windows host; run everything inside Void Linux WSL2; 16 CPU cores, 16 GiB RAM, GPU; keep clone in WSL filesystem, not `/mnt/c`.
- `smallpc`: native Void Linux; 4 CPU cores, 3.8 GiB RAM, no swap; expect staged or stage-by-stage execution.
- GPU is not part of Assignment 1. Never add GPU/CUDA dependencies based only on `/bigpc`.

## Scope And Sources

- This repo demos both assignments in `Docs/Data_Engineering_Assessments.docx.txt`; neither assignment is optional.
- Treat `Docs/Data_Engineering_Assessments.docx.txt` as requirements and `GUIDE.md` as project workflow/layout guidance. If executable config later conflicts with prose, verify intent with user.
- Keep root `README.md` for project-wide overview and decisions. Keep implementation details in `Assignment_1/README.md` and `Assignment_2/README.md`.
- Use public NYC Yellow Taxi records. Direct Parquet pattern: `https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_YYYY-MM.parquet`.
- Ask before resolving unclear requirements. Record agreed assumptions in relevant assignment README so demo can explain them.

## Demo Requirements

- Assignment 1: Python 3.10+, Bash `setup.sh`, virtual environment, dependency install, PostgreSQL in Docker, and at least two downloaded months via `curl` or `wget`.
- Assignment 1 model: `schema.sql` defines `fact_taxi_trips` plus at least three dimensions, loaded through a modern orchestrator; structured logs include start/end times and row counts; orchestrator logs or alerts failures.
- Assignment 1 output: queries for average fare per mile, peak ride hours, revenue by payment type; one-page Streamlit or Superset dashboard.
- Assignment 2: multi-broker Kafka is mandatory despite general resource-limit allowance. Topic must be `taxi-trips-stream` with multiple partitions.
- Assignment 2 flow: producer sends 10-50 events/second; consumer computes sliding-window aggregation, stores raw events, and upserts aggregates.
- Assignment 2 observability: Prometheus and Grafana must show cluster health, consumer lag, and throughput.
- Assignment 2 docs: include system diagram; production design explains scaling to 50,000 events/second, out-of-order events, and backpressure.
- Synthetic data is allowed only when source data is unavailable. Stage-by-stage demo is allowed when local resources cannot run every service together.

## Current State

- Repo currently contains documentation plus project-local OpenCode machine-profile commands; no application manifests, source, CI, tests, formatter, or verified developer commands. Do not invent application commands.
- When adding first executable tooling, document exact setup, focused test, lint, typecheck, run, and teardown commands in relevant README; update this file with non-obvious command order or prerequisites.

## GitHub And Domain Docs

- Issues and PRDs use GitHub Issues through `gh`; external PRs use same triage flow. Details: `docs/agents/issue-tracker.md`.
- Triage labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. Details: `docs/agents/triage-labels.md`.
- If present, read relevant `CONTEXT-MAP.md`, context `CONTEXT.md`, and ADRs before design changes. If absent, proceed silently. Details: `docs/agents/domain.md`.

<!-- code-review-graph MCP tools -->
## MCP Tools: code-review-graph

**IMPORTANT: This project has a knowledge graph. ALWAYS use the
code-review-graph MCP tools BEFORE using Grep/Glob/Read to explore
the codebase.** The graph is faster, cheaper (fewer tokens), and gives
you structural context (callers, dependents, test coverage) that file
scanning cannot.

### When to use graph tools FIRST

- **Exploring code**: `semantic_search_nodes_tool` or `query_graph_tool` instead of Grep
- **Understanding impact**: `get_impact_radius_tool` instead of manually tracing imports
- **Code review**: `detect_changes_tool` + `get_review_context_tool` instead of reading entire files
- **Finding relationships**: `query_graph_tool` with callers_of/callees_of/imports_of/tests_for
- **Architecture questions**: `get_architecture_overview_tool` + `list_communities_tool`

Fall back to Grep/Glob/Read **only** when the graph doesn't cover what you need.

### Key Tools

| Tool | Use when |
| ------ | ---------- |
| `detect_changes_tool` | Reviewing code changes — gives risk-scored analysis |
| `get_review_context_tool` | Need source snippets for review — token-efficient |
| `get_impact_radius_tool` | Understanding blast radius of a change |
| `get_affected_flows_tool` | Finding which execution paths are impacted |
| `query_graph_tool` | Tracing callers, callees, imports, tests, dependencies |
| `semantic_search_nodes_tool` | Finding functions/classes by name or keyword |
| `get_architecture_overview_tool` | Understanding high-level codebase structure |
| `refactor_tool` | Planning renames, finding dead code |

### Workflow

1. The graph auto-updates on file changes (via hooks).
2. Use `detect_changes_tool` for code review.
3. Use `get_affected_flows_tool` to understand impact.
4. Use `query_graph_tool` pattern="tests_for" to check coverage.
