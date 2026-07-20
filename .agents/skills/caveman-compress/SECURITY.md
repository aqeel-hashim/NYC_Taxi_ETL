# Security

## Snyk High Risk Rating

`caveman-compress` gets Snyk High Risk rating from static analysis heuristics. This document explains skill actions and limits.

### What triggers the rating

1. **subprocess usage**: Skill calls `claude` CLI via `subprocess.run()` as fallback when `ANTHROPIC_API_KEY` unset. Fixed argument list, no shell interpolation. User file content passes via stdin, not shell argument.

2. **File read/write**: Skill reads user-specified file, compresses it, writes result to same path. Saves `.original.md` backup beside it. Reads/writes no files outside user-specified path.

### What the skill does NOT do

- Never executes user file content as code
- No network requests except Anthropic's API (via SDK or CLI)
- No file access outside user-provided path
- No shell=True or string interpolation in subprocess calls
- No data collection/transmission beyond compressed file

### Auth behavior

If `ANTHROPIC_API_KEY` set, skill uses Anthropic Python SDK directly (no subprocess). Otherwise falls back to `claude` CLI using user's existing Claude desktop authentication.

### File size limit

Rejects files over 500KB before any API call.

### Reporting a vulnerability

Found genuine security issue? Open GitHub issue with label `security`.