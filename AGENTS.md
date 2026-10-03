# AGENTS.md — TWRP Device Tree for Xiaomi Gauguin

## Project Identity

- **Device:** Redmi Note 9 Pro 5G (M2007J17C), Mi 10T Lite 5G (M2007J17G), Mi 10i 5G (M2007J17I)
- **Codename:** gauguin
- **SoC:** Qualcomm SM7225 Snapdragon 750G 5G (lito platform)
- **Host OS:** PixelOS 17 (Android 16 / API 36)
- **Kernel:** 4.19 (Qualcomm CAF, from `kernel/xiaomi/gauguin`)
- **Target:** TWRP recovery image (non-A/B, boot header v2)

## Architecture Summary

| Property | Value |
|---|---|
| Boot header | v2 (Qualcomm-custom page-size layout, 4096-byte pages) |
| A/B? | **No** — separate recovery partition |
| Dynamic partitions | Yes, on 9126805504-byte "super" |
| Logical partitions | system, system_ext, product, vendor, odm |
| vendor_dlkm/system_dlkm | **None** — kernel 4.19 predates dlkm split |
| DTB source | dtbo partition **only** — no embedded DTB in boot/recovery images |
| Crypto | dm-default-key FBE + inlinecrypt_optimized + wrappedkey_v0 |
| Pixel format | BGRA_8888 |
| Arch | arm64-v8a + arm32 (armv8-2a-dotprod / armv8-2a) |

## Build Environment

**Manifest:** `https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp`, branch `twrp-12.1`.

**Do NOT use 14.1** — it pulls Mainline-split modules (`packages/modules/Security/` providing `android.security.apc`) that cascade into missing ninja edges (`libtar` → `android.security.apc-ndk_platform`). The 12.1 manifest has these modules inline.

Build recipe:
```bash
repo init -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp -b twrp-12.1
repo sync -j$(nproc)
# place this tree at device/xiaomi/gauguin
source build/envsetup.sh
source device/xiaomi/gauguin/vendorsetup.sh   # sets ALLOW_MISSING_DEPENDENCIES=true
lunch twrp_gauguin-eng
mka recoveryimage
```

### vendorsetup.sh Quirk

Minimal TWRP manifests may omit `tradefed_defaults` and other non-TWRP AOSP modules. `ALLOW_MISSING_DEPENDENCIES=true` tells soong to skip missing `defaults:` references at parse time. The SM8750 TWRP reference trees all have this line.

## Kernel Paths

**Prebuilt (preferred):** Drop `Image` + `dtb.img` into `prebuilt/`. BoardConfig.mk has dual detection — uses prebuilts if present, falls back to building from `kernel/xiaomi/gauguin` (config `vendor/lito-perf_defconfig vendor/xiaomi/gauguin.config`).

### extract_boot.py

Pure-Python boot image parser that handles both AOSP headers (v1–v4) and **Qualcomm-custom layouts**. Gauguin's boot image does NOT follow AOSP header layout — `page_size` and `header_version` live at non-standard offsets. The script handles this by scanning for known signatures when AOSP offsets don't parse.

## AVB Configuration

Non-A/B device with AVB enabled. Recovery partition MUST have its own signing key — AOSP build checks enforce this. Our BoardConfig sets:
```
BOARD_AVB_ENABLE := true
BOARD_AVB_MAKE_VBMETA_IMAGE_ARGS += --flags 3       # unlocked
BOARD_AVB_VBMETA_SYSTEM := system system_ext product
BOARD_AVB_VBMETA_SYSTEM_KEY_PATH := external/avb/test/data/testkey_rsa4096.pem
BOARD_AVB_RECOVERY_KEY_PATH := external/avb/test/data/testkey_rsa4096.pem
BOARD_AVB_RECOVERY_ALGORITHM := SHA256_RSA4096
BOARD_AVB_RECOVERY_ROLLBACK_INDEX := 1
BOARD_AVB_RECOVERY_ROLLBACK_INDEX_LOCATION := 1
```

