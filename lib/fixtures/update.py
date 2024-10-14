#!/usr/bin/env python3
import subprocess
import os.path

SKIP = ["./no-binary-no-build"]

# Update test fixtures using a newer version of uv
#
# This will use git to figure out when the lock file was originally created to
# ensure that the same dependency graph is being locked,
# just with a newer version of uv.


def find_roots():
    """Find all project roots with a uv.lock"""
    for root, _, files in os.walk("."):
        for filename in files:
            if filename == "uv.lock":
                yield root


def get_file_creation(path: str) -> str:
    proc = subprocess.run(
        ["git", "log", "--follow", "--format=%ad", "--date", "iso-strict", path],
        check=True,
        stdout=subprocess.PIPE,
    )
    return [line for line in proc.stdout.decode().split("\n") if line][-1]


def lock(root: str, exclude_newer: str):
    subprocess.run(
        ["uv", "lock", "--exclude-newer", exclude_newer], check=True, cwd=root
    )


if __name__ == "__main__":
    for root in find_roots():
        if root in SKIP:
            continue

        print(f"Updating lock for: {root}")
        exclude_newer = get_file_creation(os.path.join(root, "uv.lock"))
        lock(root, exclude_newer)
