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

**Manifest:** `https://github.com/TWRP-Test/platform_manifest_twrp_aosp`, branch `twrp-16.0`.

This manifest uses AOSP 16.0.0_r1 as base and swaps in TWRP-Test forks:
- `TWRP-Test/android_bootable_recovery` @ `twrp-16.0` (TWRP recovery with built-in security_patch override)
- `TWRP-Test/android_system_vold` @ `twrp-16.0` (crypto/KeyStorage patches)
- `TWRP-Test/android_system_security` @ `twrp-16.0` (keystore2 fork)
- `TWRP-Test/android_vendor_twrp` @ `twrp-16.0` (vendor config)
- Plus forked build system, ICU, SQLite, sepolicy etc.

**Manifest layout:** `default.xml` (AOSP 16.0 base) includes `twrp-default.xml` (remove AOSP projects, add TWRP-Test forks) which includes `remove-minimal.xml` (strip unused AOSP modules). Also pulls Android 17.0.0_r1 `external/ublksrv` for UBLK support, LineageOS 23.2 for bash/nano/ntfs.

Build recipe:
```bash
repo init -u https://github.com/TWRP-Test/platform_manifest_twrp_aosp -b twrp-16.0
repo sync -j$(nproc)
# place this tree at device/xiaomi/gauguin
source build/envsetup.sh
lunch twrp_gauguin-bp2a-eng
mka recoveryimage
```

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

`init.recovery.qcom.rc` starts `vendor.qseecomd` and `prepare-crypto` at boot.
Decryption ordering is solved entirely in the device tree (no TWRP-source
patches), using the 17-series prepdecrypt pattern:

1. `recovery/root/system/bin/prepare-crypto.sh` (oneshot service) polls for the
   super mapper devices `/dev/block/mapper/{system,vendor}` — created by TWRP
   during `Setup_Fstab_Partitions`, right before `Decrypt_Data()` blocks in
   `getService(keymaster)` for up to 25 s. It temp-mounts both partitions ro,
   reads the real patchlevels from the ROM build.props, `resetprop`s them,
   `sed`s `/prop.default` to match, then sets `crypto.ready=1`. On any
   failure it still sets `crypto.ready=1` so the chain stays observable in
   logs.
2. `on property:crypto.ready=1` starts the `keymaster-4-0` service (the real
   HAL binary, `disabled` in rc) together with `gatekeeper-1-0` (see the
   Gatekeeper section below). keymaster registers mid-`getService`-wait
   with correct patchlevels cached, and TWRP's single automatic metadata
   decrypt attempt succeeds.

Why not just start keymaster from rc: it caches
`ro.vendor.build.security_patch` once at service start, and TWRP's built-in
override (`TW_OVERRIDE_SYSTEM_PROPS`, removed from BoardConfig) ran after the
first decrypt attempt and bypassed init, so rc triggers on the overridden
props never fire. The service intentionally has NO `interface` line: an
interface mapping would let hwservicemanager lazy-start keymaster before
qseecomd is ready. Blobs are pulled from the running ROM with
`tools/extract_blobs.sh` (read-only adb pulls) into `recovery/root/vendor/`.
The keymaster TA is loaded into the TEE by the bootloader from the
`keymaster` partition — no TA firmware file exists on the filesystem.

### The two-reader version-binding model (why BoardConfig carries version values)

Two processes read version/patchlevel props, at different times, and both
caches feed the TA's key-authorization check:

- **keystore2** starts at `on late-init` (ramdisk `etc/init/keystore2.rc`),
  ~10 ms **before** prepare-crypto resets anything, and reads
  `ro.build.version.release`, `ro.build.version.security_patch` and
  `ro.vendor.build.security_patch` once at startup (via `libkm_compat` →
  `libkeymaster4_1support`/`libkeymint`; proven by `/proc/<pid>/maps`).
  prepare-crypto therefore cannot influence this cache — the values must be
  correct at build time.
- **keymaster HAL** starts at `crypto.ready=1`, after prepare-crypto, so
  prepare-crypto's resetprops *do* control its cache.

