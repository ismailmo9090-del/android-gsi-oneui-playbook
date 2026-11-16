# 13 — Troubleshooting (symptom → cause → fix)

Every row here was seen during real flashing sessions or is a direct consequence of a
documented step. When a new symptom appears, append it with the exact command output.

## 13.1 Bootloader / fastboot

| Symptom | Cause | Fix |
|---|---|---|
| `flashing unlock` → "Unlock operation is not allowed" | vendor command differs | `fastboot oem unlock` |
| `fastboot devices` empty | cable/port/driver | data cable, rear port, udev rule |
| Only `0e8d:2000` appears, repeatedly | preloader boot loop | §12.4 |
| `FAILED (remote: 'No such file or directory')` | flashing logical part in bootloader mode | `fastboot reboot fastboot` |
| `Writing 'vbmeta_b' FAILED` | physical part in fastbootd | `fastboot reboot bootloader` |
| `data too large` | `max-download-size` 128 MB | fastbootd |
| `--set-active=b` OKAY, `current-slot: a` | slot B unbootable/retry 0 | erase `misc`+`para`, set-active, reboot bootloader |
| Slot A selected and nothing boots | slot A physically empty | use slot B |
| `format:f2fs:userdata` → `usage: expected argument` | wrong syntax | `format:f2fs userdata` |
| `fastboot -w` says "raw not supported" | fastbootd cannot infer fs | `format:f2fs userdata` |

## 13.2 Boot / system

| Symptom | Cause | Fix |
|---|---|---|
| `adb devices` → `recovery` after flash | GSI rejected (SDK too new) or /data unformatted | format data; pick matching-SDK GSI (`docs/04`) |
| Boot animation forever (>5 min) | wrong GSI arch/vendor mismatch | wait 3 min, then re-flash matching GSI |
| Boots, then reboots after a few seconds | vendor HAL crash | try `vndklite` or older GSI |
| Touch/display dead but system boots | GSI arch or panel overlay missing | different GSI release |
| Device becomes unbootable after several boots | slot retry counter drained | `bootctl mark-boot-successful` (`docs/05.5`) |
| No Wi-Fi / Bluetooth | vendor mismatch (rare on same-SDK GSI) | check `dmesg`, try another GSI |

## 13.3 Google apps

| Symptom | Cause | Fix |
|---|---|---|
| GMS crash loop, no UI | `unlabeled` SELinux on injected APKs | `docs/07` |
| GMS starts then dies in `dlopen` | `lib64` labeled `system_file` | use `system_lib_file` |
| Play Store closes on "Sign in" | `MissingWebViewPackageException` | `cmd webviewupdate set-webview-implementation` (`docs/09.3`) |
| "Device isn't Play Protect certified" | GSI fingerprint not certified | register at google.com/android/uncertified (device ID via `adb shell settings get secure android_id`) |
| Play Store "device not compatible" for apps | generic fingerprint | use Aurora Store's spoof manager, or accept |
| Sign-in fails with network error | wrong clock | set date/time automatically |
| `com.google.android.gsf` missing | GApps subset too aggressive | re-inject GSF/GSF permissions |
| Play Store works, Google app doesn't | Velvet/Google app trimmed | expected; install from Play Store |

## 13.4 Fonts

| Symptom | Cause | Fix |
|---|---|---|
| Font unchanged | `fonts.xml` not replaced / wrong family | `grep -c InterVariable /system/etc/fonts.xml` |
| Some text missing/garbled | declared axes not in font (`ital`/`wdth` on Inter) | remove those axis lines (`docs/08`) |
| Italics upright | replaced italic entries too | keep Roboto-Italic |
| UI crash after font change | malformed XML | validate with minidom, re-flash previous image |
| Font ignored despite correct file | no SELinux label on TTF | `ea_set ... system_file` |

## 13.5 Launcher / UI

| Symptom | Cause | Fix |
|---|---|---|
| Home keeps returning to AOSP launcher | default home not set | `cmd package set-home-activity <pkg>/<activity>` |
| No gesture pill | overlay not enabled | `cmd overlay enable-exclusive --category com.android.internal.systemui.navbar.gestural` |
| Icons too big/small | launcher icon scale pref | set in launcher UI (per-user preference) |
| Icon pack not applied | pack incompatible / not selected | Lawnchair → Icons → icon pack |
| Wallpaper cropped badly | low resolution image | use ≥ 2000 px, set from launcher |
| Text huge everywhere | `font_scale` / display size | `settings get system font_scale`, `wm density` |

## 13.6 Root

