#!/usr/bin/env bash
# Read-only device inventory. Safe to run in any mode.
#
#   bash scripts/inventory.sh            > inventory.txt
#   ADB=... FB=... bash scripts/inventory.sh
#
set -uo pipefail

ADB=${ADB:-adb}
FB=${FB:-fastboot}

hr() { printf '\n===== %s =====\n' "$*"; }
sh_() { "$ADB" shell "$@" 2>/dev/null | tr -d '\r'; }

if "$ADB" get-state >/dev/null 2>&1 && [ "$("$ADB" get-state 2>/dev/null)" = "device" ]; then
  hr "mode"
  echo "adb: device"
  "$ADB" shell getprop ro.build.characteristics 2>/dev/null | tr -d '\r'

  hr "identity"
  sh_ "getprop ro.product.manufacturer; getprop ro.product.model; getprop ro.product.device; getprop ro.product.board; getprop ro.board.platform; getprop ro.boot.hardware"
  hr "build"
  sh_ "getprop ro.build.display.id; getprop ro.build.version.release; getprop ro.build.version.sdk; getprop ro.vendor.build.version.sdk; getprop ro.vndk.version; getprop ro.treble.enabled"
  hr "abi"
  sh_ "getprop ro.product.cpu.abilist; getprop ro.product.cpu.abilist64; getprop ro.build.ab_update; getprop ro.boot.dynamic_partitions"
  hr "slots"
  sh_ "getprop ro.boot.slot_suffix; bootctl get-current-slot; bootctl is-slot-bootable 0; bootctl is-slot-bootable 1; bootctl is-slot-marked-successful 0; bootctl is-slot-marked-successful 1"
  hr "verified boot"
  sh_ "getprop ro.boot.verifiedbootstate; getprop ro.boot.flash.locked"
  hr "partitions (by-name)"
  sh_ "ls /dev/block/by-name/"
  hr "logical partitions"
  sh_ "ls /dev/block/mapper/"
  hr "sizes"
  sh_ 'for p in super boot_b init_boot_b userdata metadata; do printf "%-14s " "$p"; blockdev --getsize64 /dev/block/by-name/$p 2>/dev/null || echo n/a; done'
  hr "storage"
  sh_ "df -h /data /metadata 2>/dev/null"
  hr "modifications"
  sh_ "ls /data/adb/modules 2>/dev/null; which su; ls -l /system/xbin/su /debug_ramdisk/su 2>/dev/null"
  sh_ "pm list packages | grep -iE 'magisk|lawnchair|iconify|vector|lsposed'"
  sh_ "cmd overlay list | grep '\\[x\\]'"
  hr "webview"
  sh_ "dumpsys webviewupdate | grep -i -m3 'WebView package'"
  hr "device owner / MDM"
  sh_ "dumpsys device_policy | sed -n '1,20p'"

elif [ -n "$("$FB" devices 2>/dev/null)" ]; then
  hr "mode"
  echo "fastboot: $("$FB" devices | head -1)"
  hr "state"
  for v in is-userspace current-slot unlocked secure slot-unbootable:a slot-unbootable:b \
           slot-successful:a slot-successful:b slot-retry-count:a slot-retry-count:b \
           battery-voltage max-download-size product; do
    printf '%-24s ' "$v"
    "$FB" getvar "$v" 2>&1 | head -1 | sed 's/^[a-z-]*: //'
  done
else
  echo "No device in adb or fastboot." >&2
  echo "Check cable/port, then: fastboot devices   OR   adb devices" >&2
  exit 1
fi
