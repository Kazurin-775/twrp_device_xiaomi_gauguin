# SPDX-FileCopyrightText: 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

DEVICE_PATH := device/xiaomi/gauguin

# Architecture
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-2a-dotprod
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := cortex-a55
TARGET_CPU_VARIANT_RUNTIME := kryo570

TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := armv8-2a
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := cortex-a55
TARGET_2ND_CPU_VARIANT_RUNTIME := kryo570

ENABLE_CPUSETS := true
ENABLE_SCHEDBOOST := true

# Bootloader
TARGET_BOOTLOADER_BOARD_NAME := gauguin
TARGET_NO_BOOTLOADER := true
TARGET_USES_UEFI := true

# Assert
TARGET_OTA_ASSERT_DEVICE := gauguin,gauguinpro,gauguininpro

# DTB/DTBO
# Header v2 has no dedicated DTBO field — pack DTBO into the "second" slot
TARGET_PREBUILT_DTB := $(DEVICE_PATH)/prebuilt/dtb.img
BOARD_MKBOOTIMG_ARGS += --dtb $(TARGET_PREBUILT_DTB)
BOARD_MKBOOTIMG_ARGS += --second $(DEVICE_PATH)/prebuilt/recovery_dtbo

# Kernel: 4.19 (lito platform), no dlkm — vendor modules are built into
# the vendor partition, no separate vendor_dlkm/system_dlkm images exist.
# Kernel
BOARD_KERNEL_CMDLINE := \
    androidboot.hardware=qcom \
    androidboot.memcg=1 \
    androidboot.usbcontroller=a600000.dwc3 \
    cgroup.memory=nokmem,nosocket \
    loop.max_part=7 \
    lpm_levels.sleep_disabled=1 \
    msm_rtb.filter=0x237 \
    pcie_ports=compat \
    service_locator.enable=1 \
    swiotlb=2048 \
    iptable_raw.raw_before_defrag=1 \
    ip6table_raw.raw_before_defrag=1
BOARD_KERNEL_CMDLINE += androidboot.init_fatal_reboot_target=recovery

BOARD_KERNEL_PAGESIZE := 4096
BOARD_KERNEL_IMAGE_NAME := Image
BOARD_BOOTIMG_HEADER_VERSION := 2
BOARD_KERNEL_BASE := 0x00000000
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOTIMG_HEADER_VERSION)
BOARD_RAMDISK_USE_LZ4 := true

TARGET_NO_KERNEL := false
TARGET_KERNEL_ARCH := $(TARGET_ARCH)

# Prebuilt kernel — preferred path
# NOTE: DTB IS embedded via --dtb above (needed for recovery boot even though
# stock ROM uses a separate dtbo partition). BOARD_KERNEL_SEPARATED_DTBO still
# applies for dtbo.img packaging during build.
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/Image

ifneq ($(wildcard $(TARGET_PREBUILT_KERNEL)),)
TARGET_FORCE_PREBUILT_KERNEL := true
else
TARGET_PREBUILT_KERNEL :=
TARGET_KERNEL_SOURCE := kernel/xiaomi/gauguin
TARGET_KERNEL_CONFIG := vendor/lito-perf_defconfig vendor/xiaomi/gauguin.config
endif

# Platform
TARGET_BOARD_PLATFORM := lito
TARGET_BOARD_PLATFORM_GPU := qcom-adreno619
TARGET_USES_HARDWARE_QCOM_BOOTCTRL := true
QCOM_BOARD_PLATFORMS += $(TARGET_BOARD_PLATFORM)

# Partition Info
BOARD_FLASH_BLOCK_SIZE := 262144 # (BOARD_KERNEL_PAGESIZE * 64)

BOARD_BOOTIMAGE_PARTITION_SIZE := 134217728
BOARD_CACHEIMAGE_PARTITION_SIZE := 402653184
BOARD_DTBOIMG_PARTITION_SIZE := 33554432
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 134217728

# Super / Dynamic Partitions
BOARD_SUPER_PARTITION_SIZE := 9126805504
BOARD_SUPER_PARTITION_GROUPS := qti_dynamic_partitions
BOARD_QTI_DYNAMIC_PARTITIONS_SIZE := 9122611200 # BOARD_SUPER_PARTITION_SIZE - 4MB
BOARD_QTI_DYNAMIC_PARTITIONS_PARTITION_LIST := \
    system \
    system_ext \
    product \
    odm \
    vendor

BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_SYSTEM_EXTIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_ODMIMAGE_FILE_SYSTEM_TYPE := ext4

TARGET_COPY_OUT_ODM := odm
TARGET_COPY_OUT_PRODUCT := product
TARGET_COPY_OUT_SYSTEM_EXT := system_ext
TARGET_COPY_OUT_VENDOR := vendor

