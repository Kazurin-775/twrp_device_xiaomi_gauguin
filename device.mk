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

# ro.debuggable=1 ensures post_process_props.py appends "adb" instead of "none"
# to every partition prop file, so adbd starts at boot.
PRODUCT_ODM_PROPERTIES += ro.debuggable=1
PRODUCT_PRODUCT_PROPERTIES += ro.debuggable=1
PRODUCT_SYSTEM_EXT_PROPERTIES += ro.debuggable=1

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
