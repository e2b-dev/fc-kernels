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

## CI / Releasing

The **Build & Release** workflow runs in two modes:

- **On every pull request**: builds every (kernel version × arch) combination from `kernel_versions.txt` in parallel (one runner per pair) and uploads the binaries as workflow artifacts (downloadable from the PR's checks tab) so reviewers can inspect them. No release or GCS upload happens.
- **Manually (workflow_dispatch)**: pick the branch in the GitHub UI and run. It does the same build as a PR and additionally creates a GitHub release tagged `YYYY.MM.DD` (with a `.N` suffix for additional runs the same day) containing every binary, and uploads them to GCS.

Release asset naming for that commit:

   ```
   vmlinux-<version>-amd64.bin
   vmlinux-<version>-arm64.bin
   vmlinux-<version>.bin           # legacy (= amd64) for backwards compat
   ```

4. The arch-specific binaries are uploaded to each deploy environment's GCS bucket at `gs://$GCP_BUCKET_NAME/kernels/vmlinux-<version>-<short_hash>/<arch>/vmlinux.bin`. Deploy environments: `staging`, `juliett`, `foxtrot`, `public`. To upload an existing release to a bucket manually, run `./scripts/upload-release-to-gcs.sh --hash <commit_hash> --bucket <bucket>/kernels` (add `--dry-run` to preview). Existing objects are never overwritten.

## New kernel in E2B's infra
_Note: these steps should give you a new kernel on your self-hosted E2B using https://github.com/e2b-dev/infra_

- Run the release workflow on the branch with the new config/patch.
- Update `DefaultKernelVersion` in [packages/api/internal/cfg/model.go](https://github.com/e2b-dev/infra/blob/main/packages/api/internal/cfg/model.go) if you changed the kernel version.
- Build and deploy `api`.

## Architecture naming

Output directories use Go's `runtime.GOARCH` convention (`amd64`, `arm64`) so they match the infra orchestrator's `TargetArch()` path resolution. The build-time variable `TARGET_ARCH` (`x86_64`, `arm64`) is only used internally for config paths and cross-compilation flags.

## License

This project is licensed under the Apache License 2.0. See [LICENSE](LICENSE) for details.
