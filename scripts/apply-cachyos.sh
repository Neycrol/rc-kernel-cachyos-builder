#!/usr/bin/env bash
set -euo pipefail

major="${1:-}"
if [[ -z "${major}" ]]; then
  echo "Usage: $0 <major>" >&2
  exit 1
fi

if [[ ! -f Makefile ]]; then
  echo "Run this script from the kernel source tree." >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
local_patch_dir="${repo_root}/patches/${major}"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

strict_patch="${STRICT_PATCH:-0}"

apply_patch_file() {
  local patch_file="$1"
  local name="$2"
  local reject_file="${tmp_dir}/${name}.rej"

  rm -f "${reject_file}"
  if patch -p1 --forward --batch --no-backup-if-mismatch --reject-file "${reject_file}" < "${patch_file}"; then
    rm -f "${reject_file}"
    return 0
  fi

  if [[ -s "${reject_file}" ]]; then
    echo "Patch ${name} had rejects (saved to ${reject_file})." >&2
  else
    echo "Patch ${name} failed to apply." >&2
  fi

  if [[ "${strict_patch}" == "1" ]]; then
    exit 1
  fi

  return 0
}

apply_url() {
  local url="$1"
  local name="$2"
  local patch_file="${tmp_dir}/${name}.patch"

  echo "Applying ${name}"
  curl -fsSL "${url}" -o "${patch_file}"
  apply_patch_file "${patch_file}" "${name}"
}

apply_url_allow_applied() {
  local url="$1"
  local name="$2"
  local patch_file="${tmp_dir}/${name}.patch"

  echo "Applying ${name}"
  curl -fsSL "${url}" -o "${patch_file}"

  if patch -p1 --reverse --dry-run --batch --no-backup-if-mismatch < "${patch_file}" >/dev/null 2>&1; then
    echo "Patch ${name} already applied, skipping."
    return 0
  fi

  apply_patch_file "${patch_file}" "${name}"
}

apply_file_allow_applied() {
  local patch_file="$1"
  local name="$2"

  echo "Applying ${name} (local override)"

  if patch -p1 --reverse --dry-run --batch --no-backup-if-mismatch < "${patch_file}" >/dev/null 2>&1; then
    echo "Patch ${name} already applied, skipping."
    return 0
  fi

  apply_patch_file "${patch_file}" "${name}"
}

list_patch_urls() {
  local path="$1"

  python3 - "$path" <<'PY'
import json
import os
import re
import sys
import urllib.request

path = sys.argv[1]
url = f"https://api.github.com/repos/CachyOS/kernel-patches/contents/{path}"
req = urllib.request.Request(url, headers={"User-Agent": "rc-kernel-cachyos-builder"})
token = os.environ.get("GITHUB_TOKEN")
if token:
    req.add_header("Authorization", f"token {token}")
try:
    with urllib.request.urlopen(req) as resp:
        data = json.load(resp)
except Exception as exc:
    print(f"Failed to query {url}: {exc}", file=sys.stderr)
    sys.exit(2)

rx = re.compile(r"^\d{4}.*\.patch$")
files = []
for item in data:
    if item.get("type") != "file":
        continue
    name = item.get("name", "")
    if rx.match(name):
        files.append((name, item.get("download_url", "")))

for name, download_url in sorted(files, key=lambda item: item[0]):
    if download_url:
        print(download_url)
PY
}

apply_patch_series() {
  local path="$1"
  local urls

  if ! urls="$(list_patch_urls "${path}")"; then
    echo "Failed to query patch list at ${path}" >&2
    exit 1
  fi

  if [[ -z "${urls}" ]]; then
    return 1
  fi

  echo "Applying CachyOS patch series from ${path}"
  while IFS= read -r url; do
    [[ -z "${url}" ]] && continue
    local filename="${url##*/}"
    local name="${filename%.patch}"
    local local_patch="${local_patch_dir}/${filename}"
    if [[ -f "${local_patch}" ]]; then
      apply_file_allow_applied "${local_patch}" "${name}"
    else
      apply_url_allow_applied "${url}" "${name}"
    fi
  done <<< "${urls}"
  return 0
}

resolve_patch_url() {
  local path="$1"
  shift

  python3 - "$path" "$@" <<'PY'
import json
import os
import re
import sys
import urllib.request

path = sys.argv[1]
patterns = sys.argv[2:]
url = f"https://api.github.com/repos/CachyOS/kernel-patches/contents/{path}"
req = urllib.request.Request(url, headers={"User-Agent": "rc-kernel-cachyos-builder"})
token = os.environ.get("GITHUB_TOKEN")
if token:
    req.add_header("Authorization", f"token {token}")
try:
    with urllib.request.urlopen(req) as resp:
        data = json.load(resp)
except Exception as exc:
    print(f"Failed to query {url}: {exc}", file=sys.stderr)
    sys.exit(2)

files = [item for item in data if item.get("type") == "file"]
for pat in patterns:
    rx = re.compile(pat)
    for item in files:
        name = item.get("name", "")
        if rx.search(name):
            print(item.get("download_url", ""))
            sys.exit(0)

sys.exit(1)
PY
}

require_patch_url() {
  local path="$1"
  local name="$2"
  shift 2

  local url
  if ! url="$(resolve_patch_url "${path}" "$@")"; then
    local rc=$?
    if [[ ${rc} -eq 2 ]]; then
      echo "Failed to query patch list at ${path}" >&2
    else
      echo "No patch matched in ${path} for patterns: $*" >&2
    fi
    exit 1
  fi

  if [[ -z "${url}" ]]; then
    echo "Empty download URL resolved for ${name}" >&2
    exit 1
  fi

  echo "Resolved ${name} -> ${url}"
  local filename="${url##*/}"
  local local_patch="${local_patch_dir}/${filename}"
  if [[ -f "${local_patch}" ]]; then
    apply_file_allow_applied "${local_patch}" "${name}"
  else
    apply_url_allow_applied "${url}" "${name}"
  fi
}

if ! apply_patch_series "${major}"; then
  require_patch_url "${major}/all" "cachyos-base" 'cachyos-base.*\.patch$'
fi

if ! require_patch_url "${major}/sched" "bore-sched" 'bore-cachy.*\.patch$' 'bore.*\.patch$'; then
  exit 1
fi

bbr_url=""
for path in "${major}" "${major}/misc"; do
  if bbr_url="$(resolve_patch_url "${path}" 'bbr3.*\.patch$')"; then
    break
  fi
  if [[ $? -eq 2 ]]; then
    echo "Failed to query patch list at ${path}" >&2
    exit 1
  fi
done

if [[ -z "${bbr_url}" ]]; then
  echo "BBRv3 patch not found for ${major}." >&2
  exit 1
fi

echo "Resolved bbr3 -> ${bbr_url}"
apply_url_allow_applied "${bbr_url}" "bbr3"
