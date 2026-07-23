# realme 10 4G (RMX3630) Linux port

This workspace contains the in-progress postmarketOS port for the RMX3630
(MediaTek MT6789, Oplus project `2269E`). Keep complete dumps before reproducing
any flashing steps. A second Android slot is useful during early bring-up, but
it is not a recovery path after the shared `userdata` becomes the Linux root.

## Repository scope

This repository intentionally contains only authored source, configuration,
diagnostic scripts, and documentation. It does not redistribute phone dumps,
stock boot images, the Realme kernel payload, proprietary firmware, extracted
vendor modules, generated root filesystems, or UnlockTool data.

The following ignored inputs must be obtained from the owner's own RMX3630:

- stock partition dumps, normally supplied through `DUMPS_DIR`;
- `pmaports/linux-realme-rmx3630/stock-kernel.gz`;
- `rootfs/sipa.bin`;
- vendor `.ko` files and Wi-Fi firmware consumed by
  `scripts/customize-phosh-root.sh`;
- generated images and captures under `out/`.

Do not upload IMEI/MEID, NVRAM/NVDATA, calibration partitions, UnlockTool
credentials, or complete personal dumps to an issue or pull request.

## Current status (2026-07-23)

The phone cold-boots postmarketOS with Phosh using the stock Realme
`5.10.209-android12` kernel. The persistent ext4 root is `/dev/sdc71` (227 GiB;
about 206 GiB free at the time of this update), so the large userdata area is
available to Linux rather than being limited to the early 556 MiB test image.

Installation and recovery instructions for other RMX3630 owners are in
[`INSTALL-RU.md`](INSTALL-RU.md). Read its backup and model checks before using
any image from `out/`; the current full stock-derived scatter is not a safe
three-partition public installer.

Working and physically verified:

- DRM/KMS panel at 1080x2400/60 Hz;
- Mali-G57 MC2 acceleration through Mesa/Panfrost and the GLES2 Phoc renderer;
- FT3518 touchscreen, including the Phosh lock screen;
- Power, volume-up and volume-down keys through the stock `mtk-pmic-keys`
  and `mtk-kpd` modules;
- USB RNDIS at `172.16.42.1`, DHCP, and the bring-up root shell on TCP 23;
- internal speaker through MT6789 AFE, MT6358 and SIA8100x;
- automatic ALSA/UCM/PulseAudio speaker setup after a cold boot;
- MT6789 Wi-Fi through the downstream WMT/WLAN modules and NetworkManager;
- Squeekboard and NetworkManager's password agent in the direct Phosh session;
- battery voltage and estimated percentage through a safe AUXADC power-supply
  driver, without the Android/Oplus charging stack;
- an 80% charge limit for the detected TI BQ25890H charger (charging resumes
  at 75%).

The full-root wrapper deliberately skips its old five-second `modetest`
preview.  Stopping that preview makes the stock AMOLED driver power-cycle the
panel during DRM hand-off and can leave a running Phosh session with a black
screen.  The preview can still be enabled for diagnostics by creating
`/etc/rmx3630-enable-kms-preview` before boot.

The same downstream panel also fails to resume after a normal DRM DPMS-off.
The local libinput quirk therefore hides only `KEY_POWER` from Phosh, while
`rmx3630-softpower.service` handles that raw key by writing AMOLED brightness
`0` or `1024`.  While soft-blanked it also holds `EVIOCGRAB` on the FT3518
touch event, preventing accidental input without unloading the touch driver.
The grab is released before normal interaction resumes.  The CRTC and DSI
connector remain active; the restore level can be overridden with an integer
from 1 to 2047 in
`/etc/rmx3630-softpower-brightness`.

Not working, incomplete, or not yet tested end-to-end:

- accurate coulomb-counter capacity and complete charging-state reporting;
- true suspend/resume and normal DRM DPMS;
- microphones, headset routing, cameras, modem calls/mobile data, Bluetooth,
  GPS, NFC, flashlight and most sensors.

