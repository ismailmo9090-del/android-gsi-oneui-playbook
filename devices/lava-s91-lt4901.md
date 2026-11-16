# Case study — Lava S91 (LT4901), MediaTek MT8786

Full record of what was actually done to this unit on 2026-11-15/16, including dead ends.
Useful as a reality check: the generic docs describe the happy path; this is the road.

> Serial number, account e-mail and other identifiers are redacted on purpose.

---

## 1. The device

| Item | Value |
|---|---|
| Marketing | Lava S91 |
| Model | LT4901 |
| SoC | MediaTek MT8786 (Helio G85 family) |
| Board | `tb8786p1_64_k66` |
| Stock Android | 15, `AP3A.240905.015.A2`, vendor security patch 2026-10-24 |
| Bootloader | `tb8786p1_64_k66-ab11e45d726-20261024143` |
| Slots | A/B, but **slot A is empty from the factory** |
| `super` | 9,663,676,416 bytes |
| `userdata` | 51,528,040,448 bytes (48 GB), f2fs |
| Display density | 240 dpi |
| Page size | 4096 |

**Why it was flashed:** the stock ROM contained a government MDM device-owner app that
blocked Developer Options and app installs and re-enrolled after every factory reset.
Replacing `system` removed it permanently.

Key partition nodes observed:

```
boot_a        mmcblk0p24      boot_b        mmcblk0p41
init_boot_a   mmcblk0p26      init_boot_b   mmcblk0p43
vbmeta_a      mmcblk0p5       vbmeta_b      mmcblk0p8
vbmeta_system_a p6            vbmeta_system_b p9
vbmeta_vendor_a p7            vbmeta_vendor_b p10
boot_para     p32             super         logical (dynamic)
preloader_a/b mmcblk0boot0/1  metadata      p12 (67 MB)
```

## 2. What happened, in order

### 2.1 Unlock

```
fastboot flashing unlock      → "Unlock operation is not allowed"
fastboot oem unlock           → OKAY, unlocked: yes, secure: no
```

No on-screen confirmation appeared on this unit. Userdata was wiped.

### 2.2 First attempts (all failed)

| Attempt | Result |
|---|---|
| PHH AOSP `v416` (Android 16) `arm64-ab-vanilla` | boot loop (GSI newer than vendor) |
| Andy Yan LineageOS 22.2 "Light" `arm64_vN` | boots to recovery |
| TrebleDroid `ci-20250415` (Android 15) `arm64-ab-vanilla` | **boots** ✅ |

Lesson encoded in `docs/04`: GSI SDK must be ≤ vendor SDK.

### 2.3 Flash sequence that worked

```
fastboot reboot fastboot                     # is-userspace: yes
fastboot flash system_b td_a15_arm64-ab-vanilla.img
fastboot erase metadata
fastboot format:f2fs userdata
fastboot reboot bootloader
fastboot flash vbmeta_b        vbmeta_empty.img   # flags=3
fastboot flash vbmeta_system_b vbmeta_empty.img
fastboot flash vbmeta_vendor_b vbmeta_empty.img
fastboot erase misc
fastboot erase para
fastboot --set-active=b
fastboot reboot bootloader
fastboot getvar current-slot                 # b
fastboot reboot
```

First boot took ~90 s. `adb root` worked (`userdebug`), MDM gone.

### 2.4 Google apps

No maintained GApps GSI existed for Android 15 on TrebleDroid (`ci-20250415` ships vanilla
only; PHH gapps builds were Android 12-era). Solution: inject **MindTheGapps A15** offline.

- extracted to `mtg_new/`
- trimmed `Velvet`, `VelvetTitan`, `TalkBack`, `Wellbeing`, `GoogleRestore`, `SetupWizard`
- `debugfs write` into `system/product` + `system/system_ext`
- image grew 2,147,311,616 → 2,936,012,800 bytes; `super` had ~4 GB free

**First result: GMS crash loop.** Logcat:

```
avc: denied { read } ... tcontext=u:object_r:unlabeled:s0 tclass=dir
```

Fix: `debugfs ea_set security.selinux` on **every** injected file and directory:

- `system_file` for normal files
- `system_lib_file` for `product/lib64/*`

After re-flash: Play Store 41.9.17, GMS 24.28.35, account signed in.

### 2.5 Play Store login crash

Symptom: tapping "Sign in" closed Play Store.
Logcat: `MissingWebViewPackageException`.

```
adb shell cmd webviewupdate set-webview-implementation com.android.webview
```

Persisted. Login worked.

### 2.6 UI layer

- Lawnchair 15 Beta 3 installed and set as home
- gestural navigation overlay enabled
- OneUI 8.5 icon pack + squircle applied by the user
- Inter variable font injected into the system image (`fonts.xml`, 9 entries) and re-flashed
  **without wiping data** — the account and launcher layout survived
- wallpaper set by the user

### 2.7 Root

- backed up `init_boot_b` and `boot_b`
- `boot_patch.sh` (from the Magisk APK assets) run **on the device** over adb → patched
  `init_boot_b` flashed; Magisk 31.1 boots, `magiskd` runs
- Magisk app data dir was empty ("Not Installed") → binaries + `util_functions.sh` staged
  manually into `/data/adb/magisk`
