#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Extract the minimal vendor blob set needed for keymaster-4-0, gatekeeper-1-0
# and qseecomd to run inside the TWRP ramdisk (so /vendor never has to be
# mounted for decryption).
#
# The lib list is the union of the runtime /proc/<pid>/maps of qseecomd,
# keymaster-4-0 and gatekeeper-1-0 pulled from a live boot of the ROM
# (qseecomd-maps.txt / keymaster-maps.txt), plus libs found via static
# DT_NEEDED scanning.
#
# Run while booted into the normal ROM with `adb root` working (read-only pulls).

set -euo pipefail

DEST="$(dirname "$0")/../recovery/root/vendor"

pull() { # pull <device-path> <dest-subdir>
    local src="$1" dir="$DEST/$2"
    if adb shell "[ -e '$src' ]" >/dev/null 2>&1; then
        mkdir -p "$dir"
        adb pull "$src" "$dir/" >/dev/null
        echo "pulled $src"
    else
        echo "SKIP (missing on device): $src"
    fi
}

# adb shell output is CRLF-terminated; strip \r before iterating paths
list() { adb shell "ls -1 $1 2>/dev/null" | tr -d '\r' | grep -v '^$' || true; }

echo "==> keymaster / qseecom binaries"
pull /vendor/bin/qseecomd bin
pull /vendor/bin/hw/android.hardware.keymaster@4.0-service-qti bin/hw

echo "==> gatekeeper"
GK_BIN=android.hardware.gatekeeper@1.0-service-qti
pull "/vendor/bin/hw/$GK_BIN" bin/hw
pull /vendor/lib64/android.hardware.gatekeeper@1.0.so lib64
pull /vendor/lib64/hw/android.hardware.gatekeeper@1.0-impl-qti.so lib64/hw
# Everything else the process maps (libQSEEComAPI, libkeymasterdeviceutils,
# libqcbor, libion, libcrypto, libbase, libcutils, libutils, libhidlbase,
# libhardware, libc++) is already covered by the static list below.

echo "==> vendor libs (union of live-OS proc maps of qseecomd + keymaster)"
LIBS="
libQSEEComAPI.so
libqseed3.so
libkeymasterdeviceutils.so
libkeymasterprovision.so
libkeymasterutils.so
libqtikeymaster4.so
libqcbor.so
libdrmfs.so
libdrm.so
libdrmtime.so
libdiag.so
libdisplayconfig.qti.so
libGPreqcancel.so
libGPreqcancel_svc.so
libops.so
libqisl.so
librpmb.so
libsecureui.so
libsecureui_svcsock.so
libssd.so
libStDrvInt.so
libtime_genoff.so
libxml2.so
libion.so
libbase.so
libcutils.so
libutils.so
libhidlbase.so
libbinder.so
libc++.so
libcrypto.so
libhardware.so
android.hardware.keymaster@3.0.so
android.hardware.keymaster@4.0.so
android.hardware.keymaster@4.1.so
vendor.display.config@1.0.so
vendor.display.config@2.0.so
vendor.qti.hardware.tui_comm@1.0.so
"
for lib in $LIBS; do
    pull "/vendor/lib64/$lib" lib64
done

# NOTE: do NOT pull libsqlite.so from the ROM — the A16 build references ICU
# symbols (e.g. ucol_setStrength_android) missing from TWRP's libicuuc.
# Instead the tree builds its own matching libsqlite (device.mk PRODUCT_PACKAGES).

# Note: the keymaster TA itself is loaded into the TEE by the bootloader
# (from the "keymaster" partition) before userspace starts — there is no TA
# file on the filesystem to pull. qseecomd only needs /dev/qseecom.

# NOTE: do NOT pull /vendor/etc/vintf/manifest.xml — the ROM's A16 manifest
# (manifest.version 9.0) is unparseable by TWRP's libvintf and would make
# hwservicemanager refuse keymaster registration. A minimal hand-written
# manifest lives at recovery/root/vendor/etc/vintf/manifest.xml.

echo "==> fixing permissions"
find "$DEST/bin" "$DEST/bin/hw" -type f -exec chmod 755 {} \; 2>/dev/null || true

echo "done. Blobs are in $DEST"