## Audio implementation

`rmx3630-audio.service` loads the verified 35-module vendor audio stack from
`/usr/lib/modules/$(uname -r)/extra/rmx3630-audio`. Its `scp.ko` is locally
patched to bypass the stock SCP DVFS wait which otherwise never completes.
The expected patched SCP SHA-256 is:

```text
4f4a29f13eefae193f7a054b05438e7965ae3c1ea3e6baeec0e41611350982b1
```

SIA firmware is installed as `/odm/firmware/sipa.bin`. The kernel starts its
relative lookup in `/vendor/firmware` (which now also contains the MT6789 Wi-Fi
firmware) before resolving `../../odm/firmware/sipa.bin`.

The UCM2 profile is under `rootfs/ucm2`. On a clean boot PulseAudio creates:

```text
alsa_output.platform-soc_sound.HiFi__Speaker__sink
```

`rmx3630-pulse-sink.service` selects that sink and initializes it to 70%
(approximately -9.3 dB in PulseAudio's nonlinear volume scale). Direct ALSA
and PulseAudio playback were both physically confirmed on the phone.

## Build

Run from WSL2 Ubuntu:

```sh
bash /mnt/c/Users/Valtos/Documents/Random/rmx3630-linux-port/scripts/build-alpine-boot.sh
```

The output is `out/rmx3630-alpine-test-boot.img`.

Build the battery indicator and 80% charge limiter against the prepared
stock-ABI kernel output:

```sh
bash /mnt/c/Users/Valtos/Documents/Random/rmx3630-linux-port/scripts/build-battery-module.sh
```

This produces `out/rmx3630_battery.live.ko` and
`out/rmx3630_charge_limit.live.ko`. The percentage is currently estimated
from battery voltage, so it may move by several points as load changes. The
limiter polls every 30 seconds, disables BQ25890H `REG03[4]` at 80%, and
reenables it at 75%.

The persistent postmarketOS/Phosh root used on the first device was built with
pmbootstrap 3.11.1 from the v26.06 pmaports branch, with `systemd=always` and
`ui=phosh`, then customized with the RMX3630 files in this workspace. The old
556 MiB images in `out/` are bring-up roots and are not the persistent Phosh
image.

## Flash the early test image (historical)

Run from PowerShell:

```powershell
& 'C:\Users\Valtos\Documents\Random\rmx3630-linux-port\scripts\flash-test-slot-b.ps1'
```

This script was used for the early disposable slot-B initramfs test. It is not
the complete persistent Phosh installation procedure. It copies the then
known-good slot-A `vendor_boot`, `dtbo`, and disabled `vbmeta` state to slot B,
flashes only the experimental `boot_b`, selects slot B, and reboots.

If USB RNDIS appears, connect with:

```powershell
telnet 172.16.42.1 23
```

The telnet service is deliberately unauthenticated because it is reachable
only over the point-to-point USB gadget used during bring-up.

## Restore Android

Restore the exact stock partitions recorded before installation, or use the
verified UnlockTool dumps. Restoring only another Android slot is insufficient:
the shared `userdata` now contains the Linux ext4 root and must be reformatted
or restored for Android. Do not blindly copy the old slot-A example; later
bring-up used a different active-slot arrangement.
`scripts/restore-stock-slot-a.ps1` is retained only for the original early-test
layout.

## Guardrails

Do not overwrite `nvram`, `nvdata`, `nvcfg`, `persist`, `proinfo`, `otp`,
`seccfg`, `preloader`, or GPT. They contain per-device calibration/security
data and are not needed for this port.

Never load the stock `oplus_chg.ko` in this userspace. It dereferences missing
Android/Oplus services and caused a reproducible kernel NULL dereference. The
local battery and charge-limit modules replace only the small subset needed
for UPower reporting and the BQ25890H charge-enable switch.
