# 00 — Agent protocol (read first)

This document turns the rest of the repo into a safe procedure for an AI agent operating
`adb`/`fastboot` on someone else's device. It assumes you have shell access to a Linux PC
with the device plugged in.

---

## 0.1 The three modes of a device (never mix them up)

| Mode | Detected by | What works | What does NOT work |
|---|---|---|---|
| **Android / adb** | `adb devices` → `device` | `adb shell`, `adb root`, image pull, packages | partition flashing |
| **Bootloader fastboot** | `fastboot getvar is-userspace` → `no` | physical partitions: `boot`, `init_boot`, `vbmeta*`, `misc`, `para`, erase | logical partitions (`system`, `vendor`, `product`) |
| **Fastbootd (userspace)** | `fastboot getvar is-userspace` → `yes` | logical partitions inside `super`, `format`, `resize-logical-partition` | most physical partitions (`No such file or directory`) |
| **Recovery** | `adb devices` → `recovery` | `adb reboot fastboot` (usually) | adb shell/root on many OEMs |

Always print `is-userspace` before a flash command and state which mode you are in.

---

## 0.2 Capability discovery (do this every time, never assume)

```bash
# Identity
adb shell getprop ro.product.device
adb shell getprop ro.product.board
adb shell getprop ro.board.platform
adb shell getprop ro.build.version.sdk
adb shell getprop ro.vendor.build.version.sdk     # ← the ceiling for GSI version
adb shell getprop ro.treble.enabled
adb shell getprop ro.product.cpu.abilist
adb shell getprop ro.boot.dynamic_partitions
adb shell getprop ro.build.ab_update

# Slots
adb shell bootctl get-current-slot
adb shell getprop ro.boot.slot_suffix
adb shell 'bootctl is-slot-bootable 0; bootctl is-slot-bootable 1'

# Partitions that exist (do not guess)
adb shell 'ls /dev/block/by-name/'
adb shell 'ls /dev/block/mapper/ 2>/dev/null'

# Free space in super (for a bigger injected system image)
adb shell 'blockdev --getsize64 /dev/block/by-name/super'   # A/B with super
adb shell 'lpdump 2>/dev/null | head -50'                    # logical layout
```

Decision table:

| Observation | Consequence |
|---|---|
| `ro.vendor.build.version.sdk = 35` (Android 15) | Android 15 GSI max; 16 will usually bootloop |
| `ro.product.cpu.abilist` contains `arm64-v8a` | use `arm64` GSI (`arm64-ab` if A/B) |
| `ro.build.ab_update = true` + `super` exists | flash `system_<slot>`, not `system` |
| no `init_boot` partition | Magisk patches `boot` instead |
| `slot-unbootable:a = yes` and slot A empty | the device has **no** second copy; one mistake = brick |
| `super` is 9 GB, system uses 2.2 GB | ~4 GB headroom for GApps injection |

---

## 0.3 Gate model

Every phase has an entry gate and an exit gate. Do not skip, do not "continue anyway".

```
P1 unlock     exit: getvar unlocked == yes, secure == no
P3 flash      exit: fastboot prints OKAY for system, metadata, userdata
P4 vbmeta     exit: OKAY in bootloader mode for every vbmeta_*_b
P5 slot       exit: getvar current-slot == target, slot-unbootable == no,
                    slot-retry-count >= 1
P6 boot       exit: sys.boot_completed == 1 AND ro.build.display.id is the GSI
P6b slot mark exit: bootctl is-slot-marked-successful <slot> == 1
P7 image edit exit: offline `debugfs ls` shows files AND `ea_list` shows labels
P8 look       exit: home activity + gestural overlay enabled
P9 root       exit: magiskd running, module dir readable, reboot survives
```

If an exit gate fails: stop, open `docs/12-rescue.md`, and talk to the user. Never
compensate by changing a different variable.

---

## 0.4 Irreversibility ledger

Before each action, fill one line. If you cannot fill the rollback column, do not act.

