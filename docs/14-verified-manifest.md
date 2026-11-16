# 14 — Verified manifest (reference device)

Everything below was hashed/verified on the reference device on **2026-11-16**. Treat it as a
known-good baseline: if your artifact differs, stop and identify why before flashing.

Machine-readable copy: [`../manifests/lava-s91-lt4901.yaml`](../manifests/lava-s91-lt4901.yaml)

---

## 14.1 Host artifacts

| File | Bytes | SHA-256 |
|---|---|---|
| `td_a15_arm64-ab-vanilla.img` (TrebleDroid ci-20250415, decompressed) | 2,147,311,616 | `ac1553fc6ea01ba62d61672d43de5cea8952557ea693e50c15f2e2a312f8ae04` |
| `td_a15_gapps.img` (vanilla + MindTheGapps A15 subset, Roboto) | 2,936,012,800 | `d8f17822bbf728576ee8ce20eed4ad689c08cdc999e94aa338113d26c0ab5cad` |
| `td_a15_ui.img` (**final**: + Inter font) | 2,936,012,800 | `8fd8167f2fdb0e7a4c00746214387e0ba80a882d298cd2a16c3c2ccc78b9934e` |
| `init_boot_b_stock.img` | 8,388,608 | `a2ff249a9e5fb4fb2a37ade12ba9bcf84b7f35da1172f12d22b9d119f96432b1` |
| `init_boot_b_magisk.img` (Magisk 31.1 patched) | 8,388,608 | `a210325af7665aef5846097fb753001c14d3c50e6af46ccc1fcae256244e506f` |
| `vendor_stock_lt4901.img` (stock `vendor_b` dump) | 405,835,776 | `f3ad6ad24a4a77965b5a336bc9ade1161d9e33f7a23ceca0f601e992a59b845b` |
| `vendor_patched_lt4901.img` (audio policy w/o Earpiece) | 405,835,776 | `468bcd2ddd19a9cd3455bf9f3b93335628937a7de842cd0d660015de0e57750a` |
| `ims-mtk-r.apk` (phh IMS for MTK R vendor) | 6,106,173 | `1dcdc56543d77ed1377e1345adb4110f910d286c17e0a5781c32818aac6f4a61` |

Application packages used:

| Package | Version |
|---|---|
| Lawnchair | 15 Beta 3 (`app.lawnchair`) |
| OneUI icon pack | 8.5 (`com.debojyoti.oneui_icpack`) |
| Magisk | 31.1 (`com.topjohnwu.magisk`) |
| Vector | v2.2 canary 3119 (`zygisk_vector` module) |
| Iconify | 7.3.0 FOSS (A15-compatible; v8 needs Android 16 QPR1+) |

## 14.2 Final system configuration

| Property | Value |
|---|---|
| ROM | TrebleDroid `ci-20250415`, Android 15.0.0_r26 |
| Build | `treble_arm64_bvS-userdebug 15 BP1A.250405.007 250414 test-keys` |
| Boot slot | B (`ro.boot.slot_suffix=_b`), marked successful |
| Verified boot | `orange` (unlocked) |
| GMS | 24.28.35 at sign-in time (auto-updated later) |
| Play Store | 41.9.17 at sign-in time |
| WebView provider | `com.android.webview` (pinned) |
| Font | `InterVariable.ttf`, 9 refs in `/system/etc/fonts.xml` |
| Home | `app.lawnchair/.LawnchairLauncher` |
| Navigation | gestural overlay enabled |
| Bluetooth audio | `persist.bluetooth.system_audio_hal.enabled=false` (MTK vendor provider) |
| Call audio | vendor policy without Earpiece — `9c4dd6d8…`, 18861 B; speaker is default output |
| Voice mode | **CS/CSFB only** — no IMS stack registers on this vendor (AIDL radio vs HIDL-only phh APKs). Incoming + outgoing verified on Airtel. |
| IMS | `com.mediatek.ims` (`ims-mtk-r`) is installed as a framework placeholder only; overlay `me.phh.treble.overlay.mtkims_telephony` on, `…flossims_telephony` off, `me.phh.ims` (floss) uninstalled |
| IMS props | `vilte_support=0`, `disable_voice_call_in=false`, `ims.floss=false`, `volte_avail_ovr=1`, `wfc_avail_ovr=1`, `allow_ims_off=0` |
| Display | 240 dpi, 4096-byte pages |
| Data | preserved (no wipe during font/UI re-flash) |

