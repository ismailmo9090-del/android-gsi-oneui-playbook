# Android GSI + OneUI Playbook

**A field-tested, AI-agent-friendly playbook for turning a locked-down Android tablet into a
clean GSI device — bootloader unlock → TrebleDroid GSI → Google apps → SELinux fixes →
custom font → iOS/OneUI-style launcher → optional root.**

Everything here was executed and verified on real hardware (Lava S91 / LT4901, MediaTek
MT8786, Android 15 vendor). Nothing is copied from a blog post: every step, including the
ones that failed, is documented with the exact commands and the reason it works.

> **Not a one-click tool.** It is a *decision-and-command reference* for a human or an AI
> agent driving `adb` / `fastboot` against a device. Read
> [`AGENTS.md`](AGENTS.md) if you are an agent.

---

## What this repo gives you

| Layer | What you get | Requires root? |
|---|---|---|
| Bootloader | Unlock quirks for MediaTek / vendor-specific fastboot | no |
| Firmware | GSI selection rules, safe flashing order, slot handling | no |
| Google apps | Offline injection of MindTheGapps into a vanilla GSI | no |
| SELinux | The `unlabeled` → `system_file` fix that makes GMS stop crashing | no |
| Fonts | Replacing Roboto with a variable font (Inter) correctly | no |
| First boot | WebView / Play Store / slot-success fixes | no |
| Audio | Bluetooth A2DP provider mismatch (earbuds "connected, no sound") | no |
| Calls | Earpiece routing trap + no usable MTK IMS (HIDL-only APKs) + floss-ims swallowing MT calls — works over CS/CSFB on **every** SIM | no |
| Look & feel | Lawnchair + OneUI icon pack + gestures + wallpapers | no |
| Root | Headless Magisk patch of `init_boot`, module install, Zygisk | yes |
| Rescue | Rollback and bootloop recovery for every irreversible step | no |

---

## The verified end state (case study)

| Item | Value |
|---|---|
| Device | Lava S91 (`LT4901`), MT8786, A/B slots, dynamic partitions |
| System | TrebleDroid `ci-20250415` = Android 15 (BP1A.250405.007, `arm64-ab`) |
| Google apps | MindTheGapps A15 subset injected offline (GMS, Play Store, GSF) |
| Font | Inter (variable) as `sans-serif` |
| Launcher | Lawnchair 15 Beta 3 + OneUI 8.5 icon pack + gestural nav |
| Root | Magisk 31.1 on `init_boot_b` + optional Vector/LSPosed + Iconify 7.3.0 |
| Data | Preserved through font/UI image flashes (no wipe after initial GSI flash) |

Exact hashes, sizes and versions: [`docs/14-verified-manifest.md`](docs/14-verified-manifest.md)
and [`manifests/lava-s91-lt4901.yaml`](manifests/lava-s91-lt4901.yaml).

---

## Repo map

```
AGENTS.md                     ← start here if you are an AI agent
docs/
  00-agent-protocol.md        how to drive this safely (gates, stop conditions)
  01-environment.md           PC tooling, drivers, disk space
  02-inventory.md             discover device, slots, partitions, Treble facts
  03-unlock.md                bootloader unlock (standard + MediaTek quirks)
  04-gsi-selection.md         which GSI will actually boot
  05-flash.md                 fastbootd vs bootloader, vbmeta, userdata, slots
  06-gapps-injection.md       offline MindTheGapps injection with debugfs
  07-selinux-labels.md        the fix for "GMS crashes / unlabeled" AVC denials
  08-fonts.md                 variable-font replacement without breaking fonts.xml
  09-first-boot.md            WebView, Play Store, slot-success, GMS health
  10-root.md                  Magisk headless patch, Zygisk, phh-su conflict
  11-oneui-look.md            launcher/icon/font/QS styling; what is impossible
  12-rescue.md                rollback + bootloop recovery
  13-troubleshooting.md       symptom → cause → fix table
  14-verified-manifest.md     artifact hashes and version matrix
  15-bluetooth-audio-hal.md   BT A2DP "connected but speaker" — provider mismatch fix
  16-call-audio-ims.md        calls dead/silent/incoming missing — vendor audio-policy patch + CS/CSFB lock
  hinglish-quickstart.md      short Hinglish version of the whole procedure
devices/
  lava-s91-lt4901.md          full case study: what really happened
scripts/
  env.sh  inventory.sh  download-gsi.sh  unlock.sh  flash-gsi.sh
  inject-gapps.py  label-selinux.py  patch-fonts.py
  patch-init-boot.sh  install-magisk-module.sh  verify.sh
manifests/
  lava-s91-lt4901.yaml        machine-readable artifact manifest
```