# Recovery
TARGET_NO_RECOVERY := false
BOARD_HAS_LARGE_FILESYSTEM := true
BOARD_HAS_NO_SELECT_BUTTON := true
BOARD_SUPPRESS_SECURE_ERASE := true
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/recovery/root/system/etc/recovery.fstab
TARGET_USES_MKE2FS := true

# Metadata / Crypto / Platform version (needed for FBE init on PixelOS 17)
BOARD_USES_METADATA_PARTITION := true
BOARD_USES_QCOM_FBE_DECRYPTION := true
PLATFORM_VERSION := 99.87.36
PLATFORM_VERSION_LAST_STABLE := $(PLATFORM_VERSION)

# AVB
BOARD_AVB_ENABLE := true
BOARD_AVB_MAKE_VBMETA_IMAGE_ARGS += --flags 3
BOARD_AVB_VBMETA_SYSTEM := system system_ext product
BOARD_AVB_VBMETA_SYSTEM_KEY_PATH := external/avb/test/data/testkey_rsa4096.pem
BOARD_AVB_VBMETA_SYSTEM_ALGORITHM := SHA256_RSA4096
BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX := $(PLATFORM_SECURITY_PATCH_TIMESTAMP)
BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX_LOCATION := 1
BOARD_AVB_RECOVERY_ALGORITHM := SHA256_RSA4096
BOARD_AVB_RECOVERY_KEY_PATH := external/avb/test/data/testkey_rsa4096.pem
BOARD_AVB_RECOVERY_ROLLBACK_INDEX := 1
BOARD_AVB_RECOVERY_ROLLBACK_INDEX_LOCATION := 1

# TWRP specific build flags
TARGET_RECOVERY_QCOM_RTC_FIX := true
TARGET_RECOVERY_PIXEL_FORMAT := BGRA_8888
TARGET_USE_CUSTOM_LUN_FILE_PATH := /config/usb_gadget/g1/functions/mass_storage.0/lun.%d/file
TW_THEME := portrait_hdpi
TW_BRIGHTNESS_PATH := "/sys/class/backlight/panel0-backlight/brightness"
TW_MAX_BRIGHTNESS := 2048
TW_DEFAULT_BRIGHTNESS := 800
# thermal_zone14 is battery voltage (pm6150l-vph-lvl2), use SoC zone instead
TW_CUSTOM_CPU_TEMP_PATH := "/sys/devices/virtual/thermal/thermal_zone10/temp"
TW_EXCLUDE_DEFAULT_USB_INIT := true
TW_EXTRA_LANGUAGES := true
TW_INCLUDE_CRYPTO := true
TW_NO_EXFAT_FUSE := true
TW_NO_HAPTICS := true
TW_NO_SCREEN_BLANK := true
TW_INCLUDE_REPACKTOOLS := true
TW_INCLUDE_RESETPROP := true

# Read security patch levels from the mounted ROM partitions at runtime.
# The HIDL keymaster-4-0 TA enforces patchlevel binding (current >= creation),
# and an upgrade path bug makes it fail with -8/-33 when triggered. By reading
# the real HLOS values from /system and /vendor build.prop we match exactly
# what the blob was created with and avoid the TA demanding an upgrade at all.
TW_OVERRIDE_PROPS_ADDITIONAL_PARTITIONS := vendor system
TW_OVERRIDE_SYSTEM_PROPS := \
    "ro.build.version.security_patch;ro.vendor.build.security_patch"

TARGET_RECOVERY_DEVICE_MODULES += \
    libdmabufheap \
    libion \
    libxml2

RECOVERY_LIBRARY_SOURCE_FILES += \
    $(TARGET_OUT_SHARED_LIBRARIES)/libdmabufheap.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/libion.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/libxml2.so

# TWRP Debug Flags
TARGET_USES_LOGD := true
TWRP_INCLUDE_LOGCAT := true
TARGET_RECOVERY_DEVICE_MODULES += debuggerd
RECOVERY_BINARY_SOURCE_FILES += $(TARGET_OUT_EXECUTABLES)/debuggerd
TARGET_RECOVERY_DEVICE_MODULES += strace
RECOVERY_BINARY_SOURCE_FILES += $(TARGET_OUT_EXECUTABLES)/strace

#
# For local builds only
#
# TWRP zip installer
ifneq ($(wildcard bootable/recovery/installer/.),)
    USE_RECOVERY_INSTALLER := true
    RECOVERY_INSTALLER_PATH := bootable/recovery/installer
endif

# Custom TWRP Versioning
ifneq ($(wildcard device/common/version-info/.),)
    include device/common/version-info/custom_twrp_version.mk

    ifeq ($(CUSTOM_TWRP_VERSION),)
        CUSTOM_TWRP_VERSION := $(shell date +%Y%m%d)-01
    endif
endif
#
# end local build flags
#
