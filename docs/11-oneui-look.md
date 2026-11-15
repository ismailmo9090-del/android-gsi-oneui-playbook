# 11 — OneUI / iOS look without flashing a ROM

A GSI gives you AOSP. A "OneUI feel" is a **layer**, not a ROM: launcher, icons, font,
wallpaper, gestures, and (with root) SystemUI theming.

Be precise with the user:

| Want | Possible? | How |
|---|---|---|
| OneUI home screen + app icons | ✅ | Lawnchair/Niagara + OneUI icon pack |
| OneUI font/typography | ✅ | variable font in `fonts.xml` (`docs/08`) |
| Squircle icons, rounded UI | ✅ | icon pack shape + launcher radius |
| Gesture navigation | ✅ | `cmd overlay enable-exclusive …gestural` |
| OneUI quick-settings panel / status bar | ⚠️ | Iconify (needs root + Zygisk) |
| OneUI lock screen clock / AOD | ❌ | part of Samsung SystemUI/Always-On service |
| Samsung Settings, Dialer, Camera, Weather | ❌ | vendor apps; cannot run on a GSI |
| Knox / Secure Folder / Samsung Pay | ❌ | hardware-backed, Samsung-only |
| "Exactly like S25" | ❌ | say it plainly |

## 11.1 Launcher (no root)

```bash
adb install -r Lawnchair.apk          # 15 Beta 3 used here
adb shell cmd package set-home-activity app.lawnchair/app.lawnchair.LawnchairLauncher
adb shell cmd overlay enable-exclusive --category \
  com.android.internal.systemui.navbar.gestural
adb shell cmd overlay list | grep '\[x\].*navbar'    # verify
```

Lawnchair settings: long-press home → **Home settings** (or launch
`app.lawnchair/.ui.preferences.PreferenceActivity`).

Key prefs for a OneUI look:

| Pref | Value |
|---|---|
| `pref_iconPackPackage` | the icon pack package (e.g. `com.debojyoti.oneui_icpack`) |
| `pref_icon_shape_path` | squircle path (icon pack can provide it) |
| icon size / grid | Home screen → Icons / Grid (5×5 or 4×6 for tablets) |
| labels | off for a cleaner dock |
| search bar | Google/QuickSearch or none |

Icon size is a **user preference** — do not push values remotely; either set it in the UI or
write the pref while the launcher is stopped (see `docs/troubleshooting.md`, "icon size").

## 11.2 Icon pack

Any `IconPack`-compatible APK works. Apply through Lawnchair → Home settings → Icons →
Icon pack. Avoid packs that require a specific launcher.

## 11.3 Wallpaper

```bash
adb push wallpaper.png /sdcard/Pictures/
```
Then set from the launcher/gallery. On tablets use ≥ 2000 px images to avoid upscaling.

## 11.4 Status bar / QS (root path, optional)

Iconify 7.3.0 can restyle:

- QS tiles (shape, blur, colours, labels)
- brightness slider
- status-bar icons, clock, battery style
- notification shade transparency/rounding
- power menu, volume panel
- lock-screen clock style

But it hooks `SystemUI` through Zygisk. On the reference device Zygisk could not stay loaded
because of the `phh-su` conflict (`docs/10.7`), so treat this as **best effort** and tell the
user up front.

Non-root alternatives (significantly more limited): Power Shade / One Shade-style shade
replacements, custom status-bar apps. They draw over SystemUI, they do not replace it, and
they often break notification actions.

## 11.5 Font + icons + wallpaper = 80 % of the feel

Realistic outcome on a GSI:

```
launcher      Lawnchair (OneUI-like grid, dock, search)
icons         OneUI icon pack + squircle mask
font          Inter / SamsungOne-like variable font
wallpaper     OneUI-style gradient
gestures      gestural nav
```

That is enough for most users; the remaining 20 % (Settings app, Samsung apps, AOD) requires
a real OneUI port, which does not exist for MediaTek GSIs.

## 11.6 If the user insists on a real OneUI port

Options and their costs:

1. **OneUI port GSI (unofficial)** — rare, device-specific, often unmaintained, may contain
   proprietary blobs of unknown origin. No OTA, no support. Requires the vendor to be
   Samsung-compatible; on MTK it usually does not boot.
2. **Build from source** — needs Samsung's framework, impossible without their source.
3. **Buy a Samsung device** — the honest answer for a "complete OneUI" requirement.

Say this before spending hours.
