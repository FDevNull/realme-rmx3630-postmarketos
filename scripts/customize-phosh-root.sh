#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="${1:?usage: customize-phosh-root.sh ROOT_IMAGE [PROBE_ROOT_IMAGE]}"
probe_image="${2:-/home/valtos/rmx3630-port-work/pmos-console-probe-root-556m.img}"

if [[ ! -f "$image" ]]; then
	echo "Missing Phosh root image: $image" >&2
	exit 2
fi
if [[ ! -f "$probe_image" ]]; then
	echo "Missing probe root image containing modetest: $probe_image" >&2
	exit 2
fi

mount_dir="$(mktemp -d /tmp/rmx3630-phosh.XXXXXX)"
probe_mount_dir="$(mktemp -d /tmp/rmx3630-probe.XXXXXX)"
fstab_tmp="$(mktemp /tmp/rmx3630-fstab.XXXXXX)"
cleanup() {
	mountpoint -q "$probe_mount_dir" && sudo umount "$probe_mount_dir" || true
	mountpoint -q "$mount_dir" && sudo umount "$mount_dir" || true
	rm -f "$fstab_tmp"
	rmdir "$probe_mount_dir" "$mount_dir" 2>/dev/null || true
}
trap cleanup EXIT

sudo mount -o loop,rw "$image" "$mount_dir"
sudo mount -o loop,ro "$probe_image" "$probe_mount_dir"

sudo install -Dm0755 "$project_dir/rootfs/rmx3630-systemd-wrapper" \
	"$mount_dir/sbin/rmx3630-systemd-wrapper"
sudo install -Dm0755 "$project_dir/rootfs/rmx3630-fix-device-permissions" \
	"$mount_dir/usr/local/sbin/rmx3630-fix-device-permissions"
sudo install -Dm0644 "$project_dir/rootfs/99-rmx3630-device-permissions.rules" \
	"$mount_dir/etc/udev/rules.d/99-rmx3630-device-permissions.rules"
sudo install -Dm0644 "$project_dir/rootfs/50-rmx3630-greetd.conf" \
	"$mount_dir/etc/systemd/system/greetd.service.d/50-rmx3630.conf"
sudo install -Dm0644 "$project_dir/rootfs/99-rmx3630-usb-unmanaged.conf" \
	"$mount_dir/etc/NetworkManager/conf.d/99-rmx3630-usb-unmanaged.conf"
sudo install -Dm0644 "$project_dir/rootfs/49-rmx3630-network.rules" \
	"$mount_dir/etc/polkit-1/rules.d/49-rmx3630-network.rules"
sudo install -Dm0644 "$project_dir/rootfs/local-overrides.quirks" \
	"$mount_dir/etc/libinput/local-overrides.quirks"
sudo install -Dm0644 "$project_dir/rootfs/rmx3630-phoc.ini" \
	"$mount_dir/etc/phosh/rmx3630-phoc.ini"
sudo install -Dm0644 "$project_dir/rootfs/50-rmx3630-upower.conf" \
	"$mount_dir/etc/systemd/system/upower.service.d/50-rmx3630.conf"
sudo install -Dm0644 "$project_dir/rootfs/rmx3630-phosh-direct.service" \
	"$mount_dir/etc/systemd/system/rmx3630-phosh-direct.service"
sudo install -Dm0755 "$project_dir/rootfs/rmx3630-phosh-session" \
	"$mount_dir/usr/local/bin/rmx3630-phosh-session"
sudo install -Dm0755 "$project_dir/rootfs/rmx3630-load-input" \
	"$mount_dir/usr/local/sbin/rmx3630-load-input"
sudo install -Dm0644 "$project_dir/rootfs/rmx3630-input.service" \
	"$mount_dir/etc/systemd/system/rmx3630-input.service"
sudo install -Dm0755 "$project_dir/rootfs/rmx3630-softpower" \
	"$mount_dir/usr/local/sbin/rmx3630-softpower"
