#!/usr/bin/env bash
set -euo pipefail

rc_version="$(
  python3 - <<'PY'
import json
import urllib.request

with urllib.request.urlopen("https://www.kernel.org/releases.json") as resp:
    data = json.load(resp)

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
