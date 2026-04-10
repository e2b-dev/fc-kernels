#!/bin/bash
# inspired by https://github.com/firecracker-microvm/firecracker/blob/main/resources/rebuild.sh

set -euo pipefail

# TARGET_ARCH: x86_64 (default) or arm64
TARGET_ARCH="${TARGET_ARCH:-x86_64}"
HOST_ARCH="$(uname -m)"

# Go/OCI-normalized arch name for output directory structure.
# The infra orchestrator uses Go's runtime.GOARCH convention (amd64/arm64)
# for path resolution, so output directories must match.
normalize_arch() {
  case "$1" in
    x86_64)  echo "amd64" ;;
    aarch64) echo "arm64" ;;
    *)       echo "$1" ;;
  esac
}
OUTPUT_ARCH="$(normalize_arch "$TARGET_ARCH")"

function install_dependencies {
    local packages=(
        bc bison busybox-static cpio curl flex gcc libelf-dev libssl-dev make patch squashfs-tools tree
    )

    [[ "${TARGET_ARCH}" == "arm64" && "${HOST_ARCH}" != "aarch64" ]] && packages+=( gcc-aarch64-linux-gnu )

    apt update
    apt install -y "${packages[@]}"
}

# prints the git tag corresponding to the newest and best matching the provided kernel version $1
function get_tag {
    local KERNEL_VERSION="${1}"

    # list all tags from newest to oldest
    {
        git --no-pager tag -l --sort=-creatordate | grep "microvm-kernel-${KERNEL_VERSION}-.*\.amzn2" \
        || git --no-pager tag -l --sort=-creatordate | grep "kernel-${KERNEL_VERSION}-.*\.amzn2"
    } | head -n1
}

function build_version {
  local version=$1
  echo "Starting build for kernel version: $version (${TARGET_ARCH})"

  # Configs live in configs/{arch}/
  cp ../configs/"${TARGET_ARCH}/${version}.config" .config

  echo "Checking out repo for kernel at version: $version"
  git checkout "$(get_tag "$version")"

  # Set up cross-compilation if building arm64 on x86_64
  local make_opts=""
  if [[ "$TARGET_ARCH" == "arm64" ]]; then
    if [[ "$HOST_ARCH" != "aarch64" ]]; then
      make_opts="ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-"
    else
      make_opts="ARCH=arm64"
    fi
  fi

  echo "Building kernel version: $version"
  make $make_opts olddefconfig
  
  if [[ "$TARGET_ARCH" == "arm64" ]]; then
    make $make_opts Image -j "$(nproc)"
  else
    make $make_opts vmlinux -j "$(nproc)"
  fi

  echo "Copying finished build to builds directory"
  # Output to normalized arch dir (amd64/arm64) matching Go's runtime.GOARCH
  mkdir -p "../builds/vmlinux-${version}/${OUTPUT_ARCH}"
  if [[ "$TARGET_ARCH" == "arm64" ]]; then
    cp arch/arm64/boot/Image "../builds/vmlinux-${version}/${OUTPUT_ARCH}/vmlinux.bin"
  else
    cp vmlinux "../builds/vmlinux-${version}/${OUTPUT_ARCH}/vmlinux.bin"
  fi

  # x86_64: also copy to legacy path (no arch subdir) for backwards compat
  if [[ "$TARGET_ARCH" == "x86_64" ]]; then
    cp vmlinux "../builds/vmlinux-${version}/vmlinux.bin"
  fi
}

echo "Building kernels for ${TARGET_ARCH}"

install_dependencies

[ -d linux ] || git clone --no-checkout --filter=tree:0 https://github.com/amazonlinux/linux
pushd linux

make distclean || true

grep -v '^ *#' <../kernel_versions.txt | while IFS= read -r version; do
  build_version "$version"
done

popd
