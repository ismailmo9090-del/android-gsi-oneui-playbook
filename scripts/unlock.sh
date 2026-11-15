#!/usr/bin/env bash
# Bootloader unlock. THIS WIPES THE DEVICE.
#
#   CONFIRM=1 bash scripts/unlock.sh
#
# Tries the standard command first, then the MediaTek/vendor variant.
set -uo pipefail

FB=${FB:-fastboot}

if [ "${CONFIRM:-}" != "1" ]; then
  cat >&2 <<'EOF'
Refusing to unlock without confirmation.

Unlocking erases ALL user data, may void warranty, and cannot be undone
(the device stays unlocked until relocked, and relocking with a GSI is dangerous).

If the user has explicitly accepted this, run:
    CONFIRM=1 bash scripts/unlock.sh
EOF
  exit 1
fi

"$FB" getvar is-userspace 2>&1 | head -1
"$FB" getvar unlocked 2>&1 | head -1

echo "== trying: fastboot flashing unlock"
if "$FB" flashing unlock 2>&1 | tee /tmp/.unlock1 | grep -qiE 'OKAY|already'; then
  echo "standard unlock accepted"
else
  echo "== falling back: fastboot oem unlock"
  "$FB" oem unlock 2>&1 | tee /tmp/.unlock2 || true
fi

echo "== state after unlock"
"$FB" getvar unlocked   2>&1 | head -1
"$FB" getvar secure     2>&1 | head -1
"$FB" getvar current-slot 2>&1 | head -1

echo
echo "If 'unlocked: yes' is not shown, the OEM requires its own unlock tool"
echo "(Mi Unlock, realme/OPPO deep testing, vendor code). Stop here."
