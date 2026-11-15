# AGENTS.md — operating manual for AI agents

You are about to modify boot firmware and wipe a user's device. Treat every step as
irreversible until proven otherwise.

**Read `docs/00-agent-protocol.md` completely before your first command.**
This file is the short contract; the protocol file is the full procedure.

---

## 0. Non-negotiables

| Rule | Reason |
|---|---|
| Never relock the bootloader while a GSI / custom image is installed | hard brick on many MTK/Qualcomm devices |
| Never write to `nvram`, `nvcfg`, `nvdata`, `proinfo`, `protect1/2`, `sec1`, `otp`, `preloader_*`, `lk_*`, `md1img` | IMEI, calibration, boot chain — unrecoverable |
| Never trust `OKAY` from fastboot as success | verify with `getvar` / `getprop` |
| Never flash logical partitions from bootloader fastboot | they do not exist there; use fastbootd (`is-userspace: yes`) |
| Never flash physical partitions (`vbmeta*`, `boot`, `init_boot`, `misc`, `para`) from fastbootd | `No such file or directory` |
| Never `fastboot -w` as the only wipe step | it often silently skips `userdata`; use `format:f2fs userdata` |
| Never start without a per-step rollback | users accept a 30-second rollback, not a brick |
| Never guess a partition name or slot | run `scripts/inventory.sh` first |
| Never run two destructive actions in one turn | one action → verify → next |

---

## 1. First 10 minutes

1. **Ask / confirm**: device model, current state (stock? GSI? bootloop?), whether OEM
   firmware is downloadable (this decides if a rollback exists), and that **data will be
   wiped**.
2. Run `scripts/inventory.sh` and read its output. You need:
   - `current-slot`, `slot-unbootable:*`, `slot-successful:*`, `unlocked`, `secure`
   - `is-userspace` (which fastboot mode you are in right now)
   - partition list (`by-name`), presence of `init_boot`, `super`, `vbmeta*`
   - `ro.product.cpu.abilist`, `ro.treble.enabled`, vendor SDK (`ro.vendor.build.version.sdk`)
   - `ro.boot.dynamic_partitions`, `ro.build.ab_update`
3. Decide the GSI **by vendor SDK**, not by "latest Android" (see `docs/04`).
4. Write the plan into `session-log.md` in the repo/user workspace: every irreversible step
   and its rollback. Show it to the user before touching anything.

---

## 2. Phase order (do not reorder)

```text
P0  inventory + rollback plan            (read-only)
P1  bootloader unlock                    (wipes data, irreversible-ish)
P2  download + verify GSI                (read-only)
P3  flash system + wipe metadata/userdata
P4  flash empty vbmeta (bootloader mode)
P5  slot fix + first boot
P6  mark slot successful + verify GMS/WebView
P7  offline customisation (GApps labels, fonts) — reflash system
P8  look & feel (launcher, icons, gestures)
P9  root (Magisk) — only if the user accepts the risk
```

Each phase ends with a **gate**: a command whose output must match an expectation. If it
does not match, stop and use `docs/12-rescue.md` — do not "try the next thing anyway".

---

## 3. Communication protocol

- If the user writes Hinglish/Hindi, answer in Hinglish. Keep technical terms in English.
- Give **one physical instruction per message** (e.g. "Power + Volume Down 10 s, then tell me
  `fastboot`"). Wait for confirmation.
- Before every wipe/flash, state: what will be erased, how long it takes, and the rollback.
- Report progress with the actual output, not "done".
- If a mode is wrong (bootloader vs fastbootd vs recovery vs adb), say which one you expect
  and how to reach it.

---

## 4. Golden commands

```bash
# who am I talking to?
fastboot devices ; adb devices

# which fastboot am I in?   no = bootloader, yes = fastbootd
fastboot getvar is-userspace

# state
fastboot getvar current-slot
fastboot getvar unlocked
fastboot getvar slot-unbootable:b
fastboot getvar slot-successful:b
fastboot getvar battery-voltage

# switch modes
fastboot reboot fastboot     # → fastbootd (logical partitions)
fastboot reboot bootloader   # → bootloader (physical partitions)
adb reboot fastboot          # from a booted/recovery device

# flash a logical system partition (fastbootd only)
fastboot flash system_b gsi.img

# wipe data so init can format (fastbootd only)
fastboot erase metadata
fastboot format:f2fs userdata      # SPACE between fs type and partition

# physical vbmeta (bootloader only)
fastboot flash vbmeta_b vbmeta_empty.img

# slot repair
fastboot erase misc
fastboot erase para
fastboot --set-active=b
fastboot reboot bootloader
fastboot getvar current-slot        # must be b

# verify boot
adb wait-for-device
adb shell getprop sys.boot_completed        # 1
adb shell getprop ro.build.version.release
adb shell bootctl mark-boot-successful
```

---

## 5. Stop conditions (abort and report)

- `fastboot devices` empty after 60 s, or device cycles `0e8d:2000` (preloader blips).
- `slot-retry-count` is 0 or `slot-unbootable` is `yes` for both slots.
- Battery below ~40 % (`battery-voltage` below ~3.7 V).
- `adb` shows `recovery` after a GSI flash → the image did not boot; go to `docs/12`.
- `getprop sys.boot_completed` still empty after 5 minutes on first boot.
- Any command that would touch a forbidden partition.
- The user has not explicitly accepted data loss for the current step.

---

## 6. What "success" looks like

```bash
adb shell getprop sys.boot_completed          # 1
adb shell getprop ro.build.display.id         # treble_* (not the OEM build)
adb shell bootctl is-slot-marked-successful 1 # 1
adb shell dumpsys device_policy | head -20    # no MDM device owner
adb shell cmd package resolve-activity --brief -a android.intent.action.MAIN \
        -c android.intent.category.HOME | tail -1   # launcher you installed
adb shell cmd overlay list | grep '\[x\].*navbar'   # gestural enabled
```

If root was requested, additionally `magiskd` must be running and `/data/adb/modules`
must be readable — but read `docs/10-root.md` first: **on PHH/TrebleDroid GSIs the
built-in `phh-su` conflicts with Magisk** and Magisk modules may not survive a reboot.

---

## 7. Reporting template

When you finish (or abort), report:

```text
Device:            <model / codename / SoC / slots>
Stock backup:      <yes with path+sha256 | none — irreversible>
GSI:               <name, version, sha256, size>
Flash result:      <slot, vbmeta, userdata>
Boot verification: <boot_completed, slot marked successful>
Google apps:       <GMS version, Play Store version, account status>
Customisation:     <font, launcher, icons, gestures>
Root:             <none | phh-su | Magisk version + module status>
Known issues:      <honest list>
Rollback:          <exact commands/files>
```
