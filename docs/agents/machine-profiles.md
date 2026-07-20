# Machine Profiles

Project OpenCode commands set machine context for current conversation only:

- `/bigpc`: Windows host, Void Linux WSL2, 16 CPU cores, 16 GiB RAM, GPU.
- `/smallpc`: native Void Linux, 4 CPU cores, 3.8 GiB RAM, no swap.

Invoke one command after starting a fresh OpenCode session. Switching profile never edits tracked files. Profile remains active for conversation; live preflight remains source of truth.

## Required Preflight

Before cluster creation, image builds, full-data ETL, release smoke, or benchmarks, verify:

```bash
uname -srmo
nproc
free -h
df -h .
docker info --format '{{.ServerVersion}}|{{.NCPU}}|{{.MemTotal}}|{{.Architecture}}|{{.OperatingSystem}}'
```

Stop and diagnose when selected profile materially differs from measurements. Never choose resource mode from command label alone.

Assignment 1 auto-selection remains:

- Concurrent candidate: Docker sees at least 8 GiB RAM, at least 4 CPUs, and calculated disk need plus 20% headroom.
- Staged candidate: lower Docker resources.
- Unsupported: measured staged service envelope cannot retain 20% memory headroom. Use documented stage-by-stage proof; never claim unsupported profile passed.

## Big PC

- Run every repository command inside Void Linux WSL2, not Windows PowerShell/CMD.
- Clone repository under WSL Linux filesystem such as `~/Dev/NYC_Taxi_ETL`; avoid `/mnt/c` because bind mounts, file watchers, permissions, and small-file workloads are slower.
- Verify Docker integration from WSL. Host capacity does not prove Docker backend exposes all 16 CPUs/16 GiB.
- Expected profile is concurrent, subject to preflight.
- GPU is optional/unverified. Do not add CUDA, GPU container runtime, or GPU dependencies unless later requirement needs them and `nvidia-smi` works inside WSL.
- `mkcert` CA installed in WSL does not automatically trust Windows browser. Export/install CA in Windows trust store only after explicit user confirmation; keep WSL trust configured for in-cluster tooling.
- Prefer WSL-native Git, SSH, Python, Docker CLI, and project tools. Avoid mixing Windows and Linux executable paths.

## Small PC

- Native Void Linux `x86_64`.
- Known baseline: 4 CPUs, 3.8 GiB RAM, no swap; Docker 29.6.1 previously saw same CPU/RAM.
- Expected profile is staged. Keep one heavy ETL pod; scale presentation services down during transforms.
- Existing system Python 3.14 is not project runtime. Use planned repo-local uv-managed Python 3.12.
- Full-stack/full-data runtime targets remain conditional on measured envelope. Stage-by-stage evidence is acceptable when hardware cannot fit services together.

## Benchmark Records

Every benchmark or resource claim must record:

- Active profile name.
- `uname`, CPU, host RAM, Docker-visible RAM/CPU, free disk.
- WSL2 versus native Linux.
- Resource mode: staged/concurrent/stage-by-stage.
- Dataset/source versions, image/chart/tool versions.
- Peak memory, pod restarts/OOM, elapsed time, query-cache state.

Never compare Big PC and Small PC timings without labeling both environments.
