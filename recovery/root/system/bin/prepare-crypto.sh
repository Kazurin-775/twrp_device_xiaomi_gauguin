#!/system/bin/sh

# Sets crypto-critical properties from the ROM's build.props, then signals the
# crypto chain (crypto.ready=1 -> init starts keymaster-4-0). Modeled on
# /odm/bin/prepdecrypt.sh from the reference tree.
#
# Synchronization with TWRP: the super mapper devices appear during
# Setup_Fstab_Partitions, and Decrypt_Data() then blocks in getService()
# for keymaster for up to 25 s. Finishing within that window means keymaster
# registers mid-wait with correct patchlevels already cached, and the single
# automatic metadata decrypt attempt succeeds.
#
# The two ro. patch props already exist in the ramdisk prop.default, and init
# rejects re-setting an existing ro. prop via setprop ("Read-only property
# was already set"), so resetprop is required for them.

TMP_MNT=/tmp/prepare-crypto
SYSTEM_DEV=/dev/block/mapper/system
VENDOR_DEV=/dev/block/mapper/vendor
RESETPROP=/system/bin/resetprop
[ -e "$RESETPROP" ] || RESETPROP=/sbin/resetprop

log_msg() {
    log -t prepare-crypto "$1"
}

i=0
while [ ! -e "$SYSTEM_DEV" ] || [ ! -e "$VENDOR_DEV" ]; do
    if [ $i -ge 60 ]; then
        log_msg "Mapper devices never appeared"
        setprop crypto.ready 1  # fail soft: keep the chain observable in logs
        exit 1
    fi
    sleep 0.5
    i=$((i + 1))
done

mkdir -p "$TMP_MNT/system" "$TMP_MNT/vendor"
if ! mount -o ro "$SYSTEM_DEV" "$TMP_MNT/system" || \
   ! mount -o ro "$VENDOR_DEV" "$TMP_MNT/vendor"; then
    log_msg "Temporary mounts of /system and /vendor failed"
    umount "$TMP_MNT/system"
    umount "$TMP_MNT/vendor"
    setprop crypto.ready 1
    exit 1
fi

# SAR layout: system build.prop lives under <mount>/system; vendor may be
# either flat or nested depending on image generation.
[ -f "$TMP_MNT/system/system/build.prop" ] && SYSTEM_PROP_FILE="$TMP_MNT/system/system/build.prop" \
    || SYSTEM_PROP_FILE="$TMP_MNT/system/build.prop"
[ -f "$TMP_MNT/vendor/system/build.prop" ] && VENDOR_PROP_FILE="$TMP_MNT/vendor/system/build.prop" \
    || VENDOR_PROP_FILE="$TMP_MNT/vendor/build.prop"

BUILD_PATCH=$(grep -E '^ro\.build\.version\.security_patch=' "$SYSTEM_PROP_FILE" | cut -d= -f2)
VENDOR_PATCH=$(grep -E '^ro\.vendor\.build\.security_patch=' "$VENDOR_PROP_FILE" | cut -d= -f2)
# ro.build.version.release feeds keymaster's OS_VERSION binding input. The
# ramdisk default (e.g. 99.87.36) parses higher than any real ROM release and
# makes the TA demand an upgrade of every key blob (Begin -> KEY_REQUIRES_UPGRADE).
RELEASE=$(grep -E '^ro\.build\.version\.release=' "$SYSTEM_PROP_FILE" | cut -d= -f2)
umount "$TMP_MNT/system"
umount "$TMP_MNT/vendor"
rmdir "$TMP_MNT/system" "$TMP_MNT/vendor" "$TMP_MNT"

# setprop cannot change these (already exist as ro. props); resetprop can.
[ -n "$BUILD_PATCH" ] && "$RESETPROP" ro.build.version.security_patch "$BUILD_PATCH"
[ -n "$VENDOR_PATCH" ] && "$RESETPROP" ro.vendor.build.security_patch "$VENDOR_PATCH"
[ -n "$RELEASE" ] && "$RESETPROP" ro.build.version.release "$RELEASE"

# Keep the ramdisk prop.default in sync for anything that re-reads it.
if [ -f /prop.default ]; then
    [ -n "$BUILD_PATCH" ] && sed -i "s/ro.build.version.security_patch=.*/ro.build.version.security_patch=$BUILD_PATCH/g" /prop.default
    [ -n "$VENDOR_PATCH" ] && sed -i "s/ro.vendor.build.security_patch=.*/ro.vendor.build.security_patch=$VENDOR_PATCH/g" /prop.default
    [ -n "$RELEASE" ] && sed -i "s/ro.build.version.release=.*/ro.build.version.release=$RELEASE/g" /prop.default
fi

log_msg "Set system=$BUILD_PATCH vendor=$VENDOR_PATCH release=$RELEASE; set crypto.ready=1"
setprop crypto.ready 1
