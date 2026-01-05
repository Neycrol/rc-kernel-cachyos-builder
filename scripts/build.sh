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
archive_base="linux-${rc_version}"

declare -a urls=()
if [[ "${rc_version}" == *-rc* ]]; then
  urls+=("https://cdn.kernel.org/pub/linux/kernel/v${rc_version%%.*}.x/testing/${archive_base}.tar.xz")
  urls+=("https://mirrors.edge.kernel.org/pub/linux/kernel/v${rc_version%%.*}.x/testing/${archive_base}.tar.xz")
  urls+=("https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/snapshot/${archive_base}.tar.gz")
else
  urls+=("${base_url}/${archive_base}.tar.xz")
  urls+=("https://mirrors.edge.kernel.org/pub/linux/kernel/v${rc_version%%.*}.x/${archive_base}.tar.xz")
fi

archive=""
for url in "${urls[@]}"; do
  filename="${url##*/}"
  if curl -fsSLo "${filename}" -L --retry 3 --retry-connrefused --retry-delay 5; then
    archive="${filename}"
    break
  fi
done

if [[ -z "${archive}" || ! -s "${archive}" ]]; then
  echo "Download failed for all sources:" >&2
  printf '  - %s\n' "${urls[@]}" >&2
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

make -s kernelrelease LOCALVERSION="${local_version}" > "${out}/kernel-release"
tar -I 'zstd -T0 -19' -cf "${out}/modules.tar.zst" -C "${workdir}/modules" .

bundle_dir="${out}/linux-${rc_version}${local_version}"
mkdir -p "${bundle_dir}/boot" "${bundle_dir}/lib"
kver="$(cat "${out}/kernel-release")"
cp "${out}/bzImage" "${bundle_dir}/boot/vmlinuz-${kver}"
cp "${out}/System.map" "${bundle_dir}/boot/System.map-${kver}"
cp "${out}/config" "${bundle_dir}/boot/config-${kver}"
cp "${out}/vmlinux" "${bundle_dir}/boot/vmlinux-${kver}"
cp "${out}/kernel-release" "${bundle_dir}/boot/kernel-release-${kver}"
cp -a "${workdir}/modules/lib/modules" "${bundle_dir}/lib/"

tar -I 'zstd -T0 -19' -cf "${out}/linux-${rc_version}${local_version}.tar.zst" -C "${out}" "linux-${rc_version}${local_version}"
