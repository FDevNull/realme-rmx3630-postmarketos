#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dumps_dir="${DUMPS_DIR:-/mnt/c/UnlockTool/fff}"
work_dir="${WORK_DIR:-/home/valtos/rmx3630-port-work}"
tools_dir="$work_dir/tools"
unpacked_dir="$work_dir/stock-unpacked/boot_a"
vendor_unpacked_dir="$work_dir/stock-unpacked/vendor_boot_a"
vendor_root_dir="$work_dir/stock-unpacked/vendor-ramdisk-root"
build_dir="$work_dir/alpine-initramfs"
rootfs_dir="$build_dir/rootfs"
output_dir="${OUTPUT_DIR:-$project_dir/out}"

alpine_version=3.24.1
alpine_file="alpine-minirootfs-${alpine_version}-aarch64.tar.gz"
alpine_base=https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/aarch64
apk_static_url=https://gitlab.alpinelinux.org/api/v4/projects/5/packages/generic/v2.14.6/x86_64/apk.static

case "$build_dir" in
    /home/valtos/rmx3630-port-work/*) ;;
    *) echo "Refusing unsafe build directory: $build_dir" >&2; exit 2 ;;
esac

for required in \
    "$dumps_dir/boot_a.img" \
    "$dumps_dir/vendor_boot_a.img" \
    "$project_dir/initramfs/init"; do
    if [[ ! -f "$required" ]]; then
        echo "Missing required file: $required" >&2
        exit 2
    fi
done

mkdir -p "$tools_dir" "$build_dir/downloads" "$output_dir"

if [[ ! -d "$tools_dir/mkbootimg/.git" ]]; then
    git clone --depth 1 https://android.googlesource.com/platform/system/tools/mkbootimg "$tools_dir/mkbootimg"
fi

if [[ ! -d "$tools_dir/avb/.git" ]]; then
    git clone --depth 1 https://android.googlesource.com/platform/external/avb "$tools_dir/avb"
fi

if [[ ! -x "$tools_dir/apk.static" ]]; then
    curl --fail --location --output "$tools_dir/apk.static" "$apk_static_url"
    chmod 0755 "$tools_dir/apk.static"
fi

if [[ ! -f "$build_dir/downloads/$alpine_file" ]]; then
    curl --fail --location --output "$build_dir/downloads/$alpine_file" "$alpine_base/$alpine_file"
fi
curl --fail --location --output "$build_dir/downloads/$alpine_file.sha256" "$alpine_base/$alpine_file.sha256"
(
    cd "$build_dir/downloads"
    sha256sum --check "$alpine_file.sha256"
)

if [[ -e "$rootfs_dir" ]]; then
    rm -rf -- "$rootfs_dir"
fi
mkdir -p "$rootfs_dir"
tar -xzf "$build_dir/downloads/$alpine_file" -C "$rootfs_dir"
"$tools_dir/apk.static" \
    --arch aarch64 \
    --root "$rootfs_dir" \
    --repository https://dl-cdn.alpinelinux.org/alpine/v3.24/main \
    --no-scripts \
    --update-cache \
    add busybox-extras

if [[ ! -f "$vendor_unpacked_dir/vendor_ramdisk00" ]]; then
    mkdir -p "$vendor_unpacked_dir"
    python3 "$tools_dir/mkbootimg/unpack_bootimg.py" \
        --boot_img "$dumps_dir/vendor_boot_a.img" \
        --out "$vendor_unpacked_dir"
fi

case "$vendor_root_dir" in
    /home/valtos/rmx3630-port-work/*) ;;
    *) echo "Refusing unsafe vendor ramdisk directory: $vendor_root_dir" >&2; exit 2 ;;
esac
rm -rf -- "$vendor_root_dir"
mkdir -p "$vendor_root_dir"
lz4 -d -c "$vendor_unpacked_dir/vendor_ramdisk00" \
    | (cd "$vendor_root_dir" && cpio -idmu --no-absolute-filenames 2>/dev/null)

if [[ ! -f "$vendor_root_dir/lib/modules/modules.load.recovery" ]] \
    || [[ ! -f "$vendor_root_dir/lib/modules/musb_hdrc.ko" ]] \
    || [[ ! -f "$vendor_root_dir/lib/modules/musb_main.ko" ]]; then
    echo "The stock recovery module set is incomplete" >&2
    exit 3
fi

mkdir -p "$rootfs_dir/lib"
cp -a "$vendor_root_dir/lib/modules" "$rootfs_dir/lib/modules"
install -m 0755 "$project_dir/initramfs/init" "$rootfs_dir/init"
mkdir -p "$rootfs_dir/run" "$rootfs_dir/proc" "$rootfs_dir/sys" "$rootfs_dir/dev" "$rootfs_dir/tmp"
printf '%s\n' 'RMX3630 Alpine Linux bring-up' > "$rootfs_dir/etc/hostname"
printf '%s\n' 'RMX3630 Alpine Linux bring-up: USB telnet root shell on 172.16.42.1' > "$rootfs_dir/etc/motd"

ramdisk="$build_dir/rmx3630-alpine-initramfs.cpio.lz4"
rm -f -- "$ramdisk"
(
    cd "$rootfs_dir"
    find . -print0 \
        | sort -z \
        | cpio --null --create --format=newc --owner=0:0 2>/dev/null \
        | lz4 -l -12 - "$ramdisk"
)

if [[ ! -f "$unpacked_dir/kernel" ]]; then
    mkdir -p "$unpacked_dir"
    python3 "$tools_dir/mkbootimg/unpack_bootimg.py" \
        --boot_img "$dumps_dir/boot_a.img" \
        --out "$unpacked_dir"
fi

raw_output="$output_dir/rmx3630-alpine-test-boot-raw.img"
output="$output_dir/rmx3630-alpine-test-boot.img"
rm -f -- "$raw_output" "$output" "$output.sha256"
python3 "$tools_dir/mkbootimg/mkbootimg.py" \
    --header_version 4 \
    --os_version 12.0.0 \
    --os_patch_level 2025-03 \
    --kernel "$unpacked_dir/kernel" \
    --ramdisk "$ramdisk" \
    --cmdline '' \
    --output "$raw_output"

limit=$((64 * 1024 * 1024))
raw_size=$(stat -c '%s' "$raw_output")
if (( raw_size > limit )); then
    echo "Boot image is too large: $raw_size > $limit" >&2
    exit 3
fi

cp -- "$raw_output" "$output"
python3 "$tools_dir/avb/avbtool.py" add_hash_footer \
    --image "$output" \
    --partition_name boot \
    --partition_size "$limit" \
    --algorithm SHA256_RSA2048 \
    --key "$tools_dir/mkbootimg/tests/data/testkey_rsa2048.pem" \
    --prop com.android.build.boot.os_version:12 \
    --prop com.android.build.boot.security_patch:2025-03-01

sha256sum "$output" | tee "$output.sha256"
printf 'Built raw image %s (%s bytes)\n' "$raw_output" "$raw_size"
printf 'Built AVB image %s (%s bytes)\n' "$output" "$(stat -c '%s' "$output")"