sudo install -Dm0644 "$project_dir/rootfs/rmx3630-softpower.service" \
	"$mount_dir/etc/systemd/system/rmx3630-softpower.service"
sudo install -Dm0755 "$project_dir/rootfs/rmx3630-load-audio" \
	"$mount_dir/usr/local/sbin/rmx3630-load-audio"
sudo install -Dm0755 "$project_dir/rootfs/rmx3630-start-pulse-sink" \
	"$mount_dir/usr/local/sbin/rmx3630-start-pulse-sink"
sudo install -Dm0644 "$project_dir/rootfs/rmx3630-audio.service" \
	"$mount_dir/etc/systemd/system/rmx3630-audio.service"
sudo install -Dm0755 "$project_dir/rootfs/rmx3630-load-gpu" \
	"$mount_dir/usr/local/sbin/rmx3630-load-gpu"
sudo install -Dm0644 "$project_dir/rootfs/rmx3630-gpu.service" \
	"$mount_dir/etc/systemd/system/rmx3630-gpu.service"
sudo install -Dm0755 "$project_dir/rootfs/rmx3630-wifi-service" \
	"$mount_dir/usr/local/sbin/rmx3630-wifi-service"
sudo install -Dm0644 "$project_dir/rootfs/rmx3630-wifi.service" \
	"$mount_dir/etc/systemd/system/rmx3630-wifi.service"
sudo install -Dm0755 "$project_dir/rootfs/rmx3630-wmt-launcher" \
	"$mount_dir/usr/local/sbin/rmx3630-wmt-launcher"
sudo install -Dm0755 "$project_dir/rootfs/rmx3630-wmtdetect-init" \
	"$mount_dir/usr/local/sbin/rmx3630-wmtdetect-init"
sudo install -Dm0644 "$project_dir/rootfs/rmx3630-pulse-sink.service" \
	"$mount_dir/etc/systemd/system/rmx3630-pulse-sink.service"
sudo install -Dm0644 "$project_dir/rootfs/sipa.bin" \
	"$mount_dir/odm/firmware/sipa.bin"
sudo mkdir -p "$mount_dir/vendor/firmware"
for firmware in "$project_dir/out/wifi-live/firmware/"*; do
	sudo install -m0644 "$firmware" \
		"$mount_dir/vendor/firmware/${firmware##*/}"
done
sudo mkdir -p "$mount_dir/etc/wifi" "$mount_dir/odm/etc/wifi"
for config in "$project_dir/out/wifi-live/config/"*.cfg; do
	sudo install -m0644 "$config" "$mount_dir/etc/wifi/${config##*/}"
	sudo install -m0644 "$config" "$mount_dir/odm/etc/wifi/${config##*/}"
done
sudo install -Dm0644 \
	"$project_dir/rootfs/ucm2/mt6789mt6366/mt6789mt6366.conf" \
	"$mount_dir/usr/share/alsa/ucm2/mt6789mt6366/mt6789mt6366.conf"
sudo install -Dm0644 \
	"$project_dir/rootfs/ucm2/mt6789mt6366/HiFi.conf" \
	"$mount_dir/usr/share/alsa/ucm2/mt6789mt6366/HiFi.conf"
sudo install -Dm0644 \
	"$project_dir/rootfs/ucm2/conf.d/mt6789-mt6366/mt6789-mt6366.conf" \
	"$mount_dir/usr/share/alsa/ucm2/conf.d/mt6789-mt6366/mt6789-mt6366.conf"
audio_module_dir="$mount_dir/usr/lib/modules/5.10.209-android12-9-o-05206-g23c1467af8f7/extra/rmx3630-audio"
sudo mkdir -p "$audio_module_dir"
for module in "$project_dir/out/audio-live-dvfs-disabled/"*.ko; do
	sudo install -m0644 "$module" "$audio_module_dir/${module##*/}"
done
input_module_dir="$mount_dir/usr/lib/modules/5.10.209-android12-9-o-05206-g23c1467af8f7/extra/rmx3630-input"
sudo install -Dm0644 "$project_dir/out/mtk-kpd.ko" \
	"$input_module_dir/mtk-kpd.ko"
