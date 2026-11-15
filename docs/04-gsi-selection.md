# 04 — Choosing a GSI that will actually boot

The number one cause of "GSI bootloops / drops to recovery" is a version mismatch with the
**vendor** partition. A GSI replaces `system`; the vendor HALs, kernel and firmware stay
stock. The GSI must speak the vendor's Android API level.

---

## 4.1 The compatibility rule

```
GSI SDK  ≤  vendor SDK        (equal is best)
```

Check the vendor:

```bash
adb shell getprop ro.vendor.build.version.sdk
adb shell getprop ro.vendor.build.version.release
adb shell getprop ro.vndk.version
```

Examples from real hardware:

| Vendor | Try | Result |
|---|---|---|
| Android 15 (SDK 35) | Android 15 GSI | ✅ boots |
| Android 15 (SDK 35) | Android 16 GSI (PHH v416) | ❌ boot loop |
| Android 15 (SDK 35) | LineageOS 22.2 "Light" | ❌ falls back to recovery |
| Android 15 (SDK 35) | **TrebleDroid ci-20250415** | ✅ boots (has MTK patches) |

## 4.2 Naming / architecture

| Suffix | Meaning |
|---|---|
| `arm64-ab` | ARM64, A/B slots (most modern devices) |
| `arm64-a` (sometimes `arm64-aonly`) | ARM64, A-only |
| `a64` | 32-bit userspace on 64-bit kernel |
| `arm` / `a32` | 32-bit |
| `-vanilla` | no Google apps |
| `-gapps` | Google apps included (rare for Android 15) |
| `vndklite` | relaxed VNDK requirements, for odd vendors |
| `bvS` / `bvN` | build variant flags in `ro.build.flavor` (S = secure/`user`, N = `userdebug`) |

Check the device: `ro.product.cpu.abilist` and `ro.build.ab_update`.

## 4.3 Recommended sources (in order)

1. **TrebleDroid** — https://github.com/TrebleDroid/treble_experimentations/releases
   Best MediaTek compatibility, `userdebug`, `adb root` works.
2. **PHH AOSP** — https://github.com/phhusson/treble_experimentations/releases
   Broad device support; check the Android version.
3. **LineageOS GSI (Andy Yan)** — https://sourceforge.net/projects/andyyan-gsi/files/
   Nice daily driver, but "Light" variants are picky about VNDK.
4. OEM / community GSI ports (OneUI ports, etc.) — last resort: unknown provenance,
   often no source, may include malware.

## 4.4 Vanilla vs GApps

| | Vanilla | GApps GSI |
|---|---|---|
| Play Store | no | yes |
| Size | ~2.1 GB | ~2.6 GB |
| Update path | inject GApps yourself (`docs/06`) | fixed at build time |
| Android 15 availability | good | scarce |

For Android 15 in 2026 there was **no maintained GApps asset** for TrebleDroid, so this
playbook injects MindTheGapps offline. That also lets you trim 300+ MB of unwanted Google
apps.

## 4.5 Download and verify

```bash
URL=https://github.com/TrebleDroid/treble_experimentations/releases/download/ci-20250415/system-td-arm64-ab-vanilla.img.xz
curl -L --fail --retry 3 -o gsi.img.xz "$URL"
sha256sum gsi.img.xz          # compare with the release notes / manifest
xz -t gsi.img.xz              # integrity
xz -dk -T0 gsi.img.xz         # decompress
```

Single-stream GitHub downloads can crawl (~190 KB/s). `scripts/download-gsi.sh` uses 12
parallel HTTP range requests and resumes.

## 4.6 Sanity-check the image before flashing

```bash
file gsi.img                      # "Android sparse image"? then simg2img first
stat -c%s gsi.img                 # 2.0–3.0 GB typical
debugfs -R 'ls -l /' gsi.img 2>/dev/null | head
debugfs -R 'cat /system/build.prop' gsi.img 2>/dev/null | head   # may be absent
```

If `file` says **sparse**, convert: `simg2img gsi.img gsi.raw.img` and flash the raw one.
Most fastboot builds accept sparse too, but `debugfs` (for GApps injection) needs raw ext4.

## 4.7 Decision record

Write this before flashing:

```
Device vendor SDK:   35 (Android 15)
Device ABI:          arm64-v8a
Slots:               A/B (super, dynamic)
Chosen GSI:          TrebleDroid ci-20250415, arm64-ab-vanilla, Android 15
Why:                 same SDK as vendor; MTK patches; userdebug → adb root
Rejected:            PHH v416 (SDK 36), Lineage 22.2 Light (recovery fallback)
```
