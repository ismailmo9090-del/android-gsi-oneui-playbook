# 03 — Bootloader unlock

Unlocking wipes the device and voids warranty. It is the only step with **no rollback**
(the data is gone by design). Confirm it with the user in writing.

---

## 3.1 Entering bootloader / fastboot

Common key combos (device off):

| Vendor family | Combo |
|---|---|
| MediaTek generic | **Volume Down + Power** ~10 s |
| Most Qualcomm | Volume Down + Power, or `adb reboot bootloader` |
| Samsung | Volume Down + Bixby + Power, then confirm |
| Xiaomi | Volume Down + Power (fastboot), unlock via Mi Unlock |
| Pixel | Volume Down + Power |

With a working Android: `adb reboot bootloader` is always safest.
From recovery: `adb reboot fastboot` reaches fastbootd (not bootloader) on many devices.

Verify:

```bash
fastboot devices
fastboot getvar is-userspace     # no
fastboot getvar unlocked         # no  (expected before unlock)
```

## 3.2 Standard unlock

```bash
fastboot flashing unlock
```

The device may show an on-screen confirmation. Use **Volume keys to select "Unlock"**, then
**Power** to confirm. Some devices need OEM unlocking enabled in Developer Options first.

## 3.3 Vendor-specific unlock (MediaTek / Lava / some Chinese OEMs)

If `flashing unlock` returns `Unlock operation is not allowed`:

```bash
fastboot oem unlock
```

Verified on Lava S91 / LT4901: `oem unlock` works while `flashing unlock` is refused.
After it, `getvar unlocked` returns `yes` and `getvar secure` returns `no`.

If `oem unlock` also fails, look for:

```bash
fastboot oem unlock-go
fastboot oem unlock_critical
fastboot flashing unlock_critical
fastboot getvar oem-unlock-support
```

Some OEMs require an account-bound unlock tool (Mi Unlock, realme/OPPO deep testing, Huawei
code). There is no generic workaround; stop and explain.

## 3.4 MediaTek specifics

- The preloader (`0e8d:2000`) appears for 1–2 s during every boot attempt. If you only ever
  see it, the device is in a boot loop — go to `docs/12-rescue.md`.
- BROM/EDL (`0e8d:0003`) is not reliably reachable without a signed DA; `mtkclient` was
  **not** usable on the LT4901 test unit (libusb "Couldn't get device configuration").
  Do not promise BROM recovery.
- Some MTK devices wipe `nvdata`/`nvram` on unlock — that is normal, do not "fix" it.
- `fastboot flashing lock` / relocking after a GSI = **hard brick risk**. Never.

## 3.5 Post-unlock state

```bash
fastboot getvar unlocked           # yes
fastboot getvar secure             # no
fastboot getvar current-slot
adb shell getprop ro.boot.verifiedbootstate   # orange
```

Orange verified-boot state is expected and permanent while unlocked.

## 3.6 Checklist

- [ ] user accepted data wipe + warranty loss
- [ ] `getvar unlocked` = `yes`, `secure` = `no`
- [ ] stock firmware availability documented (for honesty about "no way back")
- [ ] never relock (write it in `session-log.md`)
