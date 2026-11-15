# 10 — Root: Magisk (and why it fights PHH/TrebleDroid GSIs)

> **Status on the reference device:** Magisk 31.1 boots, `magiskd` runs, and Magisk's `su`
> works. However the TrebleDroid/PHH ROM ships its own root (`phh-su`) which **takes over
> Magisk's ramdisk binary** on later boots, so Magisk's `post-fs-data` / `boot-complete`
> stages stop running and modules (Zygisk, LSPosed/Vector, Iconify) do **not** load reliably.
> Root itself is available through `phh-su`. Read §10.7 before promising modules.

---

## 10.1 Which partition does Magisk patch?

| Android | Boot layout | Magisk target |
|---|---|---|
| ≤ 12 | kernel + ramdisk in `boot` | `boot_<slot>` |
| 13+ (GKI) | kernel in `boot`, **ramdisk in `init_boot`** | `init_boot_<slot>` |

Check first:

```bash
adb shell 'ls /dev/block/by-name/ | grep -E "init_boot|^boot"'
adb shell 'ls -l /dev/block/by-name/init_boot_b'
```

If `init_boot_<slot>` exists → patch it. Patching `boot` on such devices does nothing
useful and can break AVB.

## 10.2 Back up first (mandatory)

```bash
SLOT=$(adb shell getprop ro.boot.slot_suffix | tr -d '\r_')
adb exec-out "dd if=/dev/block/by-name/init_boot_$SLOT bs=1M 2>/dev/null" > init_boot_${SLOT}_stock.img
sha256sum init_boot_${SLOT}_stock.img
```

8 MB, restores in seconds with
`fastboot flash init_boot_b init_boot_b_stock.img`. This is your only rollback for root.

## 10.3 Headless patch (no Magisk app UI)

Magisk's APK contains everything `boot_patch.sh` needs. You can patch on the device over
`adb` without touching the app:

```bash
# host: extract assets from the APK
unzip -q Magisk.apk 'assets/*' 'lib/arm64-v8a/*' -d magisk_x

# device: stage the files
D=/data/local/tmp/mp
adb shell "rm -rf $D; mkdir -p $D"
adb push magisk_x/assets/boot_patch.sh magisk_x/assets/util_functions.sh $D/
adb push magisk_x/lib/arm64-v8a/libmagiskboot.so  $D/magiskboot
adb push magisk_x/lib/arm64-v8a/libmagiskinit.so  $D/magiskinit
adb push magisk_x/lib/arm64-v8a/libmagisk.so      $D/magisk
adb push magisk_x/lib/arm64-v8a/libinit-ld.so     $D/init-ld
adb push magisk_x/lib/arm64-v8a/libbusybox.so     $D/busybox
adb push init_boot_b_stock.img                    $D/init_boot_b.img
adb shell "chmod 755 $D/*"

# device: run the patcher
adb shell 'cd /data/local/tmp/mp && \
  export TMPDIR=/data/local/tmp/mp MAGISKBIN=/data/local/tmp/mp BOOTMODE=true && \
  sh boot_patch.sh init_boot_b.img'

# host: pull the result and flash
adb pull /data/local/tmp/mp/new-boot.img init_boot_b_magisk.img
adb reboot bootloader
fastboot flash init_boot_b init_boot_b_magisk.img
fastboot reboot
```

`boot_patch.sh` prints the repack summary (`HEADER_VER`, `RAMDISK_SZ`, ...); `RC=0` and a
file of the same size (8,388,608 bytes) mean success.

## 10.4 Verify root

```bash
adb shell getprop sys.boot_completed
adb shell 'ps -A | grep magiskd'
adb shell 'su -c id'                       # uid=0(root)
adb shell '/debug_ramdisk/magisk -v'       # 31.1:MAGISK:R
```

Magisk 31.x specifics (important):

- **No interactive su prompt.** Superuser access is granted in the app's **Superuser** tab
  before the app asks. If an app never appears there, it never gets root.
- **No app hiding / repackaging.** Uninstall the app after configuring if you want it hidden.
- **The app is not auto-reinstalled**; keep `Magisk.apk` around.

## 10.5 Installing modules headless

`magisk --install-module` refuses with `Incomplete Magisk install` unless the Magisk
binaries **and** `util_functions.sh` exist in `/data/adb/magisk`:

```bash
adb shell 'su -c "
  mkdir -p /data/adb/magisk
  cp -f /data/local/tmp/mp/{magisk,magiskboot,magiskinit,magiskpolicy,busybox,init-ld} /data/adb/magisk/
  cp -f /data/local/tmp/mp/{util_functions.sh,module_installer.sh} /data/adb/magisk/
  chmod 755 /data/adb/magisk/*
"'
adb push Module.zip /data/local/tmp/Module.zip
adb shell 'su -c "/data/adb/magisk/magisk --install-module /data/local/tmp/Module.zip"'
```

