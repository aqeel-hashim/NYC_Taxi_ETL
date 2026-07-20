---
description: Set current session to constrained native Void Linux profile
---

Set active machine profile to `smallpc` for remainder of current session.

Profile facts:

- Native Void Linux `x86_64` host.
- 4 CPU cores, 3.8 GiB RAM, no swap.
- Docker currently sees 4 CPUs and about 3.8 GiB RAM.
- Large disk is available, but live free space still requires verification.
- Expected Assignment 1 mode is staged; never assume full-stack concurrency fits.
- Host Python 3.14 is not project runtime; planned project runtime is uv-managed Python 3.12.

Read and follow `docs/agents/machine-profiles.md`. Before resource-heavy work, verify Docker-visible CPU/RAM, free disk, and Docker access. Live measurements override profile expectations. Do not edit tracked files merely to record active profile.

Reply only: `Machine profile: smallpc.`