Matches the original gauguin ROM tree (RSA4096, not RSA2048 like newer devices).

## Encryption / FBE

### Service chain (all from ramdisk blobs)

`init.recovery.qcom.rc` starts `vendor.qseecomd`, then `keymaster-4-0`
(`/vendor/bin/hw/android.hardware.keymaster@4.0-service-qti`) once qseecomd is
running. Blobs are pulled from the running ROM with `tools/extract_blobs.sh`
(read-only adb pulls) into `recovery/root/vendor/`. The keymaster TA is loaded
into the TEE by the bootloader from the `keymaster` partition — no TA firmware
file exists on the filesystem.

### USB

`init.recovery.usb.rc` (CAF/AOSP standard) owns the whole gadget chain:
configfs/functionfs setup, ffs mounts, `start adbd` on
`sys.usb.config=adb && sys.usb.configfs=1`, UDC bind. `init.recovery.qcom.rc`
only sets `sys.usb.config=adb` in `on boot`. Do NOT put `restart adbd` inside
property triggers — `sys.usb.ffs.ready=1` refires on every adbd start and
creates a 5-second kill loop.

### VINTF manifests (two of them, both required)

TWRP's libvintf is 4.0 — it cannot parse ROM manifests (`manifest.version 9.0`
fails, hwservicemanager then refuses ALL HAL registrations).

- **Device manifest** `recovery/root/vendor/etc/vintf/manifest.xml` — keymaster
  HAL, `version="1.0"` (a bare `<manifest>` also fails to parse). Lets
  keymaster register in hwservicemanager.
- **Framework manifest** `recovery/root/system/etc/vintf/manifest.xml` — AIDL
  `IKeystoreService/default`. servicemanager checks the framework manifest on
  `add`; if it's NULL (missing), keystore2 panics in a lazy-start loop with
  `NULL VINTF MANIFEST!: framework`.

`extract_blobs.sh` intentionally does NOT pull either manifest.

### Property workarounds (device.mk)

- `ro.debuggable=1` per partition (odm/product/system_ext): without it,
  post_process_props auto-appends `persist.sys.usb.config=none` to each
  section; the merged ramdisk prop.default ends on `none` (last section wins)
  and adbd never starts at boot.
- `ro.build.version.security_patch` / `ro.vendor.build.security_patch` =
  `2099-12-31` in system_ext (loaded last): keymaster 4.0 enforces
  patchlevel binding (current >= key-creation levels; the metadata key was
  created by the much newer ROM).
- `PRODUCT_PACKAGES += libsqlite`: keystore2 needs it; ROM's libsqlite.so
  references `ucol_setStrength_android` missing in TWRP 12.1's ICU.

### Decryption status / open blocker

TWRP 12.1's vold_decrypt path works up to keystore2 createOperation, which
fails with `In upgrade_keyblob_if_required_with: Upgrade failed.
Error::Km(ErrorCode(-8))` (INVALID_KEY_BLOB from the keymaster TA's
upgradeKey). Leading hypotheses:

1. The A16 ROM's vold created the metadata key via the **keymint (AIDL) chain**
   — verify on HLOS with `ps -A | grep -iE "keymint|keymaster"`. If keymint
   runs a different TA app than keymaster@4.0, the blob is in the wrong TA's
   namespace and A12.1 TWRP fundamentally needs the keymint chain (the
   twrp-xiaomi-17-series trees all do keymint + gatekeeper).
2. TEE state lives on the persist partition (see below) — if persist is not
   mounted in recovery, TA-side blob authentication can fail.

Iterate on missing blobs by rebuilding and checking logcat for
`cannot locate` / `CANNOT LINK` linker errors.

Gauguin uses Qualcomm File-Based Encryption with `dm-default-key`. Decryption is handled by `qcom_decrypt` + `qcom_decrypt_fbe` from `hardware/qcom-caf/common` (pulled via `BOARD_USES_QCOM_FBE_DECRYPTION := true`).

