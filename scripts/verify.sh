#!/usr/bin/env bash
# Verification: offline image checks and/or live device checks.
#
#   bash scripts/verify.sh                  # device only
#   bash scripts/verify.sh --img td_a15_ui.img --expect-gapps --expect-font InterVariable.ttf
#
set -uo pipefail

ADB=${ADB:-adb}
IMG=""; EXPECT_GAPPS=0; EXPECT_FONT=""
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$*"; }
skip() { printf '  skip  %s\n' "$*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --img) IMG=${2:?}; shift 2;;
    --expect-gapps) EXPECT_GAPPS=1; shift;;
    --expect-font) EXPECT_FONT=${2:?}; shift 2;;
    -h|--help) sed -n '2,7p' "$0"; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

if [ -n "$IMG" ]; then
  echo "== image: $IMG"
  [ -f "$IMG" ] && ok "image exists ($(stat -c%s "$IMG") bytes)" || { bad "image missing"; exit 1; }
  sha256sum "$IMG" | sed 's/^/     sha256 /'

  # ext4 / sparse detection
  if file "$IMG" | grep -qi 'sparse'; then
    bad "sparse image — run simg2img before debugfs operations"
  elif file "$IMG" | grep -qi 'ext4'; then
    ok "raw ext4"
  else
    bad "not recognised as ext4: $(file -b "$IMG")"
  fi

  fb() { debugfs -R "$1" "$IMG" 2>/dev/null; }

  if [ "$EXPECT_GAPPS" = 1 ]; then
    for p in /system/product/priv-app/GmsCore/GmsCore.apk \
             /system/product/priv-app/Phonesky/Phonesky.apk \
             /system/system_ext/priv-app/GoogleServicesFramework/GoogleServicesFramework.apk \
             /system/product/etc/permissions; do
      fb "stat $p" | grep -q 'Inode:' && ok "present $p" || bad "missing $p"
    done
    if fb 'ea_list "/system/product/priv-app/Phonesky/Phonesky.apk"' | grep -q 'system_file'; then
      ok "Phonesky SELinux label"
    else
      bad "Phonesky has no system_file label (docs/07)"
    fi
    if fb 'ea_list "/system/product/lib64"' | grep -q 'system_lib_file'; then
      ok "lib64 SELinux label"
    else
      bad "lib64 not labelled system_lib_file"
    fi
  fi

  if [ -n "$EXPECT_FONT" ]; then
    fb "stat /system/fonts/$EXPECT_FONT" | grep -q 'Inode:' \
      && ok "font present: $EXPECT_FONT" || bad "font missing: $EXPECT_FONT"
    refs=$(debugfs -R "dump /system/etc/fonts.xml /tmp/fonts.verify.xml" "$IMG" >/dev/null 2>&1; \
           grep -c "$EXPECT_FONT" /tmp/fonts.verify.xml 2>/dev/null || echo 0)
    [ "${refs:-0}" -gt 0 ] && ok "fonts.xml references font ($refs)" \
                           || bad "fonts.xml does not reference $EXPECT_FONT"
  fi
fi

if "$ADB" get-state >/dev/null 2>&1; then
  echo "== device"
  g() { "$ADB" shell "$1" 2>/dev/null | tr -d '\r'; }

  [ "$(g 'getprop sys.boot_completed')" = "1" ] && ok "boot_completed=1" || bad "boot_completed != 1"
  disp=$(g 'getprop ro.build.display.id')
  case "$disp" in
    *treble*|*lineage*|*aosp*) ok "GSI build: $disp";;
    "") bad "no display id";;
    *) skip "build id looks OEM: $disp (expected only if you did not flash a GSI)";;
  esac

  cur=$(g 'bootctl get-current-slot')
  if [ -n "$cur" ]; then
    ok "current slot index: $cur"
    marked=$(g "bootctl is-slot-marked-successful $cur")
    [ "$marked" = "1" ] && ok "slot marked successful" || bad "slot not marked successful (docs/05.5)"
  else
    skip "bootctl unavailable (try 'adb root' first)"
  fi

  wv=$(g "dumpsys webviewupdate | grep -i -m1 'Current WebView package'")
  [ -n "$wv" ] && ok "webview: $wv" || skip "webview provider unknown"

  home=$(g 'cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME | tail -1')
  [ -n "$home" ] && ok "home: $home" || skip "home activity unknown"

  g "cmd overlay list | grep -q '\[x\].*navbar.gestural'" && ok "gestural nav enabled" \
                                                         || skip "gestural nav not enabled"

  if g "pm list packages | grep -q com.google.android.gms"; then
    ok "GMS installed"
    ok "GMS version: $(g 'dumpsys package com.google.android.gms | grep -m1 versionName')"
  else
    skip "GMS not installed (vanilla GSI)"
  fi

  n_unlabeled=$(g "logcat -d -b all 2>/dev/null | grep -c 'unlabeled'")
  [ "${n_unlabeled:-0}" -eq 0 ] && ok "no unlabeled AVC denials" \
                                || bad "$n_unlabeled unlabeled denials (docs/07)"

  if g 'ps -A | grep -q magiskd'; then
    ok "magiskd running"
    if g "logcat -d -b all | grep -q 'post-fs-data mode running'"; then
      ok "Magisk boot stages ran"
    else
      bad "Magisk boot stages did NOT run (docs/10.7)"
    fi
  else
    skip "Magisk not installed"
  fi
fi

echo
echo "summary: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
