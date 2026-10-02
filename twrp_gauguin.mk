# SPDX-FileCopyrightText: 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

PRODUCT_PLATFORM := lito
DEVICE_PATH := device/xiaomi/gauguin

$(call inherit-product, vendor/twrp/config/common.mk)

PRODUCT_DEVICE := gauguin
PRODUCT_NAME := twrp_gauguin
PRODUCT_BRAND := Xiaomi
PRODUCT_MODEL := Redmi Note 9 Pro 5G
PRODUCT_MANUFACTURER := Xiaomi

$(call inherit-product, $(DEVICE_PATH)/device.mk)
