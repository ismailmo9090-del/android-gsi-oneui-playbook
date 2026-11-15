# 02 — Device inventory (read-only)

Run this before any write. The goal is to answer six questions:

1. Which Android/SDK is the **vendor** (the ceiling for the GSI)?
2. Is the device A/B or A-only? Which slot is alive?
3. Does it use dynamic partitions (`super`)? How big is `super` and how much is free?
4. Which CPU ABI? (`arm64`, `a64`, `arm`)
5. Does it already have root / a GSI / modules?
6. What can be backed up?

`scripts/inventory.sh` automates all of it; this doc explains the output.

---

## 2.1 Fastboot identity

```bash
fastboot devices
fastboot getvar all 2>&1 | sort          # dump everything once
```

Values that matter:

| Variable | Meaning |
|---|---|
| `is-userspace` | `no` = bootloader, `yes` = fastbootd |
| `current-slot` | `a` / `b` / empty (A-only) |
| `slot-unbootable:a|b` | `yes` = that slot cannot boot |
| `slot-successful:a|b` | `yes` = last boot completed |
| `slot-retry-count:a|b` | remaining attempts before the slot is marked unbootable |
| `unlocked`, `secure` | bootloader state |
| `max-download-size` | usually 128 MB in bootloader mode — logical images are larger, hence fastbootd |
| `battery-voltage` | below ~3.7 V, flashing can loop |

> On some devices `getvar all` leaks the serial number. Redact it before pasting in public.

## 2.2 Android identity

```bash
adb shell getprop | grep -E \
 'ro.product.(board|device|model)|ro.board.platform|ro.build.version.(sdk|release)|ro.vendor.build.version.sdk|ro.treble.enabled|ro.product.cpu.abilist|ro.boot.dynamic_partitions|ro.build.ab_update|ro.boot.slot_suffix'
```

| Field | Use |
|---|---|
| `ro.vendor.build.version.sdk` | **max GSI SDK** (e.g. 35 → Android 15; an Android 16 GSI will usually bootloop) |
| `ro.treble.enabled` | must be `true` for any GSI |
| `ro.product.cpu.abilist` | choose `arm64` / `a64` / `arm` GSI |
| `ro.boot.dynamic_partitions` | `true` → `system` lives in `super` → flash in fastbootd |
| `ro.build.ab_update` | `true` → slot suffix required |

Also useful:

```bash
adb shell getprop ro.product.first_api_level      # shipped Android version
adb shell getprop ro.vndk.version                 # VNDK availability
adb shell getprop ro.board.platform               # SoC family
adb shell getprop ro.boot.verifiedbootstate       # orange = unlocked
```

## 2.3 Partition layout

```bash
adb shell 'ls -l /dev/block/by-name/'             # physical partitions
adb shell 'ls /dev/block/mapper/ 2>/dev/null'     # logical (dynamic) partitions
adb shell 'cat /proc/partitions'
```

Record the presence of:

- `boot_<slot>` — kernel (+ ramdisk on older devices)
- `init_boot_<slot>` — ramdisk only on GKI devices (Android 13+) → **Magisk goes here**
- `vbmeta_<slot>`, `vbmeta_system_<slot>`, `vbmeta_vendor_<slot>`
- `super` — contains system/vendor/product/system_ext/odm
- `metadata`, `misc`, `para`
- **never-touch**: `nvram`, `nvcfg`, `nvdata`, `proinfo`, `protect1/2`, `sec1`, `otp`,
  `preloader_*`, `lk_*`, `md1img`

```bash
# sizes
adb shell 'for p in super boot_b init_boot_b userdata metadata; do
  printf "%-14s " "$p"; blockdev --getsize64 /dev/block/by-name/$p 2>/dev/null || echo n/a; done'
```

## 2.4 How much room does `super` have?

A bigger `system` image only fits if `super` has free space. Estimate:

```bash
adb shell 'df -h /system'          # used by the mounted system
adb shell 'lpdump 2>/dev/null | sed -n "1,60p"'
```

Rule of thumb: injected GApps + font image grew from **2,147,311,616 → 2,936,012,800 bytes**
(+788 MB) on a **9,663,676,416-byte** `super`, with ~4 GB free. If `super` has less than
~500 MB free, strip more GApps (see `docs/06`).

## 2.5 Existing modifications

```bash
adb shell 'getprop ro.build.display.id'                 # treble_* → already a GSI
adb shell 'ls /data/adb/modules 2>/dev/null'            # Magisk modules
adb shell 'which su; ls -l /system/xbin/su /debug_ramdisk/su 2>/dev/null'
adb shell 'pm list packages | grep -iE "magisk|lawnchair|iconify|vector"'
adb shell 'cmd overlay list | grep "\[x\]"'
```

On PHH/TrebleDroid builds `su` exists **before** you install anything — that is the ROM's
built-in `phh-su`, not Magisk. It matters later (`docs/10`).

## 2.6 Backups you can take

With `adb root` (userdebug GSI) or `phh-su`:

```bash
mkdir -p backups
for p in boot_$(getprop ro.boot.slot_suffix | tr -d _) \
         init_boot_$(getprop ro.boot.slot_suffix | tr -d _) \
         vbmeta_$(getprop ro.boot.slot_suffix | tr -d _) ; do
  adb exec-out "dd if=/dev/block/by-name/$p bs=1M 2>/dev/null" > "backups/$p.img"
  sha256sum "backups/$p.img"
done
```

On many OEM devices `adb root` is unavailable and recovery `adb` is broken — then you have
**no partition backup**. Say so explicitly; do not promise one.

## 2.7 Output template

```
Device:        <brand model / codename / SoC / board>
Build:         <display id>  SDK <n>  vendor SDK <n>
Slots:         <a/b>  current=<x>  A bootable=<y>  B bootable=<z>
Partitions:    <super? init_boot? vbmeta count?>
Storage:       <super size / free>, userdata <size> <fs>
ABI:           <abilist>
Mods:          <stock | GSI <name> | root <kind> | modules <list>>
Backups:       <files+sha256 | none>
```
