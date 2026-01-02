#!/usr/bin/env bash
set -euo pipefail

base_config="${1:-}"
perf_config="${2:-}"

if [[ -z "${perf_config}" ]]; then
  echo "Usage: $0 <base.config> <perf.config>" >&2
  exit 1
fi

if [[ ! -f "${perf_config}" ]]; then
  echo "Perf config not found: ${perf_config}" >&2
  exit 1
fi

if [[ -n "${base_config}" && -f "${base_config}" ]]; then
  cp "${base_config}" .config
else
  make defconfig
fi

scripts/kconfig/merge_config.sh -m .config "${perf_config}"
make olddefconfig
