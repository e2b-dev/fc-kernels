#!/bin/bash
# inspired by https://github.com/firecracker-microvm/firecracker/blob/main/resources/rebuild.sh

set -euo pipefail

# TARGET_ARCH: x86_64 (default) or arm64
TARGET_ARCH="${TARGET_ARCH:-x86_64}"
HOST_ARCH="$(uname -m)"

function install_dependencies {
    apt update
    local packages="bc flex bison gcc make libelf-dev libssl-dev squashfs-tools busybox-static tree cpio curl patch"

    if [[ "$TARGET_ARCH" == "arm64" && "$HOST_ARCH" != "aarch64" ]]; then
        packages="$packages gcc-aarch64-linux-gnu"
    fi

    apt install -y $packages
}

# prints the git tag corresponding to the newest and best matching the provided kernel version $1
function get_tag {
    local KERNEL_VERSION=$1

    # list all tags from newest to oldest
    (git --no-pager tag -l --sort=-creatordate | grep microvm-kernel-$KERNEL_VERSION\..*\.amzn2 \
        || git --no-pager tag -l --sort=-creatordate | grep kernel-$KERNEL_VERSION\..*\.amzn2) | head -n1
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
  make $make_opts vmlinux -j "$(nproc)"

  echo "Copying finished build to builds directory"
  # Always output to {arch}/ subdirectory
  mkdir -p "../builds/vmlinux-${version}/${TARGET_ARCH}"
  cp vmlinux "../builds/vmlinux-${version}/${TARGET_ARCH}/vmlinux.bin"

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