sudo install -Dm0644 "$project_dir/out/mtk-pmic-keys.ko" \
	"$input_module_dir/mtk-pmic-keys.ko"
gpu_module_dir="$mount_dir/usr/lib/modules/5.10.209-android12-9-o-05206-g23c1467af8f7/extra/rmx3630-gpu"
sudo mkdir -p "$gpu_module_dir"
for module in "$project_dir/out/gpu-live/modules/"*.ko; do
	sudo install -m0644 "$module" "$gpu_module_dir/${module##*/}"
done
panfrost_module_dir="$mount_dir/usr/lib/modules/5.10.209-android12-9-o-05206-g23c1467af8f7/extra/rmx3630-panfrost"
sudo mkdir -p "$panfrost_module_dir"
for module in "$project_dir/out/panfrost-live/modules/"*.ko; do
	sudo install -m0644 "$module" "$panfrost_module_dir/${module##*/}"
done
wifi_module_dir="$mount_dir/usr/lib/modules/5.10.209-android12-9-o-05206-g23c1467af8f7/extra/rmx3630-wifi"
sudo mkdir -p "$wifi_module_dir"
for module in "$project_dir/out/wifi-live/modules/"*.ko; do
	sudo install -m0644 "$module" "$wifi_module_dir/${module##*/}"
done
sudo depmod -b "$mount_dir" 5.10.209-android12-9-o-05206-g23c1467af8f7
sudo install -Dm0755 "$probe_mount_dir/usr/bin/modetest" \
	"$mount_dir/usr/bin/modetest"
sudo rm -f "$mount_dir/etc/systemd/system/display-manager.service"
sudo mkdir -p "$mount_dir/etc/systemd/system/graphical.target.wants"
sudo ln -sfn ../rmx3630-phosh-direct.service \
	"$mount_dir/etc/systemd/system/graphical.target.wants/rmx3630-phosh-direct.service"
sudo mkdir -p "$mount_dir/etc/systemd/system/multi-user.target.wants"
sudo ln -sfn ../rmx3630-audio.service \
	"$mount_dir/etc/systemd/system/multi-user.target.wants/rmx3630-audio.service"
sudo ln -sfn ../rmx3630-gpu.service \
	"$mount_dir/etc/systemd/system/multi-user.target.wants/rmx3630-gpu.service"
sudo ln -sfn ../rmx3630-wifi.service \
	"$mount_dir/etc/systemd/system/multi-user.target.wants/rmx3630-wifi.service"
sudo ln -sfn ../rmx3630-input.service \
	"$mount_dir/etc/systemd/system/multi-user.target.wants/rmx3630-input.service"
sudo ln -sfn ../rmx3630-softpower.service \
	"$mount_dir/etc/systemd/system/multi-user.target.wants/rmx3630-softpower.service"
sudo ln -sfn ../rmx3630-pulse-sink.service \
	"$mount_dir/etc/systemd/system/graphical.target.wants/rmx3630-pulse-sink.service"

# boot_a contains the kernel and initramfs, so a second pmbootstrap /boot
# filesystem must not put systemd into emergency mode.
sudo awk '$2 != "/boot"' "$mount_dir/etc/fstab" >"$fstab_tmp"
sudo install -o root -g root -m 0644 "$fstab_tmp" "$mount_dir/etc/fstab"

sudo test -x "$mount_dir/sbin/init"
sudo test -x "$mount_dir/usr/bin/phoc"
sudo test -x "$mount_dir/usr/bin/phosh-session"
sudo test -x "$mount_dir/usr/libexec/phosh"
sudo test -x "$mount_dir/usr/sbin/greetd"
sudo test -x "$mount_dir/usr/sbin/dnsmasq"
sudo test -x "$mount_dir/usr/bin/modetest"

sudo sync
sudo umount "$probe_mount_dir"
sudo umount "$mount_dir"
sudo e2fsck -pf "$image"
sha256sum "$image"
