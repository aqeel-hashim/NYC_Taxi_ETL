from __future__ import annotations

import os
import subprocess
from pathlib import Path


def test_verify_propagates_failed_tool(tmp_path: Path) -> None:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    (bin_dir / "uv").write_text("#!/usr/bin/env bash\nexit 9\n")
    (bin_dir / "docker").write_text("#!/usr/bin/env bash\nexit 0\n")
    for name in ("uv", "docker"):
        (bin_dir / name).chmod(0o755)
    env = os.environ | {"PATH": f"{bin_dir}:{os.environ['PATH']}"}
    result = subprocess.run(["./scripts/verify.sh"], cwd=Path.cwd(), env=env, check=False)
    assert result.returncode == 1


def test_verify_can_pass_with_stubbed_tools(tmp_path: Path) -> None:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    (bin_dir / "uv").write_text("#!/usr/bin/env bash\nexit 0\n")
    (bin_dir / "docker").write_text("#!/usr/bin/env bash\nexit 0\n")
    for name in ("uv", "docker"):
        (bin_dir / name).chmod(0o755)
    env = os.environ | {"PATH": f"{bin_dir}:{os.environ['PATH']}"}
    result = subprocess.run(["./scripts/verify.sh"], cwd=Path.cwd(), env=env, check=False)
    assert result.returncode == 0
