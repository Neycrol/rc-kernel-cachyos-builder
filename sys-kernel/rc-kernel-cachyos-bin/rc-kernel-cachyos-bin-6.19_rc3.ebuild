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
  elog "Update your bootloader entry (systemd-boot) and initramfs if needed."
}
