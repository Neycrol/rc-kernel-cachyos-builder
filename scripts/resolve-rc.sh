#!/usr/bin/env bash
set -euo pipefail

rc_version="$(
  python3 - <<'PY'
import json
import os
from pathlib import Path
import sys
import urllib.request
import urllib.error

url = "https://www.kernel.org/releases.json"
timeout = 30
cache_path = Path(os.environ.get("KERNEL_RELEASES_CACHE", "scripts/releases.json"))

def load_data(path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)

try:
    with urllib.request.urlopen(url, timeout=timeout) as resp:
        data = json.load(resp)
except (urllib.error.URLError, TimeoutError) as exc:
    print(
        f"Failed to fetch {url} within {timeout}s: {exc}",
        file=sys.stderr,
    )
    if cache_path.exists():
        print(f"Using cached releases data from {cache_path}.", file=sys.stderr)
        data = load_data(cache_path)
    else:
        raise SystemExit(
            "Unable to fetch releases.json; please retry or provide cache via "
            "KERNEL_RELEASES_CACHE."
        )

for rel in data.get("releases", []):
    if rel.get("moniker") == "mainline":
        print(rel.get("version"))
        raise SystemExit(0)
raise SystemExit("mainline release not found")
PY
)"

is_rc="false"
rc_major=""

if [[ "${rc_version}" == *-rc* ]]; then
  is_rc="true"
  rc_major="${rc_version%%-*}"
  rc_major="$(echo "${rc_major}" | awk -F. '{print $1"."$2}')"
else
  echo "mainline is not an RC release: ${rc_version}" >&2
fi

output_file="${GITHUB_OUTPUT:-/dev/stdout}"
{
  echo "rc_version=${rc_version}"
  echo "rc_major=${rc_major}"
  echo "is_rc=${is_rc}"
} >> "${output_file}"