- Vector v2.2 (LSPosed-compatible) module installed via `magisk --install-module`
- Zygisk enabled in Magisk's SQLite settings

**Then the discovery:** on later boots `/debug_ramdisk/magisk` was replaced by the ROM's
built-in `phh-su` (identical md5 to `/system/xbin/su`). Magisk's `--post-fs-data` and
`--boot-complete` stages stopped running (`nosuid_transition` denial for `init`), so modules
and Zygisk never loaded. Root itself still works through `phh-su`.

Also learned: files copied into `/data/adb/magisk` with `cp` get `system_file` labels, which
breaks Magisk's own boot stages — they must be `magisk_file`. Both issues are documented in
`docs/10`.

### 2.8 Icon size request

The user asked to reduce icon size. This is a per-user launcher preference
(`pref_iconSizeFactor` / Home screen → Icons in Lawnchair) and is best changed in the UI or
while the launcher is stopped; it is not a system-level property. See
`docs/13-troubleshooting.md` §13.5.

### 2.9 Calls: IMS + call audio (2026-11-16)

After the UI work the tablet was used with a Jio SIM: data worked, calls did not. Three problems,
all SIM-independent:

1. **Vendor declared an Earpiece the tablet does not have.** `audioserver` crashed with
   `connectAudioSourceToSink: a swOutput shall always be associated` at call setup; with only
   the `voice tx` route removed, Speaker had to be pressed for every call. Removed all four
   Earpiece-related blocks from `/vendor/etc/audio_policy_configuration.xml` and rebuilt the
   EROFS `vendor_b` (405,835,776 B) with device-captured SELinux labels, gid 2000 and fakeroot
   metadata, then flashed it in fastbootd (10.7 s). Data untouched.
2. **No usable MTK IMS on the GSI.** The vendor exposes **AIDL** radio
   (`android.hardware.radio.ims.IRadioIms/slot1-2`, `…mtkradioex.ims-V2-ndk.so`), while phh's
   `ims-mtk-r/s.apk` are HIDL-only — installed they log `IMS_RILA: getRadioProxy: mRadioProxy
   == null` every second and never register. No stock LT4901 dump exists to extract the tablet's
   own Android 15 IMS APK. The vendor `volte_*` daemons also never register (no SIP socket, no
   XFRM state).
3. **floss-ims made incoming calls worse.** With a Jio/Airtel SIM, floss (`me.phh.ims`, TCP)
   registered successfully but never ACKed the `200 OK`, ignored 180/183, and **received zero MT
   INVITEs** while holding the registration. Removing it restored both directions.
   Also: TrebleApp re-enables the floss overlay on every boot while `me.phh.ims` is installed, so
   the APK has to be uninstalled, not just disabled.

**Final, verified mode: CS/CSFB.** `com.mediatek.ims` (ims-mtk-r) stays installed purely as the
framework binding; it never registers, so MO calls fall back to GSM/WCDMA (`GsmCdmaCallTracker:
dialGsm` in the log) and MT calls arrive over SGs paging. On Airtel (`+91 73096 83245`): outgoing
call → `ACTIVE`, incoming call → rings and `ACTIVE`, 15 s call log entry, two-way audio, no
earpiece press needed. Floss is uninstalled, `flossims` overlay off, `mtkims` overlay on,
`persist.sys.phh.ims.floss=false`.

Caveat: this needs 2G/3G coverage for CSFB. In an LTE-only cell, voice requires a real AIDL MTK
IMS APK, which this device has no source for.

Hashes and the rebuild flow: `docs/16-call-audio-ims.md`. Rolling back is a single
`fastboot flash vendor_b vendor_stock_lt4901.img`.

## 3. Final state

```
ROM          TrebleDroid ci-20250415 (Android 15, BP1A.250405.007)
Slot         B, marked successful, retry OK
Google       GMS 24.28.35, Play Store 41.9.17, WebView com.android.webview
Font         Inter (variable)
Home         Lawnchair 15 Beta 3 + OneUI 8.5 icon pack + gestural nav
Root         phh-su (ROM built-in); Magisk 31.1 present but module/Zygisk stability limited
BT audio     A2DP on MediaTek vendor provider (persist.bluetooth.system_audio_hal.enabled=false)
Calls        CS/CSFB (verified both directions); com.mediatek.ims installed as placeholder, floss removed; vendor policy without Earpiece
Vendor       vendor_b patched (audio policy 9c4dd6d8…, 18861 B), stock image kept for rollback
Data         preserved through the font/UI/vendor re-flashes
```

Hashes and exact artifacts: `docs/14-verified-manifest.md`.

## 4. Honest limitations on this unit

- **No stock firmware publicly available** → flashing `system_b` destroyed the only stock
  copy; there is no return path without Lava service firmware.
- Slot A is empty; it cannot be used as a rescue slot.
- `mtkclient` / BROM recovery did not work (libusb configuration error).
- Recovery `adb shell` is broken (SELinux context abort); `adb reboot fastboot` works.
- Banking / Play Integrity apps fail.
- Magisk + Zygisk modules are unreliable because of the built-in `phh-su` (see `docs/10.7`).
- A "complete OneUI" experience is not achievable on this MTK GSI; launcher + icons + font
  is the realistic maximum without an actual Samsung ROM.
