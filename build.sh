#!/bin/bash
# inspired by https://github.com/firecracker-microvm/firecracker/blob/main/resources/rebuild.sh

set -euo pipefail

# Cross-compilation settings
CROSS_COMPILE_X86="${CROSS_COMPILE_X86:-}"
HOST_ARCH=$(uname -m)
TARGET_ARCH="x86_64"
CROSS_COMPILE_PREFIX="${TARGET_ARCH}-linux-gnu-"

function install_dependencies {
    apt update
    local packages="bc flex bison gcc make libelf-dev libssl-dev squashfs-tools busybox-static tree cpio curl patch git"
    
    # Add cross-compilation toolchain if needed (use gcc-12 to avoid C23 issues with newer GCC)
    if [[ "$CROSS_COMPILE_X86" == "1" ]]; then
        packages="$packages gcc-12-x86-64-linux-gnu"
    fi
    
    apt install -y $packages
}

# From above mentioned script
# prints the git tag corresponding to the newest and best matching the provided kernel version $1
# this means that if a microvm kernel exists, the tag returned will be of the form
#
#    microvm-kernel-$1.<patch number>.amzn2[023]
#
# otherwise choose the newest tag matching
#
#    kernel-$1.<patch number>.amzn2[023]
function get_tag {
    local KERNEL_VERSION=$1

    # list all tags from newest to oldest
    (git --no-pager tag -l --sort=-creatordate | grep microvm-kernel-$KERNEL_VERSION\..*\.amzn2 \
        || git --no-pager tag -l --sort=-creatordate | grep kernel-$KERNEL_VERSION\..*\.amzn2) | head -n1
}

function build_version {
  local version=$1
  echo "Starting build for kernel version: $version"

  cp ../configs/"${version}.config" .config

  echo "Checking out repo for kernel at version: $version"
  git reset --hard
  git clean -fdx
  git checkout "$(get_tag "$version")"

  # Clean build artifacts from previous build
  make mrproper || true

  # Set up cross-compilation if needed
  local make_opts=""
  if [[ "$CROSS_COMPILE_X86" == "1" ]]; then
    echo "Cross-compiling for $TARGET_ARCH on $HOST_ARCH"
    # Use gcc-12 to avoid C23 issues with newer GCC (bool/true/false keywords)
    make_opts="ARCH=$TARGET_ARCH CROSS_COMPILE=$CROSS_COMPILE_PREFIX CC=${CROSS_COMPILE_PREFIX}gcc-12"
  fi

  echo "Building kernel version: $version"
  make $make_opts olddefconfig
  make $make_opts vmlinux -j "$(nproc)"

  echo "Copying finished build to builds directory"
  mkdir -p "../builds/vmlinux-${version}"
  cp vmlinux "../builds/vmlinux-${version}/vmlinux.bin"
}

echo "Cloning the linux kernel repository"

install_dependencies

[ -d linux ] || git clone --no-checkout --filter=tree:0 https://github.com/amazonlinux/linux
pushd linux

grep -v '^ *#' <../kernel_versions.txt | while IFS= read -r version; do
  build_version "$version"
done

popd
