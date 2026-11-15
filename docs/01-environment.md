# 01 — PC environment

Everything here runs from a normal user account on Linux. No `sudo` is required for
`adb`, `fastboot`, `debugfs`, Python or image editing. (Some distros need a udev rule for
USB access — see §1.4.)

---

## 1.1 Required tools

| Tool | Why | Install |
|---|---|---|
| `adb`, `fastboot` | talk to the device | [platform-tools](https://developer.android.com/tools/releases/platform-tools) |
| `xz` | decompress GSI | distro package |
| `unzip` | GApps / module zips | distro package |
| `python3` | image injection scripts | distro package |
| `debugfs` | edit ext4 images offline | `e2fsprogs` |
| `e2fsck`, `resize2fs` | grow/repair the image | `e2fsprogs` |
| `avbtool` | build empty vbmeta | AOSP `external/avb` |
| `simg2img` (optional) | convert sparse images | `android-sdk-libsparse-utils` |
| `sha256sum` | verify every artifact | coreutils |

Optional but useful: `lpdump` (from the device) to inspect `super`, `aapt2`/`apkanalyzer`
(from build-tools) to read APK manifests, `ffmpeg`/ImageMagick for wallpapers.

---

## 1.2 Setup script

```bash
export WORK="$HOME/gsi-work"          # 6–10 GB free
mkdir -p "$WORK" && cd "$WORK"

curl -LO https://dl.google.com/android/repository/platform-tools-latest-linux.zip
unzip -q platform-tools-latest-linux.zip
export PATH="$WORK/platform-tools:$PATH"
adb version && fastboot --version

git clone --depth 1 https://android.googlesource.com/platform/external/avb avb
python3 avb/avbtool.py version
```

Add `export PATH="$WORK/platform-tools:$PATH"` to your shell rc so the next session also
works.

---

## 1.3 Disk space budget

| Artifact | Typical size |
|---|---|
| GSI `.img.xz` | 0.6–0.8 GB |
| GSI `.img` decompressed | 2.1–3.0 GB |
| GApps zip | 0.4–1.0 GB |
| Injected image copy | +3 GB |
| Backups (`boot`, `init_boot`, `vbmeta`) | < 100 MB |
| **Total recommended** | **≥ 10 GB free** |

---

## 1.4 USB permissions (udev)

If `fastboot devices` prints nothing while the device is in fastboot, add rules:

```bash
sudo tee /etc/udev/rules.d/51-android.rules >/dev/null <<'EOF'
SUBSYSTEM=="usb", ATTR{idVendor}=="0e8d", MODE="0666", GROUP="plugdev"   # MediaTek
SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", MODE="0666", GROUP="plugdev"   # Google
SUBSYSTEM=="usb", ATTR{idVendor}=="2717", MODE="0666", GROUP="plugdev"   # Xiaomi
SUBSYSTEM=="usb", ATTR{idVendor}=="04e8", MODE="0666", GROUP="plugdev"   # Samsung
EOF
sudo udevadm control --reload-rules && sudo udevadm trigger
```

Check membership: `groups | grep plugdev`.

Use a **data cable** and a rear USB 2.0/3.0 port directly on the PC (no hub) for flashing.
A charge-only cable is the single most common "device not detected" cause.

---

## 1.5 USB ID cheat sheet (what the device is doing)

| ID | Meaning |
|---|---|
| `0e8d:2000` | MediaTek preloader (1–2 s blips during boot loops) |
| `0e8d:201c` | MediaTek LK / bootloader fastboot |
| `18d1:d001` | Android adb (normal boot) |
| `18d1:4ee0` | fastbootd (userspace fastboot) |
| `05c6:9008` | Qualcomm EDL |

If you only see `0e8d:2000` cycling, both slots are probably unbootable — go to
`docs/12-rescue.md`.

---

## 1.6 Sanity checklist before touching a device

- [ ] platform-tools works (`adb version`, `fastboot --version`)
- [ ] ≥ 10 GB free disk
- [ ] the device charges and is detected in at least one mode
- [ ] battery > 40 %
- [ ] OEM firmware availability checked (decides rollback honesty)
- [ ] the user accepted data loss
- [ ] `session-log.md` created with the rollback plan
