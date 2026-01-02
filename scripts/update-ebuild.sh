#!/usr/bin/env bash
set -euo pipefail

rc_version="${1:-}"
if [[ -z "${rc_version}" ]]; then
  echo "Usage: $0 <rc_version>" >&2
  exit 1
fi

pv="${rc_version/-rc/_rc}"
ebuild="sys-kernel/rc-kernel-cachyos-bin/rc-kernel-cachyos-bin-${pv}.ebuild"

if [[ -f "${ebuild}" ]]; then
  echo "Ebuild already exists: ${ebuild}"
  exit 0
fi

cat > "${ebuild}" <<'EBUILD'
EAPI=8

DESCRIPTION="CachyOS patched mainline RC kernel (binary)"
HOMEPAGE="https://github.com/Neycrol/rc-kernel-cachyos-builder"

MY_PV="${PV/_/-}"
SRC_URI="https://github.com/Neycrol/rc-kernel-cachyos-builder/releases/download/rc-${MY_PV}/linux-${MY_PV}-cachyos-rc.tar.zst -> ${P}.tar.zst"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64"
BDEPEND="app-arch/zstd"

S="${WORKDIR}"

src_unpack() {
  unpack "${A}"

  local bundle="linux-${MY_PV}-cachyos-rc"
  if [[ ! -d "${WORKDIR}/${bundle}" ]]; then
    tar -I zstd -xf "${DISTDIR}/${P}.tar.zst" -C "${WORKDIR}" || die
  fi
}

src_install() {
  local bundle="linux-${MY_PV}-cachyos-rc"
  local lib_src="${WORKDIR}/${bundle}/lib"

  if [[ ! -d "${WORKDIR}/${bundle}" ]]; then
    die "Bundle directory not found: ${bundle}"
  fi

  dodir /boot /lib
  cp -a "${WORKDIR}/${bundle}/boot/." "${ED}/boot/" || die

  if [[ -d "${lib_src}/modules" ]]; then
    cp -a "${lib_src}/." "${ED}/lib/" || die
  elif [[ -d "${lib_src}/lib/modules" ]]; then
    cp -a "${lib_src}/lib/." "${ED}/lib/" || die
  else
    die "Modules directory not found under ${lib_src}"
  fi
}

pkg_postinst() {
  elog "Kernel installed under /boot and /lib/modules."

  if command -v kernel-install >/dev/null 2>&1; then
    local moddir
    for moddir in /lib/modules/*-cachyos-rc; do
      [[ -d "${moddir}" ]] || continue
      local krel="${moddir##*/}"
      local image="/boot/vmlinuz-${krel}"
      if [[ -f "${image}" ]]; then
        einfo "Running kernel-install add ${krel}"
        kernel-install add "${krel}" "${image}" || ewarn "kernel-install add failed for ${krel}"
      fi
    done
  else
    ewarn "kernel-install not found; run 'kernel-install add <version> <vmlinuz>' manually."
  fi
}
EBUILD

echo "Created ${ebuild}"
