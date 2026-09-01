#!/usr/bin/env bash
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v busted >/dev/null 2>&1; then
  echo "ERROR: busted not found. Install with: luarocks install busted"
  echo "Or run in Docker: docker build -f Dockerfile.test -t ae2-es2-test . && docker run --rm ae2-es2-test"
  exit 1
fi

busted "$@"
