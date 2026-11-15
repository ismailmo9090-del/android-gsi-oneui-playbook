#!/usr/bin/env bash
# Flash a GSI system image with the correct mode/slot/vbmeta order.
#
#   CONFIRM=1 bash scripts/flash-gsi.sh --img gsi.img --slot b \
#       --vbmeta vbmeta_empty.img [--wipe] [--skip-vbmeta]
#
# --wipe         erase metadata + format:f2fs userdata (required on first flash)
# --skip-vbmeta  keep the existing vbmeta (only when you know it is already empty)
#
# Without CONFIRM=1 it only prints the plan.
set -uo pipefail

FB=${FB:-fastboot}
IMG=""; SLOT=""; VBMETA=""; WIPE=0; SKIP_VBMETA=0

while [ $# -gt 0 ]; do
  case "$1" in
    --img) IMG=${2:?}; shift 2;;
    --slot) SLOT=${2:?}; shift 2;;
    --vbmeta) VBMETA=${2:?}; shift 2;;
    --wipe) WIPE=1; shift;;
    --skip-vbmeta) SKIP_VBMETA=1; shift;;
    -h|--help) sed -n '2,12p' "$0"; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

[ -n "$IMG" ]  || { echo "--img required" >&2; exit 2; }
[ -f "$IMG" ]  || { echo "image not found: $IMG" >&2; exit 2; }
[ "$SKIP_VBMETA" = 0 ] && [ -z "$VBMETA" ] && { echo "--vbmeta required (or --skip-vbmeta)" >&2; exit 2; }
[ "$SKIP_VBMETA" = 1 ] || [ -f "$VBMETA" ] || { echo "vbmeta not found: $VBMETA" >&2; exit 2; }

if [ -z "$SLOT" ]; then
  SLOT=$("$FB" getvar current-slot 2>&1 | head -1 | sed 's/.*: //' | tr -d ' \r')
fi
[ -n "$SLOT" ] || { echo "cannot determine slot; pass --slot a|b" >&2; exit 2; }

SYS="system"; [ -n "$SLOT" ] && SYS="system_$SLOT"
VB="vbmeta"; VBS="vbmeta_system"; VBV="vbmeta_vendor"
[ -n "$SLOT" ] && { VB="vbmeta_$SLOT"; VBS="vbmeta_system_$SLOT"; VBV="vbmeta_vendor_$SLOT"; }

echo "plan:"
echo "  image       : $IMG ($(stat -c%s "$IMG") bytes)"
echo "  slot        : ${SLOT:-<a-only>}   partition: $SYS"
echo "  vbmeta      : $([ "$SKIP_VBMETA" = 1 ] && echo kept || echo "$VBMETA")"
echo "  wipe data   : $([ "$WIPE" = 1 ] && echo YES || echo no)"
echo "  sha256      : $(sha256sum "$IMG" | cut -d' ' -f1)"

if [ "${CONFIRM:-}" != "1" ]; then
  echo
  echo "Dry run. Re-run with CONFIRM=1 to execute."
  exit 1
fi

set -e
echo "== entering fastbootd"
"$FB" reboot fastboot
"$FB" getvar is-userspace 2>&1 | head -1 | grep -qi 'yes' || {
  echo "not in fastbootd — abort"; exit 3; }

echo "== flashing $SYS"
"$FB" flash "$SYS" "$IMG"

if [ "$WIPE" = 1 ]; then
  echo "== wiping"
  "$FB" erase metadata
  "$FB" format:f2fs userdata
fi

if [ "$SKIP_VBMETA" = 0 ]; then
  echo "== bootloader for vbmeta"
  "$FB" reboot bootloader
  for p in "$VB" "$VBS" "$VBV"; do
    # Devices without vbmeta_vendor simply fail this line; that is expected.
    "$FB" flash "$p" "$VBMETA" || echo "  warn: $p not flashed (partition may not exist)"
  done
else
  echo "== bootloader for slot repair"
  "$FB" reboot bootloader
fi

echo "== slot repair"
"$FB" erase misc  || true
"$FB" erase para  || true
"$FB" --set-active="$SLOT"
"$FB" reboot bootloader
"$FB" getvar current-slot 2>&1 | head -1

echo "== reboot"
"$FB" reboot
echo
echo "Now verify:  adb wait-for-device && adb shell getprop sys.boot_completed"
