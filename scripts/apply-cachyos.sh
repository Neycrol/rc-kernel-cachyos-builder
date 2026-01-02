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

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

apply_url() {
  local url="$1"
  local name="$2"
  local patch_file="${tmp_dir}/${name}.patch"

  echo "Applying ${name}"
  curl -fsSL "${url}" -o "${patch_file}" || return 1
  patch -p1 --forward < "${patch_file}" || return 1
}

base_repo="https://raw.githubusercontent.com/CachyOS/kernel-patches/master/${major}"

apply_url "${base_repo}/all/0001-cachyos-base-all.patch" "cachyos-base"

if ! apply_url "${base_repo}/sched/0001-bore-cachy.patch" "bore-sched"; then
  apply_url "${base_repo}/sched/0001-bore.patch" "bore-sched"
fi

bbr_patch=""
for candidate in 0003-bbr3.patch 0004-bbr3.patch 0005-bbr3.patch; do
  url="${base_repo}/${candidate}"
  if curl -fsSL "${url}" -o "${tmp_dir}/${candidate}"; then
    bbr_patch="${tmp_dir}/${candidate}"
    echo "Found BBRv3 patch: ${candidate}"
    patch -p1 --forward < "${bbr_patch}"
    break
  fi
done

if [[ -z "${bbr_patch}" ]]; then
  echo "BBRv3 patch not found for ${major}." >&2
  exit 1
fi
