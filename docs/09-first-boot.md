# 09 — First boot, Google apps and the classic fixes

The GSI boots, but "boots" is not "usable". This page is the checklist that turns a booting
GSI into a daily driver with a working Play Store.

---

## 9.1 First boot

- 1–3 minutes; screen may stay on the boot animation. Do not interrupt.
- If the setup wizard appears, complete it with a local account (skip Google for now).
- Connect Wi-Fi and set the date/time (wrong clock breaks Play login).
- `adb shell getprop sys.boot_completed` must be `1`.

Then mark the slot (`docs/05.5`) and reboot once.

## 9.2 Verify the GSI identity

```bash
adb shell getprop ro.build.display.id      # treble_arm64_bvS-userdebug ...
adb shell getprop ro.build.version.release # 15
adb shell getprop ro.build.fingerprint
adb shell getprop ro.boot.verifiedbootstate  # orange
```

If it still reports the OEM build id, you booted the stock slot — check `current-slot`.

## 9.3 WebView: the Play-Store-login killer

**Symptom:** Play Store opens, you tap "Sign in", it closes; logcat shows

```
com.google.android.gms ... MissingWebViewPackageException
```

GSIs sometimes ship more than one WebView provider (`com.android.webview`,
`com.google.android.webview`, `org.chromium.webview_shell`) and the wrong one is selected.

List and pin the working one:

```bash
adb shell pm list packages | grep -i webview
adb shell dumpsys webviewupdate | grep -i -A3 provider
adb shell cmd webviewupdate set-webview-implementation com.android.webview
```

Verify:

```bash
adb shell dumpsys webviewupdate | grep -i 'Current WebView package'
# Current WebView package (name, version): (com.android.webview, <ver>)
```

The choice persists across reboots. If the command is unavailable, install the WebView APK
matching your ABI and retry.

## 9.4 Play Store / GMS health

```bash
adb shell dumpsys package com.google.android.gms | grep -m2 -E 'versionName|versionCode'
adb shell dumpsys package com.android.vending   | grep -m2 -E 'versionName|versionCode'
adb shell pm list packages | grep -E 'com.google.android.(gsf|gms)|com.android.vending'
```

Expected set: **GMS**, **GSF** (`com.google.android.gsf`), **Play Store**
(`com.android.vending`). If GSF is missing, the GApps subset was too aggressive.

Sign-in checklist if it still fails:

- [ ] WebView pinned (§9.3)
- [ ] SELinux labels correct (`docs/07.4`), no `unlabeled` denials
- [ ] date/time correct
- [ ] no device owner / MDM (see §9.6)
- [ ] Play Store and GMS are from the same GApps package (don't mix versions)
- [ ] `adb logcat | grep -iE 'gms|vending'` has no `FATAL EXCEPTION`

## 9.5 MDM / device owner check (important on refurbished / government devices)

```bash
adb shell dumpsys device_policy | sed -n '1,25p'      # "Enabled Device Admins" should be empty
adb shell dumpsys device_policy | grep -i owner
adb shell pm list packages | grep -iE 'mdm|device.*manager|meraki|vmware|airwatch'
```

If a device-owner app remains, Developer Options and installs stay blocked
("disabled by admin"). Replacing `system` normally removes it; if not, it lives in
`/data` and a factory reset removes it.

## 9.6 Optional: reduce Google bloat

```bash
# examples; keep GMS/GSF/Play Store/WebView
adb shell pm disable-user --user 0 com.google.android.googlequicksearchbox   # Google app / feed
adb shell pm disable-user --user 0 com.google.android.apps.wellbeing
adb shell pm disable-user --user 0 com.google.android.apps.tachyon           # Duo
```

Re-enable with `pm enable --user 0 <pkg>`.

## 9.7 Performance sanity

```bash
adb shell dumpsys meminfo | head -20
adb shell settings get global window_animation_scale   # 1.0 default
```

On low-RAM devices, reducing animations (`0.5`) helps perceived smoothness without breaking
anything:

```bash
adb shell settings put global window_animation_scale 0.5
adb shell settings put global transition_animation_scale 0.5
adb shell settings put global animator_duration_scale 0.5
```

## 9.8 Final acceptance

```bash
adb shell getprop sys.boot_completed                    # 1
adb shell bootctl is-slot-marked-successful 1           # 1
adb shell cmd package resolve-activity --brief -a android.intent.action.MAIN \
        -c android.intent.category.HOME | tail -1       # your launcher
adb shell dumpsys device_policy | grep -ci 'Device Owner' # 0
```

Then reboot one last time and repeat. A GSI that survives a reboot is done.
