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

# ── extract recovery_dtbo from second slot ───────────────────────────────────
# Header v2 packs DTBO into the "second" slot (no dedicated field). Detect
# DTBO magic 0xd7b7ab1e and trim to the embedded total_size.
SECOND_FILE="$(ls "$WORK_DIR"/*-second 2>/dev/null || true)"
if [[ -n "$SECOND_FILE" && -s "$SECOND_FILE" ]]; then
    # Check for DTBO magic (big-endian: 1e ab b7 d7 → hex 1eabb7d7)
    if xxd -p -l 1024 "$SECOND_FILE" | tr -d '\n' | grep -q '1eabb7d7'; then
        # Find DTBO magic offset and extract exact size
        DTBO_OFFSET=$(xxd -p "$SECOND_FILE" | tr -d '\n' | grep -ob '1eabb7d7' | head -1 | cut -d: -f1)
        # Each hex char = 4 bits, so DTBO_OFFSET is in hex chars; /2 = bytes
        DTBO_OFFSET=$(( DTBO_OFFSET / 2 ))
        # total_size is big-endian uint32 at offset+4
        DTBO_SIZE_HEX=$(xxd -s $((DTBO_OFFSET + 4)) -l 4 -p "$SECOND_FILE")
        DTBO_SIZE=$(( 16#$DTBO_SIZE_HEX ))
        dd if="$SECOND_FILE" of="$OUT_DIR/recovery_dtbo" bs=1 skip=$DTBO_OFFSET count=$DTBO_SIZE 2>/dev/null
        echo "==> recovery_dtbo: $OUT_DIR/recovery_dtbo  ($DTBO_SIZE bytes @ offset $DTBO_OFFSET)"
    else
        cp "$SECOND_FILE" "$OUT_DIR/second.img"
        echo "==> Second:        $OUT_DIR/second.img  ($(stat -f%z "$OUT_DIR/second.img") bytes, no DTBO magic)"
    fi
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
