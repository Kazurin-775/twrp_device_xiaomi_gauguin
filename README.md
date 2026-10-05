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

### Version-binding fix (two-reader model + super-version BoardConfig)

Gauguin's HLOS runs **HIDL keymaster-4-0** only (no KeyMint AIDL). The keymaster TA
enforces patchlevel binding: when the requesting process's OS/vendor version tags are
newer than what the metadata key blob was created with, the TA demands a key upgrade
(`KM_ERROR_KEY_REQUIRES_UPGRADE` = -62).

Two processes read version/patchlevel props, at different times, and both caches
feed the TA's authorization check:

- **keystore2** starts at `on late-init`, ~10 ms *before* any prop override can run,
  and reads `ro.build.version.release`, `ro.build.version.security_patch` and
  `ro.vendor.build.security_patch` once at startup (via `libkm_compat` →
  `libkeymint` support code; proven by `/proc/<pid>/maps`). Its cached values feed
  the request tags sent to the TA — these must be correct **at build time**.
- **keymaster HAL** starts at `crypto.ready=1`, after prepare-crypto, so its cache
  *is* controllable at runtime.

The build-time half is BoardConfig.mk's **super-version block**:

```make
PLATFORM_VERSION := 99.87.36
PLATFORM_VERSION_LAST_STABLE := $(PLATFORM_VERSION)
PLATFORM_SECURITY_PATCH := 2099-12-31
VENDOR_SECURITY_PATCH := 2099-12-31
```

These are **ceiling values, not real ROM values** — every requested tag is ≥ any
blob's tags, so `begin` always returns -62 first and `upgradeKey` always succeeds
(upward-only migration). Nothing goes stale when the ROM updates. The upgraded key
is never persisted (keystore2 records `key_id=None`); every boot repeating
`-62 → upgradeKey → begin` is normal. Caveat: any key *created* under recovery
would bind to the super-values, so the decrypt path must only retrieve/upgrade.

The runtime half is `recovery/root/system/bin/prepare-crypto.sh` (an init service
started at boot): it waits for the super mapper devices, temp-mounts /system and
/vendor read-only, reads the **real** ROM patchlevels from their build.props,
`resetprop`s them (and `sed`s `/prop.default` to match), then sets `crypto.ready=1`
— which triggers `start keymaster-4-0` in `init.recovery.qcom.rc` with correct
values already cached.

Why the indirection: keymaster caches `ro.vendor.build.security_patch` once at
service start, and TWRP's own override mechanism (`TW_OVERRIDE_SYSTEM_PROPS`)
ran *after* the first decrypt attempt and bypassed init, so rc triggers on the
overridden props never fired.

This is the same mechanism the reference trees use (`prepdecrypt` pattern), adapted
for a non-A/B HIDL keymaster-4.0 device.

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
  keymaster (`@4.0::IKeymasterDevice/default`) and gatekeeper
  (`@1.0::IGatekeeper/default`) HALs so hwservicemanager accepts their
  registrations. Without a matching fqname entry the HAL is rejected with
  `must be in VINTF manifest in order to register/get` and restart-loops.
- **Framework manifest** `recovery/root/system/etc/vintf/manifest.xml` — declares
  `IKeystoreService/default` so servicemanager allows keystore2 to register.
  Without it, keystore2 panics in a lazy-start loop with
  `NULL VINTF MANIFEST!: framework`. It also declares `android.hidl.manager
  @1.2::IServiceManager/default` (keeps hwservicemanager alive; without it it
  logs `HIDL is not supported on this device`, exits, and HIDL keymaster-4-0
  can never register) and `android.hidl.memory@1.0::IMapper/ashmem` passthrough
  (hwbinder shared memory).

`tools/extract_blobs.sh` intentionally does NOT pull either manifest.

## Blob extraction

`tools/extract_blobs.sh` pulls vendor HAL binaries from the running ROM via adb
(read-only). It extracts the QSEE/keymaster stack:
- `android.hardware.keymaster@4.0-service-qti`
- `libqtikeymaster4.so`, `libQSEEComAPI.so`, `libQSEECom.so`
- `android.hardware.gatekeeper@1.0-service-qti` (+ its `-impl` library and
  `android.hardware.gatekeeper@1.0.so`) for CE / PIN verification
- Other dependencies

Pulls land in `recovery/root/vendor/{bin,lib64}`. The keymaster TA itself is
loaded from the `keymaster` partition by the bootloader — no firmware file exists
on the filesystem.

## Service chain

```
init.recovery.qcom.rc:
  on init: chmod 0660 /dev/qseecom, chown system drmrpc
  on init: chmod 0664 /dev/ion, chown system system
  on fs: wait for + symlink /dev/block/bootdevice, then
         start vendor.qseecomd, start prepare-crypto
  on property:crypto.ready=1: start keymaster-4-0, start gatekeeper-1-0
```

The `chmod`/`chown` must run before qseecomd starts: the daemon **drops itself
to uid 1000 (system)** right before spawning its listener threads, and without
a ueventd rule (`recovery/root/vendor/etc/ueventd.rc`) the nodes stay
driver-default `0600 root:root` — every listener registration then fails with
EACCES and the TA loses its reentrant callback services (RPMB, SSD, …). Both
node rules mirror the reference trees, which ship both the ueventd rules and
the rc chmods. `/dev/ion` matters as much as `/dev/qseecom`: with only the
latter fixed, the qisl/gp_reqcancel listeners still fail and metadata
decryption dies with `-8 INCOMPATIBLE_BLOCK_MODE`; with both fixed the whole
chain works (metadata key → `/data` mounted → DE keys installed).

`prepare-crypto` signals `crypto.ready=1` only after the real ROM patchlevels
are in place — keymaster caches them at service start, so it must never start
earlier (see the version-binding section above). keymaster and gatekeeper start
**together** from that trigger: gatekeeper shares the keymasta TA instance
with keymaster, and a successful boot proved that coexistence is fine
(gatekeeper registered *before* the metadata `begin`, which still succeeded) —
an earlier suspicion of a startup race led to a 12 s delay that was later
removed as unnecessary.

## CE decryption (PIN → user data)

Metadata decryption alone mounts `/data` with the default-deleted view;
seeing the user's actual files requires unlocking **CE storage**, which goes
through the gatekeeper HAL (bound directly by TWRP's vold — `gatekeeperd` is
not needed). `BoardConfig.mk` sets **`RECOVERY_SDCARD_ON_DATA := true`**,
which is mandatory here: without it TWRP unmounts `/data` after DE decrypt
(`!datamedia` branch of `UnMount_Main_Partitions`), and the PIN-time remount
in `Decrypt_Device` then falls back to the raw block device (the dm device is
only linked while `Is_Decrypted` is true, which resets after DE), fails with
EBUSY and `IGatekeeper::verify` is never reached — the PIN page appears but
does nothing. With the flag set, `/sdcard` maps to `/data/media/0` and the
whole chain is verified working end-to-end: PIN accepted → auth token →
synthetic password unwrapped → `User 0 Decrypted Successfully!`.

The keymaster HAL must not start before qseecomd. USB gadget setup lives entirely
in `init.recovery.usb.rc` — don't touch `sys.usb.ffs.ready` with `restart adbd`,
it refires on every start and creates a 5-second kill loop.

## Known Caveats

- `TW_CUSTOM_CPU_TEMP_PATH` is `/sys/devices/virtual/thermal/thermal_zone10/temp`
  — zone14 is battery voltage (pm6150l-vph-lvl2), not temperature; re-check the
  zone mapping if readings look wrong (`cat /sys/class/thermal/thermal_zone*/type`).
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
