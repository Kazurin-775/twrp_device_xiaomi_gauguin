#!/usr/bin/env bash
#
# extract_boot.sh — Extract kernel Image and dtb.img from a boot.img
# using AOSP platform tools (unpackbootimg + mkbootimg).
#
# Usage:
#   ./extract_boot.sh <boot.img> [--out <dir>]
#
# The script auto-detects boot header v1–v4, pulls out kernel + dtb/dtbo,
# and writes the two prebuilt blobs into the device tree's prebuilt/ dir
# by default (override with --out).
#
# Requires: unpackbootimg and mkbootimg on PATH (both come from
#   AOSP system/tools/mkbootimg after building `mkbootimg_host`).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── arg parsing ──────────────────────────────────────────────────────────────
BOOT_IMG=""
OUT_DIR="$SCRIPT_DIR/prebuilt"
KEEP_UNPACK=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --out)        OUT_DIR="$2"; shift 2 ;;
        --keep)       KEEP_UNPACK=1; shift ;;
        -h|--help)
            sed -n '2,20p' "$0"
            exit 0 ;;
        *)            BOOT_IMG="$1"; shift ;;
    esac
done

if [[ -z "$BOOT_IMG" || ! -f "$BOOT_IMG" ]]; then
    echo "error: boot image not found: ${BOOT_IMG:-<none>}" >&2
    echo "usage: $0 <boot.img> [--out <dir>] [--keep]" >&2
    exit 1
fi

# ── tool checks ──────────────────────────────────────────────────────────────
for t in unpackbootimg mkbootimg; do
    if ! command -v "$t" &>/dev/null; then
        echo "error: '$t' not on PATH." >&2
        echo "  Build from AOSP:" >&2
        echo "    m mkbootimg_host" >&2
        echo "  Or grab a prebuilt from:" >&2
        echo "    https://github.com/osm0sis/magiskboot (magiskboot unpack -h boot.img)" >&2
        exit 1
    fi
done

# ── unpack ──────────────────────────────────────────────────────────────────
WORK_DIR="$(mktemp -d -t extract_boot.XXXXXX)"
trap '[[ $KEEP_UNPACK -eq 0 ]] && rm -rf "$WORK_DIR"' EXIT

echo "==> Unpacking $(basename "$BOOT_IMG")"
unpackbootimg --boot_img "$BOOT_IMG" --out "$WORK_DIR" --format mkbootimg 2>&1 | sed 's/^/   /'

echo "==> Boot header info"
HEADER_INFO="$(mkbootimg --boot_img "$BOOT_IMG" --format mkbootimg --kernel /dev/null 2>&1)" \
    || true
echo "$HEADER_INFO" | grep -E 'header_version|kernel_size|kernel_offset|ramdisk_size|dtb_size|dtb_offset|cmdline|os_version' | sed 's/^/   /'

# ── extract kernel ───────────────────────────────────────────────────────────
KERNEL_FILE="$(ls "$WORK_DIR"/*-kernel 2>/dev/null || true)"
if [[ -n "$KERNEL_FILE" && -s "$KERNEL_FILE" ]]; then
    mkdir -p "$OUT_DIR"
    cp "$KERNEL_FILE" "$OUT_DIR/Image"
    echo "==> Kernel:  $OUT_DIR/Image  ($(stat -f%z "$OUT_DIR/Image") bytes)"
else
    echo "!!! No kernel extracted — boot image may be GKI, vendor_boot, or corrupted" >&2
    exit 2
fi

# ── extract dtb ──────────────────────────────────────────────────────────────
DTB_FILE="$(ls "$WORK_DIR"/*-dtb 2>/dev/null || true)"
if [[ -n "$DTB_FILE" && -s "$DTB_FILE" ]]; then
    cp "$DTB_FILE" "$OUT_DIR/dtb.img"
    echo "==> DTB:     $OUT_DIR/dtb.img  ($(stat -f%z "$OUT_DIR/dtb.img") bytes)"
else
    echo "!!! No DTB extracted — boot image may use a separate dtbo partition" >&2
    echo "    If header_version >= 3, dtb is usually in vendor_boot, not boot." >&2
fi

# ── extract dtbo (optional, for reference) ───────────────────────────────────
DTBO_FILE="$(ls "$WORK_DIR"/*-second 2>/dev/null || true)"
if [[ -n "$DTBO_FILE" && -s "$DTBO_FILE" ]]; then
    cp "$DTBO_FILE" "$OUT_DIR/dtbo.img"
    echo "==> DTBO:    $OUT_DIR/dtbo.img  ($(stat -f%z "$OUT_DIR/dtbo.img") bytes)"
fi

# ── header dump (debug) ──────────────────────────────────────────────────────
if command -v hexdump &>/dev/null; then
    echo "==> First 512 bytes of boot header"
    hexdump -C -n 512 "$BOOT_IMG" | sed 's/^/   /' | head -16
fi

echo
echo "Done. Copy the two prebuilts into your TWRP device tree's prebuilt/ dir,"
echo "or just run the build — BoardConfig.mk auto-falls back to kernel source"
echo "if prebuilt/Image doesn't exist."
