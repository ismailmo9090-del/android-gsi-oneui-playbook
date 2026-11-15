# 12 — Rescue: rollback and bootloop recovery

Every irreversible action in this playbook has a rollback here. Read it **before** you need it.

---

## 12.1 Decision tree

```
Does the device show up at all?
├─ adb device            → system boots. Fix software (WebView, launcher, root).
├─ adb recovery          → system failed.  → §12.3
├─ fastboot (0e8d:201c)  → bootloader.     → §12.2
├─ 0e8d:2000 blips only  → bootloop.       → §12.4
└─ nothing               → cable/port/battery. Try another cable/port. → §12.5
```

## 12.2 From fastboot (bootloader or fastbootd)

Check which mode and the slot state:

```bash
fastboot getvar is-userspace
fastboot getvar current-slot
fastboot getvar slot-unbootable:a ; fastboot getvar slot-unbootable:b
fastboot getvar slot-retry-count:a ; fastboot getvar slot-retry-count:b
```

**Stuck on the wrong slot / unbootable target:**

```bash
fastboot erase misc
fastboot erase para
fastboot --set-active=b
fastboot reboot bootloader
fastboot getvar current-slot        # b
fastboot getvar slot-unbootable:b   # no
fastboot getvar slot-retry-count:b  # 5 or 7
```

**Bad system image / recovery fallback:** re-flash the last known good `system`:

```bash
fastboot reboot fastboot
fastboot flash system_b good_system.img
fastboot reboot bootloader
fastboot --set-active=b
fastboot reboot
```

**Bootloop after Magisk:** restore the stock ramdisk (30 s, keeps data):

```bash
fastboot flash init_boot_b init_boot_b_stock.img
fastboot reboot
```

**Bad vbmeta:** re-flash stock `vbmeta_b`, `vbmeta_system_b`, `vbmeta_vendor_b` (from your
backup) or the empty vbmeta if the GSI is still installed.

## 12.3 From recovery

On many OEMs recovery `adb shell` aborts (`shell_service.cpp:380 Could not set SELinux
context`) and `adb root` is denied. But this works:

```bash
adb devices                 # recovery
adb reboot fastboot         # → fastbootd, no button presses
```

Then use §12.2. Do not try to debug from recovery — you will not get logs.

## 12.4 Bootloop (preloader blips only)

1. **Power off hard**: hold Power 15–20 s.
2. Enter bootloader: hold **Volume Down + Power** ~10 s until `fastboot mode`.
3. If it enters fastboot: §12.2 (erase `misc`/`para`, set-active, re-flash system).
4. If it never stops looping: keep holding the combo during boot; some MTK devices only
   expose fastboot for a fraction of a second.
5. Last resort: BROM/EDL. On the LT4901 test unit `mtkclient` **failed** (libusb config
   error) and no signed DA was available. Do not promise it.

## 12.5 Not detected at all

- Different cable (data, not charge-only), direct rear USB port, no hub.
- `dmesg -w` while plugging in: look for `0e8d:2000` (preloader) or nothing.
- Charge for 30 min — a very low battery can look like a dead device.
- Try another PC/OS (Windows needs the MTK/Google USB driver).
- If Windows: install Google USB driver + MTK preloader driver, disable driver signature
  enforcement if needed.

## 12.6 Restoring stock

Only possible if you have the OEM firmware. On devices like the LT4901 there is **no public
firmware** — flashing `system` destroyed the stock copy. The honest position:

> "There is no way back to the original ROM unless the manufacturer provides the firmware.
> The device is not bricked, but it is permanently a GSI device."

If you do have stock images:

```bash
fastboot reboot fastboot
fastboot flash system_b stock_system.img
fastboot reboot bootloader
fastboot flash vbmeta_b stock_vbmeta.img
fastboot --set-active=b
fastboot reboot
# only if the vendor requires it: fastboot format:f2fs userdata
```

Never flash `preloader`, `lk`, `nvram`, `nvdata`, `proinfo`, `protect1/2`, `sec1`, `otp`.

## 12.7 Pre-flight rollback checklist

Before any flash, confirm you can answer:

- [ ] exact file + sha256 of the image you are flashing
- [ ] exact command to restore the previous working image
- [ ] `init_boot_<slot>_stock.img` backed up (if rooting)
- [ ] `vbmeta_<slot>` backup (if changing AVB)
- [ ] bootloader reachable from a bootloop on this device (key combo tested)
- [ ] the user knows data loss status (wiped vs preserved)

If any box is unchecked, do not proceed.
