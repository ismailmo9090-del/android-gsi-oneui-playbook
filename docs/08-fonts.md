# 08 — Replacing the system font with a variable font (Inter)

Goal: everything in the UI renders in a modern font (Inter) without breaking italic,
condensed or handwriting fallbacks.

Verified: Inter 4.x variable (`InterVariable.ttf`, 879,708 bytes) replaced Roboto in the
`sans-serif` family; 9 weight entries patched; UI + settings render correctly.

---

## 8.1 How Android picks fonts

`/system/etc/fonts.xml` defines families:

```xml
<family name="sans-serif">
    <font weight="400" style="normal">Roboto-Regular.ttf
        <axis tag="ital" stylevalue="0" />
        <axis tag="wdth" stylevalue="100" />
        <axis tag="wght" stylevalue="400" />
    </font>
    <font weight="400" style="italic">Roboto-Italic.ttf ...</font>
    ...
</family>
```

A `<font>` entry either names a **static** TTF (one weight) or a **variable** font plus the
axes that select an instance. The axes you declare must **exist inside the font**. Declaring
`ital` on a font that has only `opsz` and `wght` makes the entry invalid → the family falls
back or text disappears.

Inter's variable axes: **`opsz`** and **`wght`** only (no `ital`, no `wdth`).

## 8.2 The rule

For each `style="normal"` entry of `sans-serif`:

1. replace `Roboto-Regular.ttf` with `InterVariable.ttf`
2. **delete** `<axis tag="ital" .../>` and `<axis tag="wdth" .../>` lines
3. **keep** `<axis tag="wght" stylevalue="N" />` (N = the entry's weight: 100…900)

Leave `style="italic"` entries pointing at Roboto (Inter has no italic file in this setup),
and leave `sans-serif-condensed`, `sans-serif-light`, `serif`, `monospace` untouched unless
you have matching files.

## 8.3 Procedure (offline, no wipe)

```bash
# 1. extract the file from the image
debugfs -R 'dump /system/etc/fonts.xml /tmp/fonts.xml' gsi.img
cp gsi.img gsi.font.img

# 2. patch it
python3 scripts/patch-fonts.py \
  --in /tmp/fonts.xml --out /tmp/fonts_inter.xml \
  --family sans-serif --font InterVariable.ttf --styles normal

# 3. write font + patched xml into the image
debugfs -w -R 'write /tmp/InterVariable.ttf /system/fonts/InterVariable.ttf' gsi.font.img
debugfs -w -R 'rm /system/etc/fonts.xml' gsi.font.img
debugfs -w -R 'write /tmp/fonts_inter.xml /system/etc/fonts.xml' gsi.font.img

# 4. labels (see docs/07)
printf 'u:object_r:system_file:s0\0' > /tmp/sel_system_file
debugfs -w -R 'ea_set -f /tmp/sel_system_file "/system/fonts/InterVariable.ttf" security.selinux' gsi.font.img
debugfs -w -R 'ea_set -f /tmp/sel_system_file "/system/etc/fonts.xml" security.selinux' gsi.font.img
```

Flash with `docs/05.7` (system only) — user data and the Google account survive.

## 8.4 Verify

```bash
adb shell 'ls -l /system/fonts/InterVariable.ttf'
adb shell 'grep -c InterVariable /system/etc/fonts.xml'      # 9 on this build
adb shell 'settings get system font_scale'                   # unchanged (1.0)
adb logcat -d | grep -iE 'font|typeface' | grep -iE 'error|fail'
```

Visual check: open Settings, a long list, and bold text (e.g. notification title).

## 8.5 Pitfalls

| Pitfall | Symptom | Fix |
|---|---|---|
| Declaring absent axes | missing/garbled text in some weights | drop `ital`/`wdth` for Inter |
| Replacing italic entries with a variable non-italic font | italics render upright | keep Roboto-Italic |
| Forgetting the `wght` axis | all weights look identical | keep the weight axis |
| Malformed XML | boot loop / UI crash | `python3 -c "import xml.dom.minidom;xml.dom.minidom.parse(...)"` |
| No SELinux label on the new TTF | font silently ignored | `ea_set ... system_file` |
| Replacing `sans-serif-condensed` too | broken narrow UI elements | leave it unless you have the file |

## 8.6 Other fonts

The same method works for any variable font (Roboto Flex, Manrope, Plus Jakarta Sans).
Check the axes first:

```bash
python3 - <<'PY'
from fontTools.ttLib import TTFont
f = TTFont("InterVariable.ttf")
print([(a.axisTag, a.minValue, a.maxValue) for a in f["fvar"].axes])
PY
```

Only declare axes that appear in that list.
