#!/usr/bin/env bash
# Headless Magisk boot-image patch: everything happens over adb, no Magisk app UI.
#
#   bash scripts/patch-init-boot.sh \
#       --apk Magisk.apk --boot init_boot_b_stock.img --out init_boot_b_magisk.img
#
# It does NOT flash anything. It prints the exact fastboot command at the end.
set -uo pipefail

ADB=${ADB:-adb}
APK=""; BOOT=""; OUT=""; SERIAL=""

while [ $# -gt 0 ]; do
  case "$1" in
    --apk) APK=${2:?}; shift 2;;
    --boot) BOOT=${2:?}; shift 2;;
    --out) OUT=${2:?}; shift 2;;
    --serial) SERIAL=${2:?}; shift 2;;
    -h|--help) sed -n '2,10p' "$0"; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

[ -f "$APK" ]  || { echo "--apk required (Magisk APK)" >&2; exit 2; }
[ -f "$BOOT" ] || { echo "--boot required (STOCK init_boot/boot image)" >&2; exit 2; }
OUT=${OUT:-${BOOT%.img}_magisk.img}

ABILIST=$("$ADB" shell getprop ro.product.cpu.abilist 2>/dev/null | tr -d '\r')
case "$ABILIST" in
  *arm64-v8a*) ABI_DIR=arm64-v8a;;
  *armeabi-v7a*) ABI_DIR=armeabi-v7a;;
  *) echo "unsupported ABI: '$ABILIST'" >&2; exit 3;;
esac
echo "device ABI: $ABILIST -> $ABI_DIR"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
unzip -q "$APK" 'assets/*' "lib/$ABI_DIR/*" -d "$TMP"
for f in assets/boot_patch.sh assets/util_functions.sh assets/module_installer.sh \
         "lib/$ABI_DIR/libmagiskboot.so" "lib/$ABI_DIR/libmagiskinit.so" \
         "lib/$ABI_DIR/libmagisk.so" "lib/$ABI_DIR/libinit-ld.so" \
         "lib/$ABI_DIR/libbusybox.so" "lib/$ABI_DIR/libmagiskpolicy.so"; do
  [ -f "$TMP/$f" ] || { echo "missing in APK: $f" >&2; exit 4; }
done

D=/data/local/tmp/mp
SH="$ADB"
[ -n "$SERIAL" ] && SH="$ADB -s $SERIAL"

echo "== staging on device ($D)"
$SH shell "rm -rf $D; mkdir -p $D"
$SH push "$TMP/assets/boot_patch.sh" "$TMP/assets/util_functions.sh" \
          "$TMP/assets/module_installer.sh" "$D/" >/dev/null
$SH push "$TMP/lib/$ABI_DIR/libmagiskboot.so"  "$D/magiskboot"  >/dev/null
$SH push "$TMP/lib/$ABI_DIR/libmagiskinit.so"  "$D/magiskinit"  >/dev/null
$SH push "$TMP/lib/$ABI_DIR/libmagisk.so"      "$D/magisk"      >/dev/null
$SH push "$TMP/lib/$ABI_DIR/libmagiskpolicy.so" "$D/magiskpolicy" >/dev/null
$SH push "$TMP/lib/$ABI_DIR/libinit-ld.so"     "$D/init-ld"     >/dev/null
$SH push "$TMP/lib/$ABI_DIR/libbusybox.so"     "$D/busybox"     >/dev/null
$SH push "$BOOT" "$D/stock.img" >/dev/null
$SH shell "chmod 755 $D/*"

echo "== patching (boot_patch.sh)"
$SH shell "cd $D && TMPDIR=$D MAGISKBIN=$D BOOTMODE=true sh boot_patch.sh stock.img" \
  | tail -30

$SH shell "ls -l $D/new-boot.img" || { echo "patch failed: no new-boot.img" >&2; exit 5; }
$SH pull "$D/new-boot.img" "$OUT" >/dev/null
echo
echo "patched image: $OUT ($(stat -c%s "$OUT") bytes)"
sha256sum "$OUT"
echo
echo "flash it (bootloader fastboot):"
echo "  fastboot flash init_boot_b $OUT     # use the slot-specific partition name"
echo "rollback:"
echo "  fastboot flash init_boot_b $BOOT"
