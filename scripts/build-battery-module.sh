#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="${KERNEL_SOURCE:-/home/valtos/rmx3630-port-work/kernel-volla-mt6789-panfrost}"
output_dir="${KERNEL_OUTPUT:-/home/valtos/rmx3630-port-work/module-build-stockabi}"
symvers="${KERNEL_SYMVERS:-/home/valtos/rmx3630-port-work/config-test/vmlinux.symvers}"
kernel_release=5.10.209-android12-9-o-05206-g23c1467af8f7
crc_file="$project_dir/kernel-modules/rmx3630-power-stock-crcs.txt"

cp "$symvers" "$output_dir/Module.symvers"
cp "$output_dir/include/generated/utsrelease.h" /tmp/rmx3630-battery-utsrelease.h.bak
cp "$output_dir/include/config/kernel.release" /tmp/rmx3630-battery-kernel.release.bak

restore_release() {
	cp /tmp/rmx3630-battery-utsrelease.h.bak \
		"$output_dir/include/generated/utsrelease.h"
	cp /tmp/rmx3630-battery-kernel.release.bak \
		"$output_dir/include/config/kernel.release"
}
trap restore_release EXIT

printf '#define UTS_RELEASE "%s"\n' "$kernel_release" \
	>"$output_dir/include/generated/utsrelease.h"
printf '%s\n' "$kernel_release" >"$output_dir/include/config/kernel.release"

mkdir -p "$project_dir/out"
for name in rmx3630-battery rmx3630-charge-limit; do
	module_dir="$project_dir/kernel-modules/$name"
	make -C "$source_dir" O="$output_dir" M="$module_dir" \
		ARCH=arm64 LLVM=1 LLVM_IAS=1 \
		KERNELRELEASE="$kernel_release" clean
	make -C "$source_dir" O="$output_dir" M="$module_dir" \
		ARCH=arm64 LLVM=1 LLVM_IAS=1 \
		KERNELRELEASE="$kernel_release" modules
done

python3 "$project_dir/scripts/patch-module-crcs.py" \
	"$project_dir/kernel-modules/rmx3630-battery/rmx3630_battery.ko" \
	"$project_dir/out/rmx3630_battery.live.ko" \
	--set-file "$crc_file" --ignore-missing
python3 "$project_dir/scripts/patch-module-crcs.py" \
	"$project_dir/kernel-modules/rmx3630-charge-limit/rmx3630_charge_limit.ko" \
	"$project_dir/out/rmx3630_charge_limit.live.ko" \
	--set-file "$crc_file" --ignore-missing

modinfo "$project_dir/out/rmx3630_battery.live.ko"
modinfo "$project_dir/out/rmx3630_charge_limit.live.ko"