BoardConfig.mk consequently carries a **super-version block**
(`PLATFORM_VERSION 99.87.36`, `PLATFORM_VERSION_LAST_STABLE $(PLATFORM_VERSION)`,
`PLATFORM_SECURITY_PATCH 2099-12-31`, `VENDOR_SECURITY_PATCH 2099-12-31`):
ceiling values keeping every requested tag ≥ any blob's tags, so the TA's
`begin` returns `KEY_REQUIRES_UPGRADE(-62)` and `upgradeKey` always succeeds.
This is not hardcoded-real-value staleness — the values are upper bounds,
not ROM values, so nothing goes stale when the ROM updates. The upgraded key
is never persisted (keystore2 records `key_id=None`); every boot repeating
`-62 → upgradeKey → begin` is **normal** for this configuration. Hazard
(accepted): any key *created* under recovery would bind to the super-values;
the decrypt path only retrieves/upgrades, never creates.

### /dev/qseecom node mode (qseecomd listener registration)

**Symptom:** every qseecomd hierarchy-1 listener registration (rpmb, ssd,
secure_ui, atime, fs, gpfs, qisl, gp_reqcancel, ops) failed with
`Error::opening QSEECom device` in TWRP — while the identical
`open("/dev/qseecom", O_RDWR)` succeeded from the adb shell and from the
keymaster HAL on the same boot. No kernel-side qseecom errors, no AVC denials,
identical failure for init-started and manually-launched daemons and with the
ramdisk or the real vendor mounted.

**Root cause (proven by strace):** qseecomd **drops itself to uid/gid 1000
(system)** — `setgid(1000)` + `setuid(1000)` +
`capset(CAP_SYS_RAWIO|CAP_BLOCK_SUSPEND)` — immediately before spawning the
listener threads. In TWRP the `/dev/qseecom` node keeps the driver default
`0600 root:root` (TWRP ships no ueventd rule for it), so every listener open
fails with plain-DAC **EACCES**. The shell and keymaster HAL open successfully
because they run as root. On HLOS the same daemon works because the vendor
ueventd rules grant system access to the node.

**Fix** (mirrors the twrp-xiaomi-17-series ref trees, which do both):
- `recovery/root/vendor/etc/ueventd.rc`: `/dev/qseecom 0660 system drmrpc` —
  ueventd applies this at coldboot, the durable fix
- `init.recovery.qcom.rc`: `chmod 0660` + `chown system drmrpc` in `on init`,
  **before** `start vendor.qseecomd` — belt-and-braces; `on init` runs before
  `on fs`, where qseecomd starts (moved there for the RPMB/bootdevice symlink
  ordering — see the service chain section)

**Why it matters:** dead listeners mean the TA cannot make reentrant callbacks
into the normal world (RPMB, SSD, …) — a candidate contributor to the
metadata-key `begin` failure (`-8`/`-7`).

### /dev/ion node mode (the fix that made metadata decryption work)

Same DAC mechanism, second device node: after the uid drop, qseecomd's qisl
(id 36864) and gp_reqcancel (id 4352) listeners allocate ION memory and log
`open /dev/ion failed: Permission denied` / `ION memalloc failed` on the
driver-default `0600 root:root` node. The qseecom fix alone still left these
two `-1`s — and the metadata-key `begin` kept returning `-8
INCOMPATIBLE_BLOCK_MODE`.

**Fix** (same two layers as /dev/qseecom, values from the 17-series refs):
`/dev/ion 0664 system system` in `vendor/etc/ueventd.rc` plus `chmod 0664` +
`chown system system` in `on init` before qseecomd starts.

**Verified outcome:** all listener registrations return 0, and the entire
decryption chain comes alive in the same boot — metadata key retrieved,
`/data` mounted (dm-5), `fscrypt_init_user0` installs the user-0 DE key,
all DE policies verified. The `-8` never reappeared with no vold-side changes,
which also retroactively confirms it was listener-driven (the TA could not
reach its normal-world services), not a key-parameter problem.

Two red herrings worth remembering:
- `libspl.so not found` (listener index 8) is **HLOS-normal** — the ROM ships
  no such library anywhere; do not chase it or add it to extract_blobs.
- `Error getting bootctrl v1.0 module` is unrelated to decryption (AB helper,
  we set `AB_OTA_UPDATER := false` anyway).

### Gatekeeper HAL (CE unlock / PIN verification)

