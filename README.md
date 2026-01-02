# rc-kernel-cachyos-builder

Nightly GitHub Actions builder for Linux mainline RC kernels with CachyOS patches and BBRv3.

## What it does
- Resolves the latest mainline RC from kernel.org
- Applies CachyOS base + BORE scheduler + BBRv3 patches
- Merges a performance config fragment (and an optional base config)
- Builds and uploads kernel artifacts

## Artifacts
- `bzImage`, `vmlinux`, `System.map`, `.config`
- `modules.tar.zst`
- `linux-<rc_version>-cachyos-rc.tar.zst` (bundle with `/boot` + `/lib/modules`)

## Gentoo overlay usage
This repo doubles as a simple overlay that installs the bundled kernel.

```bash
eselect repository add rc-kernel-cachyos git https://github.com/Neycrol/rc-kernel-cachyos-builder
emaint sync -r rc-kernel-cachyos
ebuild sys-kernel/rc-kernel-cachyos-bin/rc-kernel-cachyos-bin-6.19_rc3.ebuild manifest
emerge -av =sys-kernel/rc-kernel-cachyos-bin-6.19_rc3
```

Then add a systemd-boot entry for the new `/boot/vmlinuz-<kver>` and reboot.

## Optional base config
If you want to seed the build with a known-good config, add `configs/base.config` to the repo.
If it is split into `configs/base.config.d/part-*`, the build script will reassemble it.
Otherwise, it uses `make defconfig`.

## Notes
- CPU instruction tuning is set via `MARCH_FLAGS` in the workflow.
