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

## Optional base config
If you want to seed the build with a known-good config, add `configs/base.config` to the repo.
The workflow will auto-detect it. Otherwise, it uses `make defconfig`.

## Notes
- CPU instruction tuning is set via `MARCH_FLAGS` in the workflow.
