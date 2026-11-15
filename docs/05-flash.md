# 05 — Flashing the GSI (the part with all the footguns)

Order matters. The two fastboot modes each refuse half the commands, `-w` does not reliably
format `/data`, and slot activation can print `OKAY` without changing anything.

---

## 5.1 The exact order

```text
1. bootloader mode : getvar is-userspace == no
2. fastboot reboot fastboot
3. fastbootd       : getvar is-userspace == yes
4. flash system_<slot> <gsi.img>            (~60–90 s)
5. erase metadata
6. format:f2fs userdata                     (space, not colon)
7. fastboot reboot bootloader
8. bootloader      : flash vbmeta_<slot>, vbmeta_system_<slot>, vbmeta_vendor_<slot>
9. erase misc ; erase para
10. --set-active=<slot> ; reboot bootloader ; verify current-slot
11. reboot ; wait ; verify boot_completed == 1
12. bootctl mark-boot-successful
```

Why this order:

- `system` is a **logical** partition inside `super` → only fastbootd can write it.
- `vbmeta*` are **physical** partitions → only bootloader fastboot can write them.
- `misc` / `para` hold the bootloader's slot/retry state; erasing resets a stuck slot.
- `userdata` must be a real filesystem (f2fs/ext4), otherwise init drops to recovery.

## 5.2 Empty vbmeta

```bash
python3 avb/avbtool.py make_vbmeta_image \
  --output vbmeta_empty.img --flags 3 --padding_size 4096
```

`--flags 3` = `HASHTREE_DISABLED | VERIFICATION_DISABLED`. Flash it over every vbmeta chain
the device has (`vbmeta`, `vbmeta_system`, `vbmeta_vendor`), otherwise verified boot rejects
the unsigned GSI.

## 5.3 Commands (A/B, slot B example)

```bash
FB=fastboot
SLOT=b

$FB reboot fastboot
$FB getvar is-userspace                 # yes

$FB flash system_$SLOT gsi.img
$FB erase metadata
$FB format:f2fs userdata

$FB reboot bootloader
$FB flash vbmeta_$SLOT        vbmeta_empty.img
$FB flash vbmeta_system_$SLOT vbmeta_empty.img
$FB flash vbmeta_vendor_$SLOT vbmeta_empty.img
$FB erase misc
$FB erase para
$FB --set-active=$SLOT

$FB reboot bootloader
$FB getvar current-slot                 # b
$FB getvar slot-unbootable:$SLOT        # no
$FB getvar slot-retry-count:$SLOT       # 5 or 7

$FB reboot
```

If the device has no `vbmeta_vendor` partition, skip that line. If `getvar` lists a
`vbmeta_system_a` but not `_b`, the layout is unusual — inventory first.

## 5.4 Verify the boot (never trust OKAY)

```bash
adb wait-for-device
adb shell getprop sys.boot_completed        # 1  (first boot 1–3 min)
adb shell getprop ro.build.display.id       # treble_* / GSI name
adb shell getprop ro.build.version.release  # 15
adb shell getprop ro.boot.verifiedbootstate # orange
adb root && adb shell id                    # uid=0(root) on userdebug GSIs
adb shell dumpsys device_policy | sed -n '1,15p'   # no device owner / MDM
```

If `adb devices` reports **recovery**, the GSI did not boot → `docs/12-rescue.md`.

## 5.5 Mark the slot successful (mandatory)

```bash
adb shell 'bootctl get-current-slot
           bootctl is-slot-marked-successful 1
           bootctl is-slot-bootable 1
           bootctl mark-boot-successful'
```

Expected `1 / 1 / 1`. Then **reboot once more** and confirm `sys.boot_completed = 1`.
Without this, the retry counter decrements on every boot and the device eventually becomes
unbootable — a slow-motion brick that looks like "it used to work".

> Some ROMs mark the slot automatically in `phh-on-boot.sh`. Verify anyway.

## 5.6 Pitfalls table

| Symptom | Cause | Fix |
|---|---|---|
| `FAILED (remote: 'No such file or directory')` on `system_*` | bootloader fastboot | `fastboot reboot fastboot` |
| `data too large` / `max-download-size` | same | fastbootd |
| `Writing 'vbmeta_b' FAILED` | fastbootd | `fastboot reboot bootloader` |
| `fastboot -w` → `File system type raw not supported` | fastbootd can't infer fs | `fastboot format:f2fs userdata` |
| `format:f2fs:userdata` → `usage: expected argument` | wrong syntax | `format:f2fs userdata` |
| boots to **recovery** | incompatible GSI or unformatted data | format data, then switch GSI (`docs/04`) |
| on/off loop, USB `0e8d:2000` blips | both slots unbootable / retry 0 | Vol Down+Power → fastboot → slot repair |
| `--set-active=b` OKAY but `current-slot: a` | target slot unbootable | erase `misc`/`para`, set-active, reboot bootloader |
| nothing boots, slot A selected | slot A physically empty | only slot B can boot; go back to B |
| `adb shell` in recovery aborts (`shell_service.cpp:380`) | broken recovery adbd context | don't debug from recovery; `adb reboot fastboot` |

## 5.7 Re-flashing only `system` later (fonts/GApps)

If you only changed the system image, you do **not** need to wipe data:

```bash
$FB reboot fastboot
$FB flash system_$SLOT new_system.img
$FB reboot bootloader
$FB --set-active=$SLOT
$FB reboot
```

Data (including the Google account and launcher layout) survives. Do not erase `metadata`
or format `userdata` in this case.

## 5.8 Download helper

`scripts/download-gsi.sh` implements 12 parallel range requests with resume, then verifies
size. Use it when a single stream is slow; it is a plain bash script, no dependencies beyond
`curl`.
