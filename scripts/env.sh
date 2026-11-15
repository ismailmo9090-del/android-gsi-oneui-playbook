#!/usr/bin/env bash
# shellcheck shell=bash
# Source this file:   . scripts/env.sh
#
# Sets ADB / FB / WORK for the current shell. Override any of them beforehand:
#   WORK=/mnt/ssd/gsi ADB=/opt/platform-tools/adb . scripts/env.sh

: "${WORK:=$HOME/gsi-work}"
export WORK

# Prefer platform-tools inside WORK, then PATH.
if [ -x "$WORK/platform-tools/adb" ]; then
  export ADB="${ADB:-$WORK/platform-tools/adb}"
  export FB="${FB:-$WORK/platform-tools/fastboot}"
else
  export ADB="${ADB:-adb}"
  export FB="${FB:-fastboot}"
fi

mkdir -p "$WORK"

_ok()   { printf '  ok   %s\n' "$*"; }
_warn() { printf '  warn %s\n' "$*"; }
_miss() { printf '  miss %s\n' "$*"; }

printf 'WORK=%s\nADB=%s\nFB=%s\n' "$WORK" "$ADB" "$FB"
command -v "$ADB" >/dev/null 2>&1 && _ok "adb"   || _miss "adb"
command -v "$FB"  >/dev/null 2>&1 && _ok "fastboot" || _miss "fastboot"
command -v debugfs >/dev/null 2>&1 && _ok "debugfs" || _miss "debugfs (e2fsprogs)"
command -v python3 >/dev/null 2>&1 && _ok "python3" || _miss "python3"
command -v xz      >/dev/null 2>&1 && _ok "xz"      || _miss "xz"
[ -f "$WORK/avb/avbtool.py" ] && _ok "avbtool" || _warn "avbtool missing (git clone external/avb)"

free_mb=$(df -Pm "$WORK" 2>/dev/null | awk 'NR==2{print $4}')
[ -n "${free_mb:-}" ] && printf 'free space: %s MB (need >= 10240)\n' "$free_mb"
