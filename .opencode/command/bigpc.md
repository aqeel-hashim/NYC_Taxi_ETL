---
description: Set current session to powerful Windows/WSL2 workstation profile
---

Set active machine profile to `bigpc` for remainder of current session.

Profile facts:

- Windows host; all project work runs inside Void Linux WSL2.
- Host has 16 CPU cores, 16 GiB RAM, powerful GPU.
- GPU model/runtime availability is unverified and Assignment 1 does not require GPU acceleration.
- Expected Assignment 1 mode is concurrent only when live Docker preflight confirms at least 8 GiB memory, 4 CPUs, and calculated disk headroom.
- Keep repository in WSL Linux filesystem, not `/mnt/c`, for container/filesystem performance.
- Windows browser trust and WSL trust stores are separate; follow mkcert WSL2 instructions.

Read and follow `docs/agents/machine-profiles.md`. Before resource-heavy work, verify WSL, Docker-visible CPU/RAM, free disk, and Docker access. Live measurements override profile expectations. Do not edit tracked files merely to record active profile.

Reply only: `Machine profile: bigpc.`
