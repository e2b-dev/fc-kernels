#!/bin/bash
# inspired by https://github.com/firecracker-microvm/firecracker/blob/main/resources/rebuild.sh

set -euo pipefail

# Usage:
#   ./build.sh                                 # build all versions in kernel_versions.txt for $TARGET_ARCH
#   ./build.sh <kernel_version> [arch]         # build a single version
#   VERSION_NAME=vmlinux-<v>_<hash> ./build.sh <kernel_version> <arch>
#
# arch is one of: x86_64 (default), arm64 (kernel-style names).
# The output goes to builds/<version_name>/<output_arch>/vmlinux.bin where
# <output_arch> is the Go/OCI name (amd64/arm64) used by the orchestrator.
# If VERSION_NAME isn't provided, it's computed deterministically from the
# kernel version's configs and patches: vmlinux-<version>_<sha256[:7]>.

HOST_ARCH="$(uname -m)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

normalize_arch() {
  case "$1" in
    x86_64)  echo "amd64" ;;
    aarch64) echo "arm64" ;;
    *)       echo "$1" ;;
  esac
}

# Returns vmlinux-<version>_<hash7>. Hash inputs: configs/{x86_64,arm64}/<v>.config
# and any files under patches/<v>/. Must match scripts/validate.py.
compute_version_name() {
  local version="$1"
  local files=()
  for arch in x86_64 arm64; do
    local cfg="$SCRIPT_DIR/configs/$arch/${version}.config"
    [ -f "$cfg" ] && files+=("$cfg")
  done
  if [ -d "$SCRIPT_DIR/patches/$version" ]; then
    while IFS= read -r -d '' f; do
      files+=("$f")
    done < <(find "$SCRIPT_DIR/patches/$version" -type f -print0 | sort -z)
  fi
  if [ "${#files[@]}" -eq 0 ]; then
    echo "Error: no configs found for kernel version $version" >&2
    exit 1
  fi
  local h
  h=$(
    for f in "${files[@]}"; do
      printf '%s\0' "${f#"$SCRIPT_DIR/"}"
      cat "$f"
      printf '\0'
    done | sha256sum | awk '{print $1}' | cut -c1-7
  )
  echo "vmlinux-${version}_${h}"
}

install_dependencies() {
  local target_arch="$1"
  local packages=(
    bc bison busybox-static cpio curl flex gcc libelf-dev libssl-dev make patch squashfs-tools tree
  )

  [[ "$target_arch" == "arm64" && "$HOST_ARCH" != "aarch64" ]] && packages+=( gcc-aarch64-linux-gnu )

  apt update
  apt install -y "${packages[@]}"
}

# Newest-tag matching the requested kernel version.
get_tag() {
  local kernel_version="$1"
  {
    git --no-pager tag -l --sort=-creatordate | grep "microvm-kernel-${kernel_version}-.*\.amzn2" \
    || git --no-pager tag -l --sort=-creatordate | grep "kernel-${kernel_version}-.*\.amzn2"
  } | head -n1
}

apply_patches() {
  local version="$1"
  local patches_dir="$SCRIPT_DIR/patches/$version"
  [ -d "$patches_dir" ] || return 0
  shopt -s nullglob
  local patches=("$patches_dir"/*.patch)
  shopt -u nullglob
  [ "${#patches[@]}" -gt 0 ] || return 0
  echo "Applying ${#patches[@]} patch(es) for $version"
  for p in "${patches[@]}"; do
    git apply --check "$p"
    git apply "$p"
  done
}

build_version() {
  local version="$1"
  local target_arch="$2"
  local version_name="$3"
  local output_arch
  output_arch="$(normalize_arch "$target_arch")"

  echo "Starting build for kernel version: $version (${target_arch}) -> $version_name"

  cp "$SCRIPT_DIR/configs/${target_arch}/${version}.config" .config

  echo "Checking out repo for kernel at version: $version"
  git checkout -f "$(get_tag "$version")"

  apply_patches "$version"

  local make_opts=""
  if [[ "$target_arch" == "arm64" ]]; then
    if [[ "$HOST_ARCH" != "aarch64" ]]; then
      make_opts="ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-"
    else
      make_opts="ARCH=arm64"
    fi
  fi

  echo "Building kernel version: $version"
  make $make_opts olddefconfig

  if [[ "$target_arch" == "arm64" ]]; then
    make $make_opts Image -j "$(nproc)"
  else
    make $make_opts vmlinux -j "$(nproc)"
  fi

  echo "Copying finished build to builds directory"
  local out_dir="$SCRIPT_DIR/builds/${version_name}/${output_arch}"
  mkdir -p "$out_dir"
  if [[ "$target_arch" == "arm64" ]]; then
    cp arch/arm64/boot/Image "$out_dir/vmlinux.bin"
  else
    cp vmlinux "$out_dir/vmlinux.bin"
  fi

  # x86_64: also copy to legacy path (no arch subdir) for backwards compat.
  if [[ "$target_arch" == "x86_64" ]]; then
    cp vmlinux "$SCRIPT_DIR/builds/${version_name}/vmlinux.bin"
  fi
}

ensure_linux_repo() {
  cd "$SCRIPT_DIR"
  [ -d linux ] || git clone --no-checkout --filter=tree:0 https://github.com/amazonlinux/linux
  cd linux
  make distclean || true
}

main() {
  local single_version="${1:-}"
  local target_arch="${2:-${TARGET_ARCH:-x86_64}}"

  install_dependencies "$target_arch"

  ensure_linux_repo

  if [[ -n "$single_version" ]]; then
    local version_name="${VERSION_NAME:-$(compute_version_name "$single_version")}"
    build_version "$single_version" "$target_arch" "$version_name"
  else
    grep -v '^ *#' <"$SCRIPT_DIR/kernel_versions.txt" | while IFS= read -r version; do
      [ -z "$version" ] && continue
      local version_name
      version_name="$(compute_version_name "$version")"
      build_version "$version" "$target_arch" "$version_name"
    done
  fi
}

main "$@"
