# SPDX-FileCopyrightText: 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

# Inherit from TWRP common config
$(call inherit-product, $(SRC_TARGET_DIR)/product/base.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit_only.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/emulated_storage.mk)
$(call inherit-product, vendor/twrp/config/common.mk)

# Build only for gauguin
TARGET_OTA_ASSERT_DEVICE := gauguin,gauguinpro,gauguininpro

# Crypto / FBE decryption (QCOM CAF)
PRODUCT_PACKAGES += \
    qcom_decrypt \
    qcom_decrypt_fbe

# keystore2 needs libsqlite.so; TWRP's static ld.config only searches
# /system/lib64, so build our own (matching tree's ICU) instead of
# borrowing the ROM's (ICU symbol mismatch).
PRODUCT_PACKAGES += \
    libsqlite

# post_process_props.py auto-appends persist.sys.usb.config=none to every
# partition prop file that lacks ro.debuggable=1; the merged ramdisk
# prop.default then ends with "none" (last section wins) and adbd never
# starts at boot. Add ro.debuggable to each partition so every section
# auto-appends "adb" instead.
PRODUCT_ODM_PROPERTIES += ro.debuggable=1
PRODUCT_PRODUCT_PROPERTIES += ro.debuggable=1
PRODUCT_SYSTEM_EXT_PROPERTIES += ro.debuggable=1

# Keymaster 4.0 enforces patchlevel binding: a key blob can only be used if
# the current boot reports OS/vendor patchlevels >= the ones stamped at key
# creation. The metadata key was created by the ROM (much newer), so report
# 2099-12-31 to always pass. The system_ext section is loaded last in the
# merged ramdisk prop.default, so these overrides win.
PRODUCT_SYSTEM_EXT_PROPERTIES += ro.build.version.security_patch=2099-12-31
PRODUCT_SYSTEM_EXT_PROPERTIES += ro.vendor.build.security_patch=2099-12-31

# Dynamic partitions
PRODUCT_USE_DYNAMIC_PARTITIONS := true

# fastbootd
PRODUCT_PACKAGES += \
    android.hardware.fastboot@1.0-impl-mock \
    fastbootd

# Soong namespaces
PRODUCT_SOONG_NAMESPACES += \
    $(DEVICE_PATH)

# Debugfs restrictions (matches PixelOS / gauguin ROM)
PRODUCT_DEBUG_FS_ALLOW_ALL := false