| Symptom | Cause | Fix |
|---|---|---|
| Magisk app says "Not Installed" but `magiskd` runs | app data dir empty, app never initialised | open app once, or stage `/data/adb/magisk` manually (`docs/10.5`) |
| `magisk --install-module` → `Incomplete Magisk install` | `/data/adb/magisk/util_functions.sh` missing | copy it + binaries, chmod 755 |
| `init: cannot execv('/debug_ramdisk/magisk')` | wrong SELinux label (`system_file`) | `chcon -R u:object_r:magisk_file:s0 /data/adb/magisk` |
| Modules install but never load | Magisk boot stages failing (see above) or `phh-su` took over `/debug_ramdisk/magisk` | `docs/10.7` |
| `su` works but Zygisk missing | `zygisk=0` in DB or boot stage broken | enable in DB + fix labels, reboot |
| Bootloop after Magisk | patched image incompatible | `fastboot flash init_boot_b init_boot_b_stock.img` |
| Su prompt never appears (Magisk 31) | prompts removed in 31.x | grant in app → Superuser tab |

## 13.7 Performance / battery

| Symptom | Cause | Fix |
|---|---|---|
| Laggy UI | animations, GMS background | reduce animation scales to 0.5 |
| High idle drain | GMS/Play services on a GSI | restrict background, disable unused Google apps |
| Random reboots | vendor/GSI mismatch | check `last_kmsg`/pstore, try another GSI |

## 13.8 Audio / Bluetooth

| Symptom | Cause | Fix |
|---|---|---|
| Earbuds connect, media plays on speaker | BT stack uses GSI `sysbta` provider but the vendor audio HAL expects `vendor/default` | `adb shell su -c 'setprop persist.bluetooth.system_audio_hal.enabled false'` + reboot (`docs/15`) |
| `createProxy: failed to register BT port` in logcat | same provider mismatch | as above |
| `APM failed to make available A2DP device error=1` | A2DP port never registered | as above, then verify during playback |
| A2DP fine, calls fine, but one app silent | per-app audio routing (e.g. app pinned to speaker) | check app's audio output setting / `dumpsys audio` |
| Earbuds mute until re-pair, only after BT restart | multi-point earbuds still attached to phone | disconnect from the other device, re-pair |
| `getprop persist.bluetooth.system_audio_hal.enabled` empty as `shell` | SELinux denies non-root read | read via `su -c getprop …` |

## 13.9 Calls / IMS / call audio

| Symptom | Cause | Fix |
|---|---|---|
| Incoming calls never arrive, outgoing works (or has no ringback) | a **registering** IMS stack (floss-ims `me.phh.ims`) received the MT INVITE but cannot handle it (no ACK, no 180/183, SDP 503) | `pm uninstall --user 0 me.phh.ims`, `cmd overlay disable …flossims_telephony`, `setprop persist.sys.phh.ims.floss false`, reboot — calls then run on CS/CSFB (`docs/16` §16.5) |
| Floss keeps coming back after every reboot | TrebleApp re-enables the floss overlay while `me.phh.ims` is still installed | uninstall the APK (not just disable); `auto-fix.sh` call-guard also enforces it per boot |
| Mobile data works, calls never connect in an LTE-only area | no AIDL MTK `ImsService` on the GSI → no VoLTE (fatal on Jio `405/871`) | no known fix on this vendor; phh `ims-mtk-*` are HIDL-only. Where 2G/3G exists, calls fall back to CS/CSFB |
| `IMS_RILA: getRadioProxy: mRadioProxy == null` every second | `ims-mtk-r/s.apk` speaks HIDL `android.hardware.radio@1.x`, vendor exposes AIDL `IRadioIms` only | expected; keep it only as a placeholder, it will never register |
| Calls connect but ring/audio silent until Speaker is pressed | vendor policy declares a non-existent `Earpiece`; `audioserver` crashes in `connectAudioSourceToSink` | patch vendor `audio_policy_configuration.xml` (4 blocks) — `docs/16` |
| `connectAudioSourceToSink: a swOutput shall always be associated` | same earpiece routing | as above; removing only `voice tx` is not enough |
| `convertModuleConfigToAidl … BAD_VALUE` at boot | `<devicePort tagName="Earpiece">` left behind after route removal | remove `<item>`, `<devicePort>`, `<route sink=Earpiece>`, `<route sink="voice tx">` |
| "4G Calling / VoLTE" switch missing in Settings | IMS not registered / `persist.dbg.volte_avail_ovr` unset | `setprop persist.dbg.volte_avail_ovr 1` + reboot (cosmetic only on this vendor) |
| `INSTALL_FAILED_VERIFICATION_FAILURE` while installing `ims-mtk-r.apk` | Play Protect blocks `com.mediatek.ims` | `settings put global verifier_verify_adb_installs 0`, install again |
| `persist.sys.phh.disable_voice_call_in=true` makes boot audio unstable | wrong switch for this vendor | keep it `false` |

## 13.10 Collecting evidence for a bug report

```bash
adb shell getprop > props.txt
adb shell dmesg > dmesg.txt 2>/dev/null
adb logcat -d -b all > logcat.txt
adb shell dumpsys > dumpsys.txt
adb shell ls -lZ /system/product/priv-app > labels.txt 2>&1
adb shell 'ls /data/adb/modules' > modules.txt 2>&1
```

Redact serial numbers and account e-mails before publishing.