## 14.3 Device facts (stock, before flashing)

| Item | Value |
|---|---|
| Marketing | Lava S91 |
| Model / board | LT4901 / `tb8786p1_64_k66` |
| SoC | MediaTek MT8786 (`ro.boot.hardware=mt8786`, `ro.board.platform=mt6768`) |
| Stock build | `AP3A.240905.015.A2`, Android 15 (SDK 35) |
| Slot layout | A/B, dynamic partitions in `super` |
| `super` size | 9,663,676,416 bytes |
| `userdata` | 51,528,040,448 bytes, f2fs |
| `metadata` | 67,108,864 bytes |
| `boot_<slot>` | 67,108,864 bytes |
| `init_boot_<slot>` | 8,388,608 bytes |
| USB IDs | `0e8d:2000` preloader, `0e8d:201c` fastboot, `18d1:d001` adb |
| Unlock | `fastboot oem unlock` (standard `flashing unlock` refused) |

## 14.4 Rebuild the final image from scratch

```bash
# 1. vanilla
xz -dk td_a15_arm64-ab-vanilla.img.xz

# 2. inject GApps (selects a trimmed MindTheGapps subset)
python3 scripts/inject-gapps.py \
  --img td_a15_arm64-ab-vanilla.img \
  --src gapps/ \
  --include manifests/gapps-minimal.txt \
  --out td_a15_gapps.img

# 3. label everything (the fix that makes GMS work)
python3 scripts/label-selinux.py --img td_a15_gapps.img --src gapps/ \
  --include manifests/gapps-minimal.txt

# 4. font
python3 scripts/patch-fonts.py --img td_a15_gapps.img \
  --ttf InterVariable.ttf --family sans-serif --styles normal \
  --out td_a15_ui.img

# 5. verify
bash scripts/verify.sh --img td_a15_ui.img \
  --expect-gapps --expect-font InterVariable.ttf
```

## 14.5 Reproduction commands used on the device

```bash
# flash only the system image (keeps data)
fastboot reboot fastboot
fastboot flash system_b td_a15_ui.img
fastboot reboot bootloader
fastboot --set-active=b
fastboot reboot

# after boot
adb shell cmd webviewupdate set-webview-implementation com.android.webview
adb shell cmd package set-home-activity app.lawnchair/app.lawnchair.LawnchairLauncher
adb shell cmd overlay enable-exclusive --category \
  com.android.internal.systemui.navbar.gestural
adb shell bootctl mark-boot-successful
```

## 14.6 Vendor audio policy + IMS (call fix)

Stock vendor policy is 19587 B (`ae815b68…`); the patched one is 18861 B (`9c4dd6d8…`), with the
Earpiece `<item>`, `<devicePort>`, sink route and the `voice tx` route removed (detail:
[`16-call-audio-ims.md`](16-call-audio-ims.md)).

```bash
# call fix on a booted tablet (vendor policy + CS/CSFB lock + reboot + verify)
./call-audio-fix.sh
./call-audio-fix.sh --verify
./call-audio-fix.sh --rollback          # stock vendor_b back

# manual equivalent of the vendor half
adb reboot fastboot
fastboot getvar is-userspace            # yes
fastboot getvar current-slot            # b
fastboot flash vendor_b vendor_patched_lt4901.img
fastboot reboot
```

The patched image was rebuilt from the device's own dump with `erofs-utils` 1.9
(`-zlz4hc,9 -C16384`, same UUID), SELinux labels captured with `stat -c '%C'` on the live
`/vendor`, gid 0/2000 and modes restored through `fakeroot`, then loop-mounted on the device and
compared path-by-path (2480/2480 labels and metadata match) before flashing. No AVB hashtree is
needed because the kit already flashes an empty `vbmeta` (`verifiedbootstate=orange`).

## 14.7 Known deviations from a stock experience

- No Lava OTA, no stock recovery images, no way back without vendor firmware.
- Play Integrity / banking apps fail (unlocked bootloader + test-keys).
- Some MediaTek extras (e.g. `v3avpud`, MTK thermal) run but have no UI.
- Root: `phh-su` works; Magisk modules/Zygisk unstable (`docs/10.7`).
