# TWRP Device Tree for Xiaomi Gauguin

Device tree for building Team Win Recovery Project (TWRP) for:
- Redmi Note 9 Pro 5G (M2007J17C)
- Mi 10T Lite 5G (M2007J17G)
- Mi 10i 5G (M2007J17I)

## Device Information

| Property     | Value |
| ------------ | ----- |
| Device       | Redmi Note 9 Pro 5G / Mi 10T Lite 5G / Mi 10i 5G |
| Codename     | Gauguin |
| SoC          | Qualcomm SM7225 Snapdragon 750G 5G (Lito) |
| CPU          | 2x2.2 GHz Kryo 570 & 6x1.8 GHz Kryo 570 |
| GPU          | Adreno 619 |
| Architecture | arm64-v8a |
| Boot header  | v2 (non-A/B) |
| Kernel       | 4.19 (from `kernel/xiaomi/gauguin`, prebuilt `Image` + `dtb.img` supported) |
| Display      | 1080 x 2400, 6.67" |

## Build Instructions

1. Initialize and sync a minimal TWRP AOSP manifest (**12.1 branch tested** — 14.1 pulls in Mainline-split
   modules that cascade into unresolvable ninja edges without a full AOSP checkout):
   ```
   repo init -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp -b twrp-12.1
   repo sync -j$(nproc)
   ```

2. Place this device tree at `device/xiaomi/gauguin`.

3. (Optional) Drop prebuilt kernel blobs — otherwise the tree falls back to building from
   `kernel/xiaomi/gauguin`:
   ```
   mkdir -p prebuilt
   cp /path/to/boot/Image prebuilt/
   cp /path/to/boot/dtb.img prebuilt/
   ```

4. **Set missing-deps tolerance.** Minimal manifest trees may omit some non-TWRP AOSP
   modules, causing build errors. The device tree ships a `vendorsetup.sh` that sets
   `ALLOW_MISSING_DEPENDENCIES=true` — source it explicitly if `envsetup.sh` does not
   pick it up:
   ```
   source build/envsetup.sh
   source device/xiaomi/gauguin/vendorsetup.sh
   echo $ALLOW_MISSING_DEPENDENCIES   # must print "true"
   ```

5. Build:
   ```
   lunch twrp_gauguin-eng
   mka recoveryimage
   ```

6. Flash:
   ```
   fastboot flash recovery out/target/product/gauguin/recovery.img
   ```

## Encryption Notes

Gauguin uses Qualcomm File-Based Encryption (FBE) with:
- `dm-default-key` metadata method
- AES-256-CTS filenames mode
- `inlinecrypt_optimized+wrappedkey_v0` inline encryption
- Metadata partition at `/dev/block/by-name/metadata`

`BOARD_USES_QCOM_FBE_DECRYPTION := true` pulls in `qcom_decrypt` + `qcom_decrypt_fbe`
from QCOM CAF, which handles the metadata key unwrap path for PixelOS.

## Known Caveats

- `TW_CUSTOM_CPU_TEMP_PATH` defaults to `/sys/devices/virtual/thermal/thermal_zone14/temp` —
  verify the correct zone on the target device (`cat /sys/class/thermal/thermal_zone*/type`).
- Touch / fingerprint / NFC modules may need to be loaded explicitly via
  `TW_LOAD_VENDOR_MODULES` once their .ko paths are known.
- The `qcom_decrypt_fbe` module comes from `hardware/qcom-caf/common` — ensure
  it is present in your build tree, otherwise FBE decryption will fail.

## Acknowledgements

- [PixelOS-Devices/android_device_xiaomi_gauguin](https://github.com/PixelOS-Devices/android_device_xiaomi_gauguin) — original device tree for Gauguin
- [antocorvo3000's sm8750 TWRP trees](https://github.com/antocorvo3000/twrp-xiaomi-17-series) — structural reference
- Team Win Recovery Project
- Android Open Source Project