---

## 60-second overview of the whole chain

```text
[locked tablet]
   │  fastboot oem unlock / flashing unlock            (wipes data)
   ▼
[unlocked, stock Android]
   │  fastboot reboot fastboot  (fastbootd)             ← logical partitions only here
   │  fastboot flash system_b <gsi.img>                 ← A/B: pick the live slot
   │  fastboot erase metadata ; format:f2fs userdata
   │  fastboot reboot bootloader
   │  fastboot flash vbmeta_b <empty-vbmeta.img>        ← physical: bootloader only
   │  fastboot --set-active=b ; erase misc ; erase para
   ▼
[GSI boots]
   │  (optional, offline before flashing)
   │  debugfs: inject GApps  +  set SELinux xattrs
   │  debugfs: replace font + patch /system/etc/fonts.xml
   ▼
[clean GSI + Play Store]
   │  fix WebView implementation
   │  install Lawnchair + icon pack, set home + gestural nav
   │  BT audio prop + vendor call-audio policy + CS/CSFB lock (SIM-independent)
   │  (optional) patch init_boot with Magisk, flash, install modules
   ▼
[OneUI-flavoured daily driver]
```

---

## Hard truths (read before promising anything)

1. **GSIs are irreversible on most vendor devices.** If the OEM does not publish firmware,
   flashing `system` destroys the only stock copy. Say this out loud before starting.
2. **Banking / Play-Integrity apps will not work** on an unlocked, test-keys GSI.
3. **A GSI cannot be newer than the vendor.** Android 16 GSI on an Android 15 vendor
   bootloops in most cases.
4. **A GSI replaces `system`, not the OEM skin's features.** Samsung apps, OneUI Settings,
   Knox, AOD, OEM camera modes do not exist in a GSI. A "complete OneUI feel" is achieved
   with launcher + icon pack + SystemUI theming, not by porting OneUI.
5. **Some OEMs ship root already** (PHH/TrebleDroid builds include `phh-su`). That root
   collides with Magisk — see [`docs/10-root.md`](docs/10-root.md).
6. **Never relock a bootloader with a GSI installed.** It can hard-brick.

---

## Downloads

Prebuilt artifacts (final system image, stock/patched `init_boot`) are attached to
[Releases](https://github.com/ismailmo9090-del/android-gsi-oneui-playbook/releases) — see
[`RELEASES.md`](RELEASES.md) for hashes and restore commands. The repository itself only
contains text and scripts.

---

## Credits / upstream

- [TrebleDroid](https://github.com/TrebleDroid/treble_experimentations) — GSI builds
- [MindTheGapps](https://gitlab.com/MindTheGapps) — Google apps
- [Lawnchair](https://github.com/LawnchairLauncher/lawnchair) — launcher
- [Magisk](https://github.com/topjohnwu/Magisk) — root
- [Vector](https://github.com/JingMatrix/Vector) — LSPosed-compatible framework
- [Iconify](https://github.com/Mahmud0808/Iconify) — SystemUI customisation
- [Inter](https://rsms.me/inter/) — font

License: MIT (see [`LICENSE`](LICENSE)). Device brands and app names belong to their owners.
