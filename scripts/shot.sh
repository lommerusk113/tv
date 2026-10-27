#!/usr/bin/env bash
# Container only: screenshot the virtual screen. Default output: shots/shot.png
set -euo pipefail
cd "$(dirname "$0")/.."
out="${1:-shots/shot.png}"
mkdir -p "$(dirname "$out")"
import -window root "$out"
echo "$out"
