#!/usr/bin/env bash
set -euo pipefail

rc_version="${1:-}"
rc_major="${2:-}"

if [[ -z "${rc_version}" || -z "${rc_major}" ]]; then
  echo "Usage: $0 <rc_version> <rc_major>" >&2
  exit 1
fi

workdir="$(pwd)"
base_url="https://cdn.kernel.org/pub/linux/kernel/v${rc_version%%.*}.x"

if [[ "${rc_version}" == *-rc* ]]; then
  archive="linux-${rc_version}.tar.gz"
  archive_url="https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/snapshot/${archive}"
else
  archive="linux-${rc_version}.tar.xz"
  archive_url="${base_url}/${archive}"
fi

curl -fsSLo "${archive}" -L "${archive_url}"
if [[ ! -s "${archive}" ]]; then
  echo "Download failed or empty archive: ${archive_url}" >&2
  exit 1
fi

tar -xf "${archive}"
cd "linux-${rc_version}"

bash "${workdir}/scripts/apply-cachyos.sh" "${rc_major}"

base_config="${workdir}/configs/base.config"
if [[ ! -f "${base_config}" && -d "${workdir}/configs/base.config.d" ]]; then
  cat "${workdir}/configs/base.config.d"/part-* > "${base_config}"
fi

bash "${workdir}/scripts/apply-config.sh" "${workdir}/configs/base.config" "${workdir}/configs/perf.config"

march_flags="${MARCH_FLAGS:--march=icelake-client -mtune=icelake-client}"
local_version="${LOCALVERSION:--cachyos-rc}"

make -j"$(nproc)" KCFLAGS="${KCFLAGS:-} ${march_flags}" LOCALVERSION="${local_version}"
make -j"$(nproc)" KCFLAGS="${KCFLAGS:-} ${march_flags}" LOCALVERSION="${local_version}" modules_install INSTALL_MOD_PATH="${workdir}/modules"

out="${workdir}/artifacts"
mkdir -p "${out}"
cp arch/x86/boot/bzImage "${out}/bzImage"
cp System.map "${out}/System.map"
cp .config "${out}/config"
cp vmlinux "${out}/vmlinux"

tar -I 'zstd -T0 -19' -cf "${out}/modules.tar.zst" -C "${workdir}/modules" .