Fstab crypto flags (copied verbatim from stock `fstab.default`, do NOT change):
```
fileencryption=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized+wrappedkey_v0
metadata_encryption=aes-256-xts:wrappedkey_v0
keydirectory=/metadata/vold/metadata_encryption
```

Metadata partition mount flags also match stock exactly (`data=journal,commit=1,metadata_csum`) — divergence breaks FBE key access.

## persist Partition

- **DO NOT MODIFY.** Contains per-board calibration data (WiFi MAC, RF/NVRAM, possibly DRM nonces) that cannot be restored after wipe.
- Fstab mounts it **read-only**.
- 128 MB, ext4, on UFS.
- Do NOT add `encryptable=footer` — that's FDE syntax, gauguin uses FBE.
- **TA state lives here too**: some TEE apps store their data under
  `/mnt/vendor/persist/data/`. If persist is not mounted in recovery,
  TEE-side blob authentication may fail. Mounting read-only is fine for
  reading TA state; deleting files here can permanently break DRM/TEE state.

## Hardware Probe Commands — SAFE ONLY

Never run adb shell with `su` or any command that writes to block devices. For hardware info:

```bash
# Boot header version
adb shell getprop ro.boot.header_version
adb shell cat /proc/cmdline | grep bootconfig

# Super partition layout
adb shell lpdump /dev/block/by-name/super
adb shell ls -la /dev/block/by-name/

# Crypto scheme
adb shell cat /vendor/etc/fstab.default | grep userdata
adb shell getprop ro.crypto.volume.metadata.method

# Display / thermal
adb shell cat /sys/class/backlight/panel0-backlight/max_brightness
adb shell for z in /sys/devices/virtual/thermal/thermal_zone*/type; do echo "$z → $(cat $z)"; done
```

Never run: `su`, `dd` to block devices, `fastboot flash` anything without explicit user confirmation.

## Known Open Items (need hardware verification)

| Item | Current Value | Where | Action |
|---|---|---|---|
| Brightness path | `panel0-backlight` | BoardConfig.mk, init.recovery.qcom.rc | Verify on device |
| Max brightness | 2048 | BoardConfig.mk | Calibrate |
| Default brightness | 800 | init.recovery.qcom.rc | Calibrate |
| Thermal zone (CPU temp) | thermal_zone14 | BoardConfig.mk | Verify correct zone number |
| Touch/fingerprint/NFC modules | (none) | modules.load, TW_LOAD_VENDOR_MODULES | Load via kernel built-ins or add .ko paths |
| qcom_decrypt_fbe availability | hardware/qcom-caf/common | device.mk | Confirm present in 12.1 manifest |
| UFS storage controller | 1d84000.ufshc | recovery.fstab sysfs_path | From `androidboot.bootdevice` in cmdline |

## What Was Confirmed On Hardware

- Boot header **v2** (Qualcomm-custom, 4K pages)
- Kernel 4.19, Image @ offset 0x38, dtb in dtbo partition only
- Super partition size 9126805504, 5 logical partitions (no dlkm)
- Crypto: dm-default-key FBE + inlinecrypt + wrappedkey_v0
- persist is ext4 at 0x438 magic, 128 MB
- `/dev/block/by-name/` has no `_a`/`_b` suffixes → non-A/B confirmed

## Reference Trees

| Tree | Role |
|---|---|
| `android_device_xiaomi_gauguin/` (local) | Original LineageOS/PixelOS device tree — source of truth for partition sizes, AVB keys, crypto props, kernel config |
| `twp-xiaomi-17-series/` (local) | 4 SM8750 TWRP trees — structural reference only. DO NOT copy config values (different generation, v4 headers, A/B, dlkm partitions) |
| `https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp` | Build manifest — pin to `twrp-12.1` |

## License

Files with SPDX headers are derivative work from `android_device_xiaomi_gauguin/` (The LineageOS Project, Apache-2.0). Files without headers are original to this project.
