#!/system/bin/sh

echo UDC
ls -l /sys/class/udc
for u in /sys/class/udc/*; do
	echo "U=$u"
	readlink -f "$u/device"
	cat "$u/state" 2>/dev/null
done

echo MODULES
grep -E 'musb|usb|extcon|tcpc|wusb|phy_mtk|phy_generic' /proc/modules

echo ROLE
find /sys/class/usb_role /sys/class/dual_role_usb \
	/sys/devices/platform/soc/11200000.usb0 -maxdepth 4 -type f 2>/dev/null \
	| grep -E 'role|mode|state|vbus|otg' \
	| while read -r f; do
		echo "F=$f"
		cat "$f" 2>/dev/null
	done

echo GADGET
find /config/usb_gadget -maxdepth 4 -type f 2>/dev/null \
	| while read -r f; do
		case "$f" in
			*/UDC|*/idVendor|*/idProduct|*/functions/*/ifname)
				echo "F=$f"
				cat "$f"
				;;
		esac
	done

echo LINKS
find /sys/devices/platform/soc/11200000.usb0 -maxdepth 2 -type l -ls 2>/dev/null

echo DEFERRED
cat /sys/kernel/debug/devices_deferred 2>/dev/null

echo MT_USB
ls -la /sys/devices/platform/soc/mt_usb 2>&1
cat /sys/devices/platform/soc/mt_usb/uevent 2>/dev/null
readlink -f /sys/devices/platform/soc/mt_usb/driver
readlink -f /sys/devices/platform/soc/mt_usb/of_node
find /sys/devices/platform/soc/mt_usb -maxdepth 2 -type l -ls 2>/dev/null

echo USB0
ls -la /sys/devices/platform/soc/11200000.usb0 2>&1
readlink -f /sys/devices/platform/soc/11200000.usb0/driver
cat /sys/devices/platform/soc/11200000.usb0/uevent 2>/dev/null

echo DT
find /sys/firmware/devicetree/base -maxdepth 5 \
	\( -iname '*usb*' -o -iname '*musb*' \) 2>/dev/null | head -n 100

echo DMESG
dmesg | grep -Ei 'musb|mt_usb|11200000|11f40000|extcon.*usb|wusb3801' | tail -n 200
