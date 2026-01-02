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

src_install() {
  local bundle="linux-${MY_PV}-cachyos-rc"

  if [[ ! -d "${WORKDIR}/${bundle}" ]]; then
    die "Bundle directory not found: ${bundle}"
  fi

  dodir /boot /lib
  cp -a "${WORKDIR}/${bundle}/boot/." "${ED}/boot/" || die
  cp -a "${WORKDIR}/${bundle}/lib/." "${ED}/lib/" || die
}

pkg_postinst() {
  elog "Kernel installed under /boot and /lib/modules."
  elog "Update your bootloader entry (systemd-boot) and initramfs if needed."
}
EBUILD

echo "Created ${ebuild}"
