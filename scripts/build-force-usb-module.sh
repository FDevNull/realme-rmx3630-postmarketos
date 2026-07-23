#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="${KERNEL_SOURCE:-/home/valtos/rmx3630-port-work/kernel-volla-mt6789}"
output_dir="${KERNEL_OUTPUT:-/home/valtos/rmx3630-port-work/module-build-rmx3630}"
symvers="${KERNEL_SYMVERS:-/home/valtos/rmx3630-port-work/config-test/vmlinux.symvers}"
module_dir="$project_dir/kernel-modules/rmx3630-force-usb-device"
kernel_release=5.10.209-android12-9-o-05206-g23c1467af8f7

cp "$symvers" "$output_dir/Module.symvers"
cp "$output_dir/include/generated/utsrelease.h" /tmp/rmx3630-utsrelease.h.bak
cp "$output_dir/include/config/kernel.release" /tmp/rmx3630-kernel.release.bak

restore_release() {
	cp /tmp/rmx3630-utsrelease.h.bak "$output_dir/include/generated/utsrelease.h"
	cp /tmp/rmx3630-kernel.release.bak "$output_dir/include/config/kernel.release"
}
trap restore_release EXIT

printf '#define UTS_RELEASE "%s"\n' "$kernel_release" \
	>"$output_dir/include/generated/utsrelease.h"
printf '%s\n' "$kernel_release" >"$output_dir/include/config/kernel.release"

make -C "$source_dir" O="$output_dir" M="$module_dir" \
	ARCH=arm64 LLVM=1 LLVM_IAS=1 KERNELRELEASE="$kernel_release" clean
make -C "$source_dir" O="$output_dir" M="$module_dir" \
	ARCH=arm64 LLVM=1 LLVM_IAS=1 KERNELRELEASE="$kernel_release" modules

modinfo "$module_dir/rmx3630_force_usb_device.ko"
modprobe --dump-modversions "$module_dir/rmx3630_force_usb_device.ko"
