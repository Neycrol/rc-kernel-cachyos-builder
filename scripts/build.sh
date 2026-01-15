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
download_url=""
for url in "${urls[@]}"; do
  filename="${url##*/}"
  if curl -fsSLo "${filename}" -L --retry 3 --retry-connrefused --retry-delay 5 "${url}"; then
    archive="${filename}"
    download_url="${url}"
    break
  fi
done

if [[ -z "${archive}" || ! -s "${archive}" ]]; then
  echo "Download failed for all sources:" >&2
  printf '  - %s\n' "${urls[@]}" >&2
  exit 1
fi

if [[ "${archive}" != *.tar.xz ]]; then
  echo "Unsupported archive format for verification: ${archive}" >&2
  exit 1
fi

download_dir="${download_url%/*}"
sha256_file=""
for sums_name in sha256sums.asc sha256sums; do
  if curl -fsSLo "${sums_name}" -L --retry 3 --retry-connrefused --retry-delay 5 "${download_dir}/${sums_name}"; then
    sha256_file="${sums_name}"
    break
  fi
done

if [[ -z "${sha256_file}" || ! -s "${sha256_file}" ]]; then
  echo "Failed to download sha256sums.asc or sha256sums from ${download_dir}" >&2
  exit 1
fi

signature_file="${archive}.sign"
if ! curl -fsSLo "${signature_file}" -L --retry 3 --retry-connrefused --retry-delay 5 "${download_dir}/${signature_file}"; then
  echo "Failed to download signature file ${signature_file} from ${download_dir}" >&2
  exit 1
fi

sha256_input="${sha256_file}"
if [[ "${sha256_file}" == *.asc ]]; then
  sha256_input="sha256sums.extracted"
  awk '/^[0-9a-fA-F]{64} / {print}' "${sha256_file}" > "${sha256_input}"
fi

if ! grep -q "${archive}" "${sha256_input}"; then
  echo "Checksum entry for ${archive} not found in ${sha256_file}" >&2
  exit 1
fi

if ! sha256sum -c "${sha256_input}" --ignore-missing; then
  echo "Checksum verification failed for ${archive}" >&2
  exit 1
fi

if ! command -v gpg >/dev/null 2>&1; then
  echo "gpg is required to verify ${signature_file} but was not found in PATH" >&2
  exit 1
fi

if ! gpg --verify "${signature_file}" "${archive}" >/dev/null 2>&1; then
  echo "Signature verification failed for ${archive} with ${signature_file}" >&2
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
