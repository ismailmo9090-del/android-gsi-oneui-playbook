# 06 — Injecting Google apps into a vanilla GSI (offline)

When no maintained GApps GSI exists for your Android version, inject a GApps package into
the system image **on the PC** with `debugfs`. No device, no root, no overlayfs hacks — the
result is a normal flashable `system.img`.

Verified: MindTheGapps A15 → TrebleDroid `ci-20250415`, image grew
`2,147,311,616 → 2,936,012,800` bytes (+788 MB) and Play Store worked after the SELinux fix
in `docs/07`.

---

## 6.1 Why offline injection

| Approach | Problem |
|---|---|
| `adb root` + copy into `/system` | overlayfs / tmpfs, lost on reboot or on dm-verity |
| Magisk module with GApps | needs root first, slower boot, some apps still fail |
| GApps GSI | often not available for new Android versions |
| **Offline `debugfs` injection** | persistent, matches a normal GSI flash, reproducible |

## 6.2 Requirements

- the GSI `.img` is **raw ext4** (not sparse, not erofs). Check:
  ```bash
  file gsi.img
  # "Linux rev 1.0 ext4 filesystem data"  ✅
  # "Android sparse image"                → simg2img first
  ```
- `debugfs` from `e2fsprogs`
- a GApps zip with a `system/` tree (MindTheGapps, OpenGApps, NikGapps)
- free space inside `super` for the bigger image (`docs/02.4`)

## 6.3 Extract and trim

```bash
mkdir -p gapps && unzip -q MindTheGapps-15.0.0-arm64-*.zip -d gapps
ls gapps/system            # app/ priv-app/ etc/ framework/ product/ system_ext/
```

MindTheGapps A15 layout relevant to a minimal install:

```
system/product/app/GoogleCalendarSyncAdapter
system/product/app/GoogleContactsSyncAdapter
system/product/app/MarkupGoogle_v2
system/product/app/PrebuiltExchange3Google
system/product/app/SpeechServicesByGoogle
system/product/etc
system/product/framework
system/product/lib64
system/product/overlay
system/product/priv-app/GmsCore
system/product/priv-app/GooglePartnerSetup
system/product/priv-app/Phonesky
system/system_ext/etc
system/system_ext/priv-app/GoogleFeedback
system/system_ext/priv-app/GoogleServicesFramework
```

Trim aggressively — every MB matters inside `super`:

| Drop | Why |
|---|---|
| `Velvet`, `VelvetTitan` | Google app / assistant, huge |
| `TalkBack`, `Accessibility` | optional |
| `Wellbeing`, `DigitalWellbeing` | optional |
| `GoogleRestore`, `SetupWizard` | GSI already has a setup wizard; can conflict |
| `vending` duplicates, `MediaProvider` duplicates | already in GSI |
| `*_v8a`/split APKs you don't need | size |

Keep: **GmsCore** (GMS), **Phonesky** (Play Store), **GoogleServicesFramework**,
**GooglePartnerSetup**, sync adapters, `etc/permissions/*` (privapp allowlists), overlays,
`framework` jars, `lib64`.

## 6.4 Grow the image (only if needed)

```bash
# current size and free space inside ext4
stat -c%s gsi.img
debugfs -R 'stats' gsi.img 2>/dev/null | grep -E 'Block size|Free blocks|Block count'
```

If the payload will not fit, grow the image:

```bash
truncate -s 2936012800 gsi.img          # target size, multiple of 4096
e2fsck -f -y gsi.img
resize2fs gsi.img
```

`resize2fs` grows the filesystem to the new file size. Keep a copy of the original `.img`
before any edit.

## 6.5 Inject (debugfs command file)

`scripts/inject-gapps.py` does this generically. The core idea:

```python
cmds = []
for each file in selected roots:
    cmds.append(f'mkdir "/system/product/priv-app"')   # parents first
    cmds.append(f'write "{host_path}" "{image_path}"') # or: symlink
subprocess.run(["debugfs", "-w", "-f", cmdfile, IMG])
```

Example generated commands:

```
mkdir "/system/product"
mkdir "/system/product/priv-app"
mkdir "/system/product/priv-app/Phonesky"
write "/home/u/gapps/system/product/priv-app/Phonesky/Phonesky.apk" "/system/product/priv-app/Phonesky/Phonesky.apk"
symlink "/system/product/etc/permissions/xyz.xml" "/system/etc/permissions/xyz.xml"
```

Notes:

- `debugfs` does **not** create parent directories; emit `mkdir` for every level.
- `write` overwrites existing files silently in some versions — check `suspicious` output
  for `exists` / `not found`.
- Preserve symlinks with `symlink <dest> <target>` instead of dereferencing.
- Run with `-w` (write mode). Use `-f` for large command lists (thousands of lines).

## 6.6 Verify before flashing

```bash
debugfs -R 'ls -l /system/product/priv-app' gsi.img 2>/dev/null | head
debugfs -R 'ls -l /system/product/priv-app/Phonesky' gsi.img
debugfs -R 'cat /system/product/etc/permissions/privapp-permissions-google.xml' gsi.img | head
```

Sanity checklist:

- [ ] `GmsCore`, `Phonesky`, `GoogleServicesFramework` present
- [ ] `lib64` present next to GmsCore (GMS loads native libs)
- [ ] permission XMLs copied (`etc/permissions`, `etc/sysconfig`)
- [ ] overlays copied (`product/overlay`)
- [ ] every injected file has an SELinux label → **`docs/07`** (this is the step people skip)

## 6.7 Flash

Use `docs/05.7` (system-only re-flash, no data wipe). Then:

```bash
adb shell pm list packages | grep -E 'com.google.android.gms|com.android.vending'
adb shell dumpsys package com.google.android.gms | grep -m1 versionName
```

If GMS/Play Store crash immediately, 95 % of the time it is the SELinux label problem in
`docs/07`, not a bad APK.
