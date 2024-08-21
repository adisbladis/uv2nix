#!/usr/bin/env bash
set -euo pipefail
result=$(nix-build --no-out-link ./highlightjs.nix)
cp -f "$result"/highlight.min.js ../theme/highlight.js
