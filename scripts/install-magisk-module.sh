#!/usr/bin/env bash
# Install a Magisk module over adb, including the /data/adb/magisk bootstrap that most
# guides omit. Requires root (run `adb root` first on userdebug GSIs).
#
#   bash scripts/install-magisk-module.sh --zip Vector.zip
#
# The binaries are expected in /data/local/tmp/mp (patch-init-boot.sh stages them).
set -uo pipefail

ADB=${ADB:-adb}
ZIP=""
while [ $# -gt 0 ]; do
  case "$1" in
    --zip) ZIP=${2:?}; shift 2;;
    -h|--help) sed -n '2,9p' "$0"; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[ -f "$ZIP" ] || { echo "--zip required" >&2; exit 2; }

SRC=/data/local/tmp/mp
DST=/data/adb/magisk

echo "== root check"
"$ADB" shell 'su -c id' 2>/dev/null | grep -q 'uid=0' || {
  echo "no root shell. Run 'adb root' (userdebug GSI) or use the ROM's su." >&2; exit 3; }

echo "== checking staged binaries"
for f in magisk magiskboot magiskinit magiskpolicy busybox init-ld util_functions.sh; do
  "$ADB" shell "[ -f $SRC/$f ]" || { echo "missing $SRC/$f — run scripts/patch-init-boot.sh first" >&2; exit 4; }
done

echo "== bootstrapping $DST"
"$ADB" shell "su -c '
  mkdir -p $DST
  cp -f $SRC/magisk $SRC/magiskboot $SRC/magiskinit $SRC/magiskpolicy \
        $SRC/busybox $SRC/init-ld $SRC/util_functions.sh $DST/
  [ -f $SRC/module_installer.sh ] && cp -f $SRC/module_installer.sh $DST/
  chmod 755 $DST/*
  chown 0:0 $DST/*
  # critical: init will refuse to exec these if they carry the wrong SELinux label
  chcon -R u:object_r:magisk_file:s0 $DST
  chcon u:object_r:magisk_file:s0 /debug_ramdisk/magisk \
        /debug_ramdisk/magiskpolicy /debug_ramdisk/magiskinit 2>/dev/null
  ls -Z $DST | head -3
'" 2>&1 | tail -5

echo "== pushing module"
"$ADB" push "$ZIP" /data/local/tmp/module.zip >/dev/null
echo "== installing"
"$ADB" shell "su -c '$DST/magisk --install-module /data/local/tmp/module.zip'" 2>&1 | tail -25

echo
echo "== installed modules"
"$ADB" shell 'su -c "ls /data/adb/modules"' 2>&1
echo
echo "Reboot, then confirm Magisk boot stages actually ran:"
echo "  adb logcat -d -b all | grep -E 'post-fs-data mode|late_start|boot-complete'"
echo "If those lines are missing, read docs/10.7 (phh-su conflict)."
