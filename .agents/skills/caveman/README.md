# caveman

Smart caveman speech. Same brain, fewer tokens.

## What it does

Compress every model response into caveman prose. Drop articles, filler, pleasantries, hedging. Preserve all technical details, code blocks, error strings, symbols exactly. Cut output tokens 65% (measured), preserve full accuracy. Mode persists entire session until changed/stopped.

Six intensity levels:

| Level | What change |
|-------|-------------|
| `lite` | Drop filler/hedging. Full sentences. Professional, tight. |
| `full` | Default. Drop articles. Fragments OK. Short synonyms. |
| `ultra` | Bare fragments. Abbreviations (DB, auth, fn). Causality arrows. |
| `wenyan-lite` | Classical Chinese register, light compression. |
| `wenyan-full` | Maximum 文言文. 80-90% character reduction. |
| `wenyan-ultra` | Extreme classical compression. |

Auto-clarity: use normal prose for security warnings, irreversible-action confirmations, ambiguity-prone multi-step sequences, repeated questions. Resume afterward.

## How to invoke

```
/caveman              # full mode (default)
/caveman lite         # lighter compression
/caveman ultra        # extreme compression
/caveman wenyan       # classical Chinese
stop caveman          # back to normal prose
```

## Example output

Question: \"Why does my React component re-render?\"

Normal:
> Component re-renders because each render creates new object reference. Wrap it in `useMemo` to fix.

Caveman (full):
> New object ref each render. Inline object prop = new ref = re-render. Wrap in `useMemo`.

Caveman (ultra):
> Inline obj prop → new ref → re-render. `useMemo`.

## See also

- [`SKILL.md`](./SKILL.md) — full LLM instructions
- [Caveman README](../../README.md) — repo overview, install, benchmarks