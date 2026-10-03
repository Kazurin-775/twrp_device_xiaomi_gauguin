# TWRP Device Tree for Xiaomi Gauguin

Device tree for building Team Win Recovery Project (TWRP) for:
- Redmi Note 9 Pro 5G (M2007J17C)
- Mi 10T Lite 5G (M2007J17G)
- Mi 10i 5G (M2007J17I)

Target ROM: PixelOS 17 (Android 16 / API 36). The tree follows the stock
gauguin configuration — dynamic partitions on super, dm-default-key FBE,
4.19 kernel.

## Device Information

| Property     | Value |
| ------------ | ----- |
| Device       | Redmi Note 9 Pro 5G / Mi 10T Lite 5G / Mi 10i 5G |
| Codename     | Gauguin |
| SoC          | Qualcomm SM7225 Snapdragon 750G 5G (Lito) |
| CPU          | 2x2.2 GHz Kryo 570 & 6x1.8 GHz Kryo 570 |
| GPU          | Adreno 619 |
| Architecture | arm64-v8a |
| Boot header  | v2 (non-A/B, separate recovery partition) |
| Kernel       | 4.19, prebuilt `Image` + `dtb.img` in `prebuilt/` |
| Display      | 1080 x 2400, 6.67" |

## Build Instructions

1. Initialize and sync the TWRP-Test AOSP 16.0 manifest:
   ```
   repo init -u https://github.com/TWRP-Test/platform_manifest_twrp_aosp -b twrp-16.0
   repo sync -j$(nproc)
   ```

   This manifest uses AOSP 16.0.0_r1 as base and swaps in TWRP-Test forks
   (`android_bootable_recovery`, `android_system_vold`, `android_system_security`, etc.)
   on the `twrp-16.0` revision. It also pulls Android 17.0.0_r1 `external/ublksrv`
   for UBLK support and LineageOS 23.2 for bash/nano/ntfs.

2. Place this device tree at `device/xiaomi/gauguin`.

3. Drop prebuilt kernel blobs into `prebuilt/` — BoardConfig.mk has dual detection,
   prebuilts win if present, otherwise it builds from `kernel/xiaomi/gauguin`
   (config `vendor/lito-perf_defconfig vendor/xiaomi/gauguin.config`):
   ```
   mkdir -p prebuilt
   cp /path/to/boot/Image prebuilt/
   cp /path/to/boot/dtb.img prebuilt/
   cp /path/to/boot/recovery_dtbo prebuilt/
   ```

4. Build:
   ```
   source build/envsetup.sh
   lunch twrp_gauguin-bp2a-eng
   mka recoveryimage
   ```

5. Flash:
   ```
   fastboot flash recovery out/target/product/gauguin/recovery.img
   ```

## Encryption / FBE

Gauguin uses Qualcomm File-Based Encryption (FBE) with:
- `dm-default-key` metadata method
- AES-256-CTS filenames mode
- `inlinecrypt_optimized+wrappedkey_v0` inline encryption
- Metadata partition at `/dev/block/by-name/metadata`

`BOARD_USES_QCOM_FBE_DECRYPTION := true` pulls in `qcom_decrypt` + `qcom_decrypt_fbe`
from QCOM CAF, which handles the metadata key unwrap path.

### Patchlevel binding fix

Gauguin's HLOS runs **HIDL keymaster-4-0** only (no KeyMint AIDL). The keymaster TA
enforces patchlevel binding: when the current boot's OS/vendor patchlevels are newer
than what the metadata key blob was created with, the TA demands a key upgrade
(`KM_ERROR_KEY_REQUIRES_UPGRADE` = -62). The HIDL keymaster-4-0 upgrade path breaks in
TWRP's partial TEE state (`-8` / `-33`).

The fix avoids triggering upgrade at all:
- `TW_OVERRIDE_SYSTEM_PROPS` reads `ro.build.version.security_patch` from `/system/build.prop`
- `TW_OVERRIDE_PROPS_ADDITIONAL_PARTITIONS := vendor system` also mounts `/vendor`
  and reads `ro.vendor.build.security_patch` from `vendor/build.prop`
- Both values are passed through `resetprop` so TWRP runs with the **exact same patchlevels
  as the ROM that created the key**, and the TA accepts `begin` directly.

This is the same mechanism the `recovery_device_generic_marmalade` reference tree uses.

### Property workarounds

- **`ro.debuggable=1`** per partition (odm/product/system_ext): without it,
  `post_process_props.py` auto-appends `persist.sys.usb.config=none` to every
  partition prop file; the merged ramdisk `prop.default` ends on `none`
  (last section wins) and adbd never starts at boot.
- **`libsqlite`**: keystore2 needs it; the ROM's libsqlite.so references
  `ucol_setStrength_android` which TWRP 12.1's ICU lacks, so we build our own.

## VINTF manifests (two required)

TWRP 12.1's libvintf 4.0 cannot parse modern ROM manifests (`manifest.version 9.0`).
Ship minimal manifests in the ramdisk:

- **Device manifest** `recovery/root/vendor/etc/vintf/manifest.xml` — declares the
  keymaster HAL registration so hwservicemanager accepts it.
- **Framework manifest** `recovery/root/system/etc/vintf/manifest.xml` — declares
  `IKeystoreService/default` so servicemanager allows keystore2 to register.
  Without it, keystore2 panics in a lazy-start loop with
  `NULL VINTF MANIFEST!: framework`.

`tools/extract_blobs.sh` intentionally does NOT pull either manifest.

## Blob extraction

`tools/extract_blobs.sh` pulls vendor HAL binaries from the running ROM via adb
(read-only). It extracts the QSEE/keymaster stack:
- `android.hardware.keymaster@4.0-service-qti`
- `libqtikeymaster4.so`, `libQSEEComAPI.so`, `libQSEECom.so`
- Other dependencies

Pulls land in `recovery/root/vendor/{bin,lib64}`. The keymaster TA itself is
loaded from the `keymaster` partition by the bootloader — no firmware file exists
on the filesystem.

## Service chain

```
init.recovery.qcom.rc:
  on fs: wait /dev/qseecom, chmod 0660
  on init: start vendor.qseecomd
  on property:init.svc.vendor.qseecomd=running: start keymaster-4-0
```

The keymaster HAL must not start before qseecomd. USB gadget setup lives entirely
in `init.recovery.usb.rc` — don't touch `sys.usb.ffs.ready` with `restart adbd`,
it refires on every start and creates a 5-second kill loop.

## Known Caveats

- `TW_CUSTOM_CPU_TEMP_PATH` defaults to `/sys/devices/virtual/thermal/thermal_zone14/temp`
  — verify the correct zone (`cat /sys/class/thermal/thermal_zone*/type`).
- Touch / fingerprint / NFC modules may need `TW_LOAD_VENDOR_MODULES` once .ko paths are known.
- The `qcom_decrypt_fbe` module comes from `hardware/qcom-caf/common` — ensure it is present
  in your build tree, otherwise FBE decryption will fail.
- **persist partition is read-only. DO NOT MODIFY.** It holds calibration data (WiFi MAC,
  RF/NVRAM, DRM nonces) that cannot be restored after wipe. Some TEE apps also store state
  under `/mnt/vendor/persist/data/` — mounting it read-only is sufficient for TA auth.

## Acknowledgements

- [PixelOS-Devices/android_device_xiaomi_gauguin](https://github.com/PixelOS-Devices/android_device_xiaomi_gauguin) — original device tree
- [TWRP-Test/platform_manifest_twrp_aosp](https://github.com/TWRP-Test/platform_manifest_twrp_aosp) — twrp-16.0 manifest (AOSP 16.0 base with TWRP-Test forks)
- [antocorvo3000's sm8750 TWRP trees](https://github.com/antocorvo3000/twrp-xiaomi-17-series) — reference TWRP device trees
- Team Win Recovery Project
- Android Open Source Project