| Action | Data lost | Rollback |
|---|---|---|
| `oem unlock` | everything | none (by design) |
| `flash system_<slot>` | stock system (if no firmware) | re-flash stock image **only if you have it** |
| `format:f2fs userdata` | internal storage | none |
| `erase metadata` | /metadata (device encryption state) | re-created on boot |
| `flash vbmeta` | AVB state | re-flash stock vbmeta backup |
| `flash init_boot` (Magisk) | nothing (8 MB boot image) | re-flash `init_boot_<slot>_stock.img` |
| GApps/font injection | nothing (offline .img) | keep the pre-edit `.img` copy |
| module install | nothing | delete `/data/adb/modules/<id>`, reboot |

**Back up before writing**: `dd if=/dev/block/by-name/<part>` over `adb exec-out` works for
`boot`, `init_boot`, `vbmeta*` when `adb root` is available. Verify the hash.

---

## 0.5 Style rules for agents

1. One destructive command per turn, followed by verification.
2. Show the user the exact command before running it when it writes to the device.
3. Prefer offline image editing (host `debugfs`) over on-device hacks — it is reproducible
   and survives factory reset.
4. Never enable `permissive` SELinux as a "fix". Fix labels instead (`docs/07`).
5. Never install an app as a device-owner/admin unless the user asked for MDM.
6. Keep `session-log.md`: timestamp, command, output summary. The next agent will need it.
7. If the device is already modified (GSI, root, modules), **do not assume stock** — inventory
   first. Some devices have empty slot A (no rescue copy).
8. When the user says "make it look like OneUI", split the promise: launcher/icon/font/QS =
   possible; Samsung Settings/apps/AOD/Knox = not possible (`docs/11`).
9. Timebox downloads: use the parallel-range downloader in `docs/05` if a single stream is
   under ~200 KB/s.
10. Everything you learn that contradicts this repo → open a PR/issue with the device model
    and the exact output.

---

## 0.6 Minimal happy-path command list (A/B, Android 15 vendor, arm64)

```bash
# 0. environment
export ADB=$PWD/platform-tools/adb FB=$PWD/platform-tools/fastboot

# 1. inventory (must be adb device)
bash scripts/inventory.sh > inventory.txt

# 2. unlock (wipes)
$FB oem unlock            # or: $FB flashing unlock
$FB getvar unlocked       # yes

# 3. flash system in fastbootd
$FB reboot fastboot
$FB getvar is-userspace   # yes
$FB flash system_b td_a15_arm64-ab-vanilla.img
$FB erase metadata
$FB format:f2fs userdata

# 4. vbmeta in bootloader
$FB reboot bootloader
$FB flash vbmeta_b        vbmeta_empty.img
$FB flash vbmeta_system_b vbmeta_empty.img
$FB flash vbmeta_vendor_b vbmeta_empty.img
$FB erase misc
$FB erase para
$FB --set-active=b
$FB reboot bootloader
$FB getvar current-slot   # b

# 5. boot + verify
$FB reboot
$ADB wait-for-device
$ADB shell getprop sys.boot_completed       # 1
$ADB shell bootctl mark-boot-successful
```

Then, if Google apps are wanted, go back to `docs/06` and `docs/07`, rebuild the image, and
repeat steps 3–5 (no data wipe needed if the system image only changes — `metadata`/`userdata`
stay intact).

---

## 0.7 When the user's device differs

| Difference | Adapt |
|---|---|
| A-only device | flash `system`, no slot suffix, no `--set-active` |
| No `super` / non-dynamic | `fastboot flash system system.img` in bootloader mode may be possible; check `max-download-size` |
| `boot` contains ramdisk (Android ≤12) | Magisk patches `boot`; wiping `init_boot` not applicable |
| 32-bit only | `arm` / `a32` GSI |
| Vendor is Android 11 | use Android 11/12 GSI, not 15 |
| Samsung / Xiaomi / OnePlus | extra steps (Odin / Mi Unlock / `fastboot flashing unlock_critical`); this playbook's commands still apply after unlock |
| GSI boots but no touch/display | wrong GSI arch or missing VNDK; try `vndklite` or another release |
