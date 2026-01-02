#!/usr/bin/env bash
set -euo pipefail

rc_version="$({
  curl -fsSL https://www.kernel.org/releases.json | python3 - <<'PY'
import json
import sys

data = json.load(sys.stdin)
for rel in data.get("releases", []):
    if rel.get("moniker") == "mainline":
        print(rel.get("version"))
        raise SystemExit(0)
raise SystemExit("mainline release not found")
PY
} )"

if [[ "${rc_version}" != *-rc* ]]; then
  echo "mainline is not an RC release: ${rc_version}" >&2
  exit 1
fi

rc_major="${rc_version%%-*}"
rc_major="$(echo "${rc_major}" | awk -F. '{print $1"."$2}')"

output_file="${GITHUB_OUTPUT:-/dev/stdout}"
{
  echo "rc_version=${rc_version}"
  echo "rc_major=${rc_major}"
} >> "${output_file}"
