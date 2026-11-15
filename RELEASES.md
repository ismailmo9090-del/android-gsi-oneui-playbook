# Releases

Prebuilt artifacts for the reference device (Lava S91 / LT4901). The repository itself
contains no binaries; everything large lives in GitHub Releases.

> **These images are device-specific.** The system image targets an Android 15 vendor,
> arm64 A/B device with a `super` partition of at least ~9 GB. The `init_boot` images are
> for the LT4901 only — flashing them on another model can brick it.

---

## `gsi-2026-11-16`

| Asset | Bytes | SHA-256 | Purpose |
|---|---|---|---|
| `td_a15_ui.img.xz` | <!--XZ_SIZE--> | <!--XZ_SHA--> | Final system image: TrebleDroid A15 + MindTheGapps subset + Inter font |
| `init_boot_b_stock.img` | 8,388,608 | `a2ff249a9e5fb4fb2a37ade12ba9bcf84b7f35da1172f12d22b9d119f96432b1` | Stock boot ramdisk (Magisk rollback) |
| `init_boot_b_magisk.img` | 8,388,608 | `a210325af7665aef5846097fb753001c14d3c50e6af46ccc1fcae256244e506f` | Same, patched with Magisk 31.1 |

Full manifest: [`docs/14-verified-manifest.md`](docs/14-verified-manifest.md) and
[`manifests/lava-s91-lt4901.yaml`](manifests/lava-s91-lt4901.yaml).

---

## Flashing the system image

```bash
# 1. verify after download
sha256sum td_a15_ui.img.xz        # compare with the table above
xz -t td_a15_ui.img.xz            # integrity
xz -dk td_a15_ui.img.xz           # -> td_a15_ui.img (2,936,012,800 bytes)

# 2. check the target device first (never skip)
fastboot getvar is-userspace      # no = bootloader
fastboot reboot fastboot
fastboot getvar is-userspace      # must be yes
fastboot getvar current-slot      # b

# 3. flash system only — data is preserved
fastboot flash system_b td_a15_ui.img
fastboot reboot bootloader
fastboot --set-active=b
fastboot reboot
```

First boot: ~90 s. Then:

```bash
adb shell getprop sys.boot_completed        # 1
adb shell bootctl mark-boot-successful
adb shell cmd webviewupdate set-webview-implementation com.android.webview
```

If this is the **first** GSI flash on a stock device, follow
[`docs/05-flash.md`](docs/05-flash.md) instead — you also need `metadata`/`userdata` wipe and
empty vbmeta images.

## Restoring the stock boot ramdisk

Only needed if Magisk causes a boot loop:

```bash
fastboot flash init_boot_b init_boot_b_stock.img
fastboot reboot
```

## What is inside the system image

- TrebleDroid `ci-20250415` (`BP1A.250405.007`, Android 15, `arm64-ab`, userdebug)
- MindTheGapps A15 subset: GMS, Play Store, GSF, partner setup, sync adapters, overlays
- SELinux labels on every injected path (`system_file` / `system_lib_file`)
- Inter variable font as `sans-serif` (9 entries in `/system/etc/fonts.xml`)

Not included: Google app/Velvet, TalkBack, Wellbeing, SetupWizard, GoogleRestore — trimmed to
fit `super`. Root is not included; see [`docs/10-root.md`](docs/10-root.md).
