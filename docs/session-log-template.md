# Session log (template)

Copy this to `session-log.md` (git-ignored) before touching a device. One row per action.
The next agent/human must be able to reconstruct the device state from this file alone.

```text
Date/time:
Device:            <brand model / codename>
Serial:            <keep private, do not commit>
SoC / board:
Android (stock):   <release / SDK / build id>
Vendor SDK:
Slots:             <A/B?>  current=<x>  A bootable=<y>  B bootable=<z>
Firmware available:<yes/url | no>
User confirmed:    [ ] data loss  [ ] warranty  [ ] no stock rollback
```

## Actions

| # | Action | Command | Result | Rollback |
|---|---|---|---|---|
| 1 | inventory | `bash scripts/inventory.sh` | ok | n/a |
| 2 | unlock | `fastboot oem unlock` | unlocked: yes | none |
| 3 | flash system | `fastboot flash system_b …` | OKAY | re-flash known-good image |
| 4 | wipe | `fastboot format:f2fs userdata` | ok | none |
| 5 | vbmeta | `fastboot flash vbmeta_b …` | OKAY | stock vbmeta backup |
| 6 | first boot | `getprop sys.boot_completed` | 1 | — |
| 7 | slot mark | `bootctl mark-boot-successful` | 1 | — |

## Artifacts

| File | Bytes | SHA-256 |
|---|---|---|
| gsi.img | | |
| vbmeta_empty.img | | |
| init_boot_b_stock.img | | |
| init_boot_b_magisk.img | | |

## Deviations from the playbook

<what did not match the docs, and why>

## Final state

<copy the reporting template from AGENTS.md §7>
```

## Notes on discipline

- Log **before** you run a destructive command, not after.
- Record failures too (that is where the value is).
- Redact serial numbers, IMEI, account e-mails before sharing the log.
