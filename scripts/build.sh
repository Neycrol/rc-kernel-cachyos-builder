#!/usr/bin/env bash
set -euo pipefail

rc_version="${1:-}"
rc_major="${2:-}"

if [[ -z "${rc_version}" || -z "${rc_major}" ]]; then
  echo "Usage: $0 <rc_version> <rc_major>" >&2
  exit 1
fi

workdir="$(pwd)"
cache_dir="${KERNEL_CACHE_DIR:-${HOME}/.cache/rc-kernel-cachyos}"
mkdir -p "${cache_dir}"
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
cache_hit="0"
for url in "${urls[@]}"; do
  filename="${url##*/}"
  cached_path="${cache_dir}/${filename}"
  if [[ -s "${cached_path}" ]]; then
    archive="${cached_path}"
    download_url="${url}"
    cache_hit="1"
    break
  fi
  if curl -fsSLo "${cached_path}" -L --retry 3 --retry-connrefused --retry-delay 5 "${url}"; then
    archive="${cached_path}"
    download_url="${url}"
    break
  fi
done

if [[ -z "${archive}" || ! -s "${archive}" ]]; then
  echo "Download failed for all sources:" >&2
  printf '  - %s\n' "${urls[@]}" >&2
  exit 1
fi

archive_filename="${archive##*/}"
if [[ "${archive_filename}" != *.tar.xz ]]; then
  echo "Unsupported archive format for verification: ${archive}" >&2
  exit 1
fi

download_dir="${download_url%/*}"
sha256_file=""
for sums_name in sha256sums.asc sha256sums; do
  sums_path="${cache_dir}/${sums_name}"
  if curl -fsSLo "${sums_path}" -L --retry 3 --retry-connrefused --retry-delay 5 "${download_dir}/${sums_name}"; then
    sha256_file="${sums_path}"
    break
  fi
done

if [[ -z "${sha256_file}" || ! -s "${sha256_file}" ]]; then
  echo "Failed to download sha256sums.asc or sha256sums from ${download_dir}" >&2
  exit 1
fi

signature_file="${cache_dir}/${archive_filename%.tar.xz}.tar.sign"
if ! curl -fsSLo "${signature_file}" -L --retry 3 --retry-connrefused --retry-delay 5 "${download_dir}/${signature_file##*/}"; then
  echo "Failed to download signature file ${signature_file##*/} from ${download_dir}" >&2
  exit 1
fi

sha256_input="${sha256_file}"
if [[ "${sha256_file}" == *.asc ]]; then
  sha256_input="${cache_dir}/sha256sums.extracted"
  awk '/^[0-9a-fA-F]{64} / {print}' "${sha256_file}" > "${sha256_input}"
fi

verify_checksum() {
  if ! grep -q "${archive_filename}" "${sha256_input}"; then
    echo "Checksum entry for ${archive_filename} not found in ${sha256_file}" >&2
    return 1
  fi

  local checksum_line
  checksum_line="$(grep -E "^[0-9a-fA-F]{64}  ${archive_filename}$" "${sha256_input}" || true)"
  if [[ -z "${checksum_line}" ]]; then
    echo "Checksum entry for ${archive_filename} not found in ${sha256_input}" >&2
    return 1
  fi

  (cd "${cache_dir}" && printf '%s\n' "${checksum_line}" | sha256sum -c -)
}

if ! verify_checksum; then
  if [[ "${cache_hit}" == "1" ]]; then
    echo "Cached archive failed checksum; re-downloading ${archive_filename}." >&2
    rm -f "${archive}"
    cache_hit="0"
    if ! curl -fsSLo "${archive}" -L --retry 3 --retry-connrefused --retry-delay 5 "${download_url}"; then
      echo "Failed to re-download ${archive_filename} from ${download_url}" >&2
      exit 1
    fi
    if ! verify_checksum; then
      echo "Checksum verification failed for ${archive_filename}" >&2
      exit 1
    fi
  else
    echo "Checksum verification failed for ${archive_filename}" >&2
    exit 1
  fi
fi

if ! command -v gpg >/dev/null 2>&1; then
  echo "gpg is required to verify ${signature_file} but was not found in PATH" >&2
  exit 1
fi

if [[ -z "${KERNEL_GPG_KEYRING:-}" ]]; then
  KERNEL_GPG_KEYRING="${workdir}/.gnupg-kernel"
  mkdir -p "${KERNEL_GPG_KEYRING}"
  chmod 700 "${KERNEL_GPG_KEYRING}"
fi

keyring_opt=(--homedir "${KERNEL_GPG_KEYRING}")
if ! gpg "${keyring_opt[@]}" --list-keys >/dev/null 2>&1; then
  echo "Initializing GPG keyring at ${KERNEL_GPG_KEYRING}" >&2
  gpg "${keyring_opt[@]}" --batch --list-keys >/dev/null 2>&1 || true
fi

kernel_keys_url="${KERNEL_KEYS_URL:-https://www.kernel.org/signature.html}"
if ! gpg "${keyring_opt[@]}" --list-keys 38DBBDC86092693E >/dev/null 2>&1; then
  if curl -fsSL "${kernel_keys_url}" | gpg "${keyring_opt[@]}" --batch --import >/dev/null 2>&1; then
    : # imported
  else
    echo "Failed to import kernel.org signing keys from ${kernel_keys_url}" >&2
    exit 1
  fi
fi

if ! gpg "${keyring_opt[@]}" --verify "${signature_file}" "${archive}" >/dev/null 2>&1; then
  echo "Signature verification failed for ${archive_filename} with ${signature_file}" >&2
  exit 1
fi

if command -v ccache >/dev/null 2>&1 && [[ -z "${CC:-}" ]]; then
  export CC="ccache gcc"
  export HOSTCC="ccache gcc"
  export CCACHE_BASEDIR="${workdir}"
  export CCACHE_DIR="${CCACHE_DIR:-${HOME}/.ccache}"
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
