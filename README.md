# fc-kernels

## Overview

This project automates the building of custom Linux kernels for Firecracker microVMs, using the same kernel sources as official Firecracker repo and custom configuration files. It supports building specific kernel versions and uploading the resulting binaries to a Google Cloud Storage (GCS) bucket.

## Prerequisites

- Linux environment (for building kernels)

## Building Kernels

1. **Configure kernel versions:**
   - Edit `kernel_versions.txt` to specify which kernel versions to build (one per line, e.g., `6.1.102`).
   - Place the corresponding config file in `configs/` (e.g., `configs/6.1.102.config`).

2. **Build:**
   ```sh
   make build
   # or directly
   ./build.sh
   ```
   The built kernels will be placed in `builds/vmlinux-<version>/<arch>/vmlinux.bin` where `<arch>` is `amd64` or `arm64` (Go/OCI convention). For x86_64 backward compatibility, a legacy copy is also placed at `builds/vmlinux-<version>/vmlinux.bin`.

## Development Workflow
  - On every push, GitHub Actions will automatically build the kernels and save it as an artifact.

## Architecture naming

Output directories use Go's `runtime.GOARCH` convention (`amd64`, `arm64`) so they match the infra orchestrator's `TargetArch()` path resolution. The build-time variable `TARGET_ARCH` (`x86_64`, `arm64`) is only used internally for config paths and cross-compilation flags.

## New Kernel in E2B's infra
_Note: these steps should give you new kernel on your self-hosted E2B using https://github.com/e2b-dev/infra_

  - Copy the kernel build in your project's object storage under `e2b-*-fc-kernels`
  - In [packages/api/internal/cfg/model.go](https://github.com/e2b-dev/infra/blob/main/packages/api/internal/cfg/model.go) update `DefaultKernelVersion`
  - Build and deploy `api`
  
## License

This project is licensed under the Apache License 2.0. See [LICENSE](LICENSE) for details. 