Metadata (DE) decryption alone only mounts `/data` with the default-deleted
view. Unlocking **CE storage (the user's actual files)** requires verifying
the user's PIN through gatekeeper to unwrap the synthetic password. TWRP's
vold fork (`Decrypt.cpp`) binds the HAL **directly** — it first checks AIDL
`android.hardware.gatekeeper.IGatekeeper/default`, then falls back to HIDL
`IGatekeeper::getService()` on our ROM. `gatekeeperd` (`/system/bin/
gatekeeperd`) is **NOT needed** — verified in code, do not chase it.

The stock ROM's gatekeeper is QTI HIDL: `android.hardware.gatekeeper@1.0-
service-qti` plus `android.hardware.gatekeeper@1.0.so` and the `-impl-qti`
library — all three pulled by `extract_blobs.sh` (hardcoded pulls). It runs
as a `disabled` service started from `on property:crypto.ready=1`, sharing
the qseecomd TA stack with keymaster.

Three gotchas hit during bring-up:
1. **VINTF manifest:** the service must be declared in the device manifest
   (`@1.0::IGatekeeper/default` fqname) or hwservicemanager rejects its
   registration — `must be in VINTF manifest in order to register/get`,
   binder error -2147483648, 5 s restart loop.
2. **Service-manager lookup:** at CE time keystore2 first tries the AIDL
   name in servicemanager, which logs `Could not find
   android.hardware.gatekeeper.IGatekeeper/default in the VINTF manifest` —
   that is **normal** (it's the AIDL probe before the HIDL fallback), not a
   failure.
3. **TA coexistence:** gatekeeper attaches to the *same* keymasta TA
   instance as keymaster (`App is already loaded QSEE and app id = 1`). One
   boot failed the metadata `begin` with INCOMPATIBLE_BLOCK_MODE 2 ms after
   keymaster, which led to a 12 s `gatekeeper-delay` bisect patch — but then
   a successful boot ran **without** any delay: gatekeeper started 0.4 ms
   after keymaster and registered *before* the metadata `begin`, which still
   succeeded. Same configuration, different outcome → the race theory is
   unreproduced; starting both from `crypto.ready=1` together is the final
   shape and the delay was removed.

### RECOVERY_SDCARD_ON_DATA (the CE-decrypt fix)

**Symptom:** after gatekeeper came up, the PIN page appeared but verification
was never reached — strace on the gatekeeper service showed init, TA
registration, then idle; no `verify` call ever arrived. Manual UI decrypt
reported no error, DE data decrypted, CE did not.

**Root cause (chain-diagnosed):** without `RECOVERY_SDCARD_ON_DATA`, TWRP's
`datamedia` flag stays false, and:
1. `twrp.cpp main()` treats `/sdcard` as the settings-storage partition and
   skips the datamedia auto-detect (which requires no `/sdcard` partition in
   the fstab),
2. after DE decrypt, `PartitionManager::UnMount_Main_Partitions()`
   unmounts `/data` (`if (!datamedia) UnMount_By_Path("/data", true)`),
3. when the user enters the PIN, `Decrypt_Device()` calls
   `Mount_By_Path("/data")` as its gate — but `/data`'s
   `Actual_Block_Device` is still the raw `/dev/block/sda35` because
   `Find_Actual_Block_Device()` only maps `Decrypted_Block_Device` while
   `Is_Decrypted` is true, and stock `Decrypt_FBE_DE()` deliberately resets
   `Is_Decrypted=false` after the DE mount. Mounting raw sda35 (already
   mounted via dm) fails with **EBUSY**, `Decrypt_Device` silently returns,
   and `IGatekeeper::verify` is never called.

**Fix:** `RECOVERY_SDCARD_ON_DATA := true` in BoardConfig.mk — sets
`datamedia=true` from process start, `/sdcard` maps to `/data/media/0`, and
`/data` stays mounted across the DE→CE transition.

**Verified outcome:** PIN accepted → `add_auth_token` in keystore2 →
synthetic password blob unwrapped → `User 0 Decrypted Successfully!` →
`/data/media/0` shows the user's intact files. Full chain (metadata DE +
CE) works end-to-end.

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
  HAL `@4.0::IKeymasterDevice/default` and gatekeeper HAL
  `@1.0::IGatekeeper/default`, `version="1.0"` (a bare `<manifest>` also fails
  to parse). Without a fqname entry hwservicemanager rejects the
  registration with `must be in VINTF manifest in order to register/get` and
  the HAL loops in a 5 s restart cycle (-2147483648).
- **Framework manifest** `recovery/root/system/etc/vintf/manifest.xml` — AIDL
  `IKeystoreService/default`. servicemanager checks the framework manifest on
  `add`; if it's NULL (missing), keystore2 panics in a lazy-start loop with
  `NULL VINTF MANIFEST!: framework`. It also declares two HIDL infra entries
  the HIDL transport needs in recovery: `android.hidl.manager@1.2::
  IServiceManager/default` (without it hwservicemanager logs
  `HIDL is not supported on this device` and exits, so HIDL keymaster-4-0
  can never register and both keymaster and keystore2 crash-loop) and
  `android.hidl.memory@1.0::IMapper/ashmem` passthrough (hwbinder shared
  memory).

`extract_blobs.sh` intentionally does NOT pull either manifest.

### Property workarounds (device.mk / BoardConfig.mk)

- `ro.debuggable=1` per partition (odm/product/system_ext): without it,
  post_process_props auto-appends `persist.sys.usb.config=none` to each
  section; the merged ramdisk prop.default ends on `none` (last section wins)
  and adbd never starts at boot.
- `recovery/root/system/bin/prepare-crypto.sh`: reads the real HLOS patchlevels
  from the /system and /vendor build.props and `resetprop`s them before
  keymaster starts — see the service chain section above. Hardcoding real
  patchlevels into prop.default was tried and ROLLED BACK (project principle:
  no values that silently go stale against a moving ROM); the earlier
  `TW_OVERRIDE_SYSTEM_PROPS` macro was torn down (it ran after the first
  decrypt attempt and its writes bypassed init). The previous hardcoded
  `2099-12-31` prop was removed — it triggered TA upgrade demand which the
  HIDL keymaster-4-0 upgrade path couldn't complete in that era (superseded
  by the full super-version block; see the two-reader version-binding model
  section above).
- `PRODUCT_PACKAGES += libsqlite`: keystore2 needs it; ROM's libsqlite.so
  references `ucol_setStrength_android` missing in TWRP 12.1's ICU.

### Decryption status — WORKING

Full end-to-end decryption verified against the PixelOS ROM: metadata (DE)
key retrieved and `/data` mounted, PIN verified through the gatekeeper HAL,
synthetic password unwrapped, CE storage unlocked — `User 0 Decrypted
Successfully!`, `/data/media/0` intact.

The debugging story lives in the sections above:
- patchlevel timing → `prepare-crypto` service chain (top of Encryption/FBE)
- keystore2 early-read of version props → super-version BoardConfig block
  (two-reader version-binding model)
- qseecomd listener failures → `/dev/qseecom` node mode
- metadata `begin` `-8 INCOMPATIBLE_BLOCK_MODE` → `/dev/ion` node mode
- PIN never reaching `IGatekeeper::verify` → `RECOVERY_SDCARD_ON_DATA`

**Known soft failure mode:** if the super mapper devices never appear,
prepare-crypto times out after 30 s and fails soft (keymaster starts with
ramdisk patchlevels → TA demands upgrade → old failure, clearly logged as
`prepare-crypto: mapper devices never appeared`).

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
| qcom_decrypt_fbe availability | hardware/qcom-caf/common | device.mk | Confirm present in twrp-16.0 manifest |
| UFS storage controller | 1d84000.ufshc | recovery.fstab sysfs_path | From `androidboot.bootdevice` in cmdline |

## What Was Confirmed On Hardware

- Boot header **v2** (Qualcomm-custom, 4K pages)
- Kernel 4.19, Image @ offset 0x38, dtb in dtbo partition only
- Super partition size 9126805504, 5 logical partitions (no dlkm)
- Crypto: dm-default-key FBE + inlinecrypt + wrappedkey_v0
- persist is ext4 at 0x438 magic, 128 MB
- `/dev/block/by-name/` has no `_a`/`_b` suffixes → non-A/B confirmed
- **FBE decryption fully working** (DE + CE): metadata key retrieval,
  gatekeeper PIN verify, synthetic password unwrap, `/data/media/0`
  accessible with user data intact

## Reference Trees

| Tree | Role |
|---|---|
| [PixelOS-Devices/android_device_xiaomi_gauguin](https://github.com/PixelOS-Devices/android_device_xiaomi_gauguin) | Original LineageOS/PixelOS device tree — source of truth for partition sizes, AVB keys, crypto props, kernel config |
| [antocorvo3000/twrp-xiaomi-17-series](https://github.com/antocorvo3000/twrp-xiaomi-17-series) | Reference TWRP device trees (different generation, v4 headers, A/B, dlkm partitions) |
| [TWRP-Test/platform_manifest_twrp_aosp](https://github.com/TWRP-Test/platform_manifest_twrp_aosp) | Build manifest — branch `twrp-16.0` |

## License

Files with SPDX headers are derivative work from `android_device_xiaomi_gauguin/` (The LineageOS Project, Apache-2.0). Files without headers are original to this project.