### ⚠️ SELinux label trap (learned the hard way)

Files copied with `cp` from `/data/local/tmp` get `u:object_r:system_file:s0`. Magisk's
`init` exec of `/debug_ramdisk/magisk` then fails:

```
avc: denied { nosuid_transition } for comm="init" scontext=u:r:init:s0
     tcontext=u:r:magisk:s0 tclass=process2
init: cannot execv('/debug_ramdisk/magisk'): Permission denied
```

Result: **every Magisk boot stage silently fails** (no module mount, no Zygisk), while
`magiskd` still runs and `su` still works. Always relabel:

```bash
adb shell 'su -c "
  chcon -R u:object_r:magisk_file:s0 /data/adb/magisk
  chcon u:object_r:magisk_file:s0 /debug_ramdisk/magisk /debug_ramdisk/magiskpolicy /debug_ramdisk/magiskinit
"'
```

Then reboot and confirm in logcat that `** post-fs-data mode running` appears again.

## 10.6 Zygisk

```bash
adb shell 'su -c "/data/adb/magisk/magisk --sqlite \"SELECT * FROM settings\""'
# key=zygisk|value=1
adb shell 'su -c "/data/adb/magisk/magisk --sqlite \"INSERT OR REPLACE INTO settings (key,value) VALUES('"'"'zygisk'"'"',1)\""'
```

After a successful boot: `/debug_ramdisk/.magisk/` exists, Zygisk sets
`ro.dalvik.vm.native.bridge=libzygisk.so`, and module dirs are mounted under
`/debug_ramdisk/.magisk/modules`.

If `ro.dalvik.vm.native.bridge` is missing or `magiskd` logs `nosuid_transition` denials,
Zygisk is **not** loaded — fix §10.5 before installing any Zygisk module.

## 10.7 The PHH/TrebleDroid conflict (read before promising modules)

TrebleDroid, PHH AOSP and many "treble" GSIs ship **root already**:

```
/system/xbin/su        ← phh-su (static, 476 KB)
/system/etc/init/su.rc → service sudaemon /system/bin/phh-su --daemon
```

On these builds, after the first Magisk boot the phh su daemon replaces
`/debug_ramdisk/magisk` with its own binary:

```bash
adb shell 'md5sum /debug_ramdisk/magisk /system/xbin/su'
# identical  ← it is phh-su, not Magisk
adb shell '/debug_ramdisk/magisk -v'
# 17 me.phh.superuser cm-su subind suinit
```

Consequences:

- Magisk's `--post-fs-data` / `--boot-complete` never run again → **modules and Zygisk are
  dead** even though the Magisk app says "installed".
- `su` still works (it is phh-su), so "root works" is an illusion of success.
- `bootloop` counter in Magisk's DB increments; after two boots Magisk enters safe mode and
  disables everything.

Options, in order of reliability:

1. **Use the ROM's built-in root** (`phh-su`) if all you need is root. No modules, no Zygisk.
2. **Remove/disable phh-su before installing Magisk** (unverified on the reference device):
   the binary lives on the read-only `system` partition, so this must be done **offline** in
   the image (`debugfs rm /system/xbin/su /system/xbin/magisk` + remove
   `/system/etc/init/su.rc`) and the image re-flashed. Do this *before* flashing Magisk.
3. **Use a GSI without built-in root** (e.g. a `user` build) and install Magisk on a clean
   ramdisk.
4. **Accept root-only, no modules.** This is what the reference device ended up with.

Do not mix both and expect Zygisk to behave. Any doc that says "just install Magisk and
LSPosed" on a PHH GSI is missing this.

## 10.8 Magisk rollback

```bash
adb reboot bootloader
fastboot flash init_boot_b init_boot_b_stock.img
fastboot reboot
```

If the device bootloops after Magisk: `fastboot flash init_boot_b init_boot_b_stock.img`
in bootloader fastboot fixes it in 30 seconds; data is untouched. If you cannot reach
fastboot, see `docs/12-rescue.md`.

## 10.9 Version notes

| Component | Version used | Constraint |
|---|---|---|
| Magisk | 31.1 | 31.x removed interactive su prompts and app hiding |
| Vector (LSPosed-compatible) | v2.2 canary 3119 | requires working Zygisk |
| LSPosed | 1.9.2 | alternative, same Zygisk requirement |
| Iconify | **7.3.0** | v8 requires Android 16 QPR1+; 12–16 non-QPR must use 7.3.0 |

Iconify is the only realistic "SystemUI → OneUI" customiser; without Zygisk it cannot hook
SystemUI, so treat it as optional.
