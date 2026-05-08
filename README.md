# fc-kernels

## Overview

This project builds custom Linux kernels for Firecracker microVMs from the same kernel sources as the official Firecracker repo, using the configuration files (and optional patches) that live in this repo.

## Prerequisites

- Linux environment (for building kernels)

## Building locally

1. **Configure kernel versions:**
   - Edit `kernel_versions.txt` to specify which kernel versions to build (one per line, e.g. `6.1.158`).
   - Place the corresponding config(s) in `configs/x86_64/<version>.config` and `configs/arm64/<version>.config`.
   - (Optional) Drop `*.patch` files into `patches/<version>/` to apply on top of the upstream tree before build.

2. **Build:**
   ```sh
   make build              # builds all versions in kernel_versions.txt for x86_64
   make build-arm64        # same, for arm64
   ./build.sh 6.1.158      # build a single version (x86_64)
   ./build.sh 6.1.158 arm64
   ```

   Output: `builds/vmlinux-<version>/<arch>/vmlinux.bin` where `<arch>` is `amd64` or `arm64` (Go/OCI convention). For x86_64 a legacy copy is also placed at `builds/vmlinux-<version>/vmlinux.bin`.

## Releasing

1. Pick the branch and run the **Manual Build & Release** workflow (Actions → Manual Build & Release → Run workflow → branch). The workflow takes no inputs.
2. Every kernel version in `kernel_versions.txt` is built for both `amd64` and `arm64` in parallel.
3. A single GitHub release is created per run, tagged with calver `YYYY.MM.DD` (with a `.N` suffix for additional runs the same day). The release contains every binary for that commit:

   ```
   vmlinux-<version>-amd64.bin
   vmlinux-<version>-arm64.bin
   vmlinux-<version>.bin           # legacy (= amd64) for backwards compat
   ```

4. The same binaries are uploaded to GCS at `gs://$GCP_BUCKET_NAME/kernels/vmlinux-<version>/<arch>/vmlinux.bin`.

## New kernel in E2B's infra
_Note: these steps should give you a new kernel on your self-hosted E2B using https://github.com/e2b-dev/infra_

- Run the release workflow on the branch with the new config/patch.
- Update `DefaultKernelVersion` in [packages/api/internal/cfg/model.go](https://github.com/e2b-dev/infra/blob/main/packages/api/internal/cfg/model.go) if you changed the kernel version.
- Build and deploy `api`.

## Architecture naming

Output directories use Go's `runtime.GOARCH` convention (`amd64`, `arm64`) so they match the infra orchestrator's `TargetArch()` path resolution. The build-time variable `TARGET_ARCH` (`x86_64`, `arm64`) is only used internally for config paths and cross-compilation flags.

## License

This project is licensed under the Apache License 2.0. See [LICENSE](LICENSE) for details.
