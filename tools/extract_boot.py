#!/usr/bin/env python3
"""
extract_boot.py — Parse an Android boot.img and extract kernel Image + dtb.img.

Handles AOSP headers v1/v1.2/v2/v3/v4 AND Qualcomm-custom layouts (like the
one found on Xiaomi Gauguin where page_size + header_version live at non-AOSP
offsets). Pure-Python; no AOSP tools required.
"""
import argparse, os, struct

BOOT_MAGIC = b"ANDROID!"

def parse_aosp(data):
    """Standard AOSP boot_img_hdr — tries all known variants."""
    hdr = {}
    hdr["magic"]        = data[0:8]
    hdr["kernel_size"]  = struct.unpack("<I", data[8:12])[0]
    hdr["ramdisk_size"] = struct.unpack("<I", data[12:16])[0]
    hdr["second_size"]  = struct.unpack("<I", data[16:20])[0]
    hdr["page_size"]    = struct.unpack("<I", data[52:56])[0]
    hdr["header_version"] = struct.unpack("<I", data[68:72])[0]
    hdr["os_version"]   = struct.unpack("<I", data[56:60])[0]
    hdr["board"]        = data[36:52].split(b"\x00",1)[0].decode(errors="ignore")
    hdr["header_size"]  = 1580

    # v2 DTB extension
    if hdr["header_version"] >= 2 and len(data) >= 1580:
        hdr["dtb_size"]   = struct.unpack("<I", data[1524:1528])[0]
        hdr["dtb_offset"] = struct.unpack("<Q", data[1528:1536])[0]
    else:
        hdr["dtb_size"] = hdr["dtb_offset"] = 0
    return hdr

def parse_qcom_custom(data):
    """Qualcomm custom layout — page_size at offset 0x24, header_version at 0x28.
    Header is one page (page_size=4096) and is NOT 1580 bytes."""
    hdr = {}
    hdr["magic"]        = data[0:8]
    hdr["kernel_size"]  = struct.unpack("<I", data[8:12])[0]
    hdr["ramdisk_size"] = struct.unpack("<I", data[12:16])[0]
    hdr["second_size"]  = struct.unpack("<I", data[16:20])[0]
    hdr["page_size"]    = struct.unpack("<I", data[36:40])[0]    # 0x24
    hdr["header_version"] = struct.unpack("<I", data[40:44])[0]  # 0x28
    hdr["os_version"]   = struct.unpack("<I", data[44:48])[0]
    hdr["board"]        = ""  # no board field in this layout, or it's zeroed
    # Header occupies exactly 1 page; kernel starts at offset page_size
    hdr["header_size"]  = hdr["page_size"]
    hdr["dtb_size"]     = 0  # custom layout never embeds DTB
    hdr["dtb_offset"]   = 0
    return hdr

def detect_format(data):
    """Heuristic: pick parser based on whether AOSP header_version is valid
    AND page_size + header_version make sense."""
    # Try AOSP first
    aosp_page = struct.unpack("<I", data[52:56])[0]
    aosp_hv   = struct.unpack("<I", data[68:72])[0]
    aosp_ok = (aosp_page in (2048, 4096, 8192, 16384) and aosp_hv <= 4)

    # Try QCOM custom
    qcom_page = struct.unpack("<I", data[36:40])[0]
    qcom_hv   = struct.unpack("<I", data[40:44])[0]
    qcom_ok = (qcom_page in (256, 2048, 4096, 8192, 16384) and qcom_hv in (1, 2))

    if aosp_ok and not qcom_ok:
        return "aosp"
    elif qcom_ok and not aosp_ok:
        return "qcom"
    elif aosp_ok and qcom_ok:
        # Both plausible — pick AOSP (standard)
        return "aosp"
    else:
        # Neither looks good: QCOM custom is safer fallback for Qualcomm devices
        return "qcom"

def align_up(n, page):
    return ((n + page - 1) // page) * page

def extract(img_path, out_dir):
    data = open(img_path, "rb").read()
    if data[:8] != BOOT_MAGIC:
        raise ValueError(f"Not an Android boot image (magic={data[:8]!r})")

    fmt = detect_format(data)
    if fmt == "aosp":
        hdr = parse_aosp(data)
    else:
        hdr = parse_qcom_custom(data)

    page = hdr["page_size"]

    print(f"==> {os.path.basename(img_path)}  (format={fmt})")
    print(f"    header_version = {hdr['header_version']}")
    print(f"    header_size    = {hdr['header_size']}")
    print(f"    page_size      = {page}")
    print(f"    kernel_size    = {hdr['kernel_size']}")
    print(f"    ramdisk_size   = {hdr['ramdisk_size']}")
    print(f"    second_size    = {hdr['second_size']}")
    print(f"    dtb_size       = {hdr['dtb_size']}")

    out_dir = os.path.abspath(out_dir)
    os.makedirs(out_dir, exist_ok=True)

    # Kernel: right after header, page-aligned
    kernel_off = align_up(hdr["header_size"], page)
    ks = hdr["kernel_size"]
    if ks and kernel_off + ks <= len(data):
        blob = data[kernel_off:kernel_off + ks]
        p = os.path.join(out_dir, "Image")
        open(p, "wb").write(blob)
        arm64 = b"ARMd"
        mag_off = blob.find(arm64)
        mag_str = f"  [ARM64 @ 0x{mag_off:x}]" if mag_off >= 0 else "  [magic not found]"
        print(f"==> Kernel: {p} ({len(blob)} bytes @ 0x{kernel_off:x}){mag_str}")
    else:
        print(f"!!! Kernel OOR (off=0x{kernel_off:x} sz={ks})")

    # DTB from embedded section (AOSP v2+ or v4)
    if hdr["dtb_size"] and hdr["dtb_offset"]:
        blob = data[hdr["dtb_offset"]:hdr["dtb_offset"] + hdr["dtb_size"]]
        p = os.path.join(out_dir, "dtb.img")
        open(p, "wb").write(blob)
        print(f"==> DTB:    {p} ({len(blob)} bytes @ 0x{hdr['dtb_offset']:x})")
    else:
        print("    (no embedded dtb in boot — use separate dtbo partition)")

    # Second (usually ramdisk for v1, dtbo/dtb for v2+)
    if hdr["second_size"]:
        sec_off = align_up(kernel_off + hdr["kernel_size"] + hdr["ramdisk_size"], page)
        blob = data[sec_off:sec_off + hdr["second_size"]]
        if blob:
            p = os.path.join(out_dir, "second.img")
            open(p, "wb").write(blob)
            print(f"==> Second: {p} ({len(blob)} bytes @ 0x{sec_off:x}, first 8: {blob[:8].hex()})")

def main():
    ap = argparse.ArgumentParser(description="Extract kernel + dtb from Android boot.img")
    ap.add_argument("boot_img")
    ap.add_argument("--out", "-o", default=None)
    args = ap.parse_args()
    out = args.out or os.path.join(os.path.dirname(os.path.abspath(args.boot_img)), "prebuilt")
    extract(args.boot_img, out)

if __name__ == "__main__":
    main()
