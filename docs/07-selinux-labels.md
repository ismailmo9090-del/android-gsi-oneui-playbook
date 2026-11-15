# 07 — SELinux labels inside the system image (the GMS-crash fix)

This is the least obvious and most important step in offline GApps injection.

**Symptom:** the GSI boots, Google apps are installed, but Google Play Services crashes
instantly, Play Store closes, the login screen never appears.
**Logcat:**

```
avc: denied { read } for name="GmsCore.apk" ... scontext=u:r:priv_app:s0 tcontext=u:object_r:unlabeled:s0
```

**Cause:** files written by `debugfs` inherit no SELinux extended attribute. Android labels
them `unlabeled`, and SELinux (enforcing) blocks every reader.
**Fix:** set the `security.selinux` xattr on **every injected file and directory**.

---

## 7.1 Which label to use

| Path | Label |
|---|---|
| `/system/**` (APKs, XML, jars, etc) | `u:object_r:system_file:s0` |
| `/system/**/lib*/**` (shared libraries) | `u:object_r:system_lib_file:s0` |
| `/system/etc/permissions/*` | `u:object_r:system_file:s0` |
| `/system/etc/sysconfig/*` | `u:object_r:system_file:s0` |

For GApps injected under `/system/product` and `/system/system_ext`, `system_file` is
correct; **native libraries under `lib64/` need `system_lib_file`** (GMS `dlopen`s them —
wrong label = crash even though the APK loads).

## 7.2 Applying labels with debugfs

`debugfs` cannot set xattrs by name from a plain command line easily, but `ea_set` takes a
**file containing the raw value**:

```bash
printf 'u:object_r:system_file:s0\0'     > /tmp/sel_system_file
printf 'u:object_r:system_lib_file:s0\0' > /tmp/sel_system_lib_file

debugfs -w -R 'ea_set -f /tmp/sel_system_file "/system/product/priv-app/Phonesky/Phonesky.apk" security.selinux' gsi.img
```

For thousands of files, generate a command file:

```
ea_set -f /tmp/sel_system_file "/system/product/priv-app/GmsCore/GmsCore.apk" security.selinux
ea_set -f /tmp/sel_system_lib_file "/system/product/lib64/libgmscore.so" security.selinux
...
```

then `debugfs -w -f labels.txt gsi.img`.

`scripts/label-selinux.py` walks the injected payload, picks `system_lib_file` for anything
under `lib/` or `lib64/`, and emits the command file.

## 7.3 Verify inside the image

```bash
debugfs -R 'ea_list "/system/product/priv-app/Phonesky/Phonesky.apk"' gsi.img
# security.selinux (25) = "u:object_r:system_file:s0\000"
```

Automated check (must be zero):

```bash
debugfs -R 'ea_list "/system/product/priv-app/Phonesky/Phonesky.apk"' gsi.img 2>/dev/null \
  | grep -c 'system_file'
```

## 7.4 Verify on the device

After flashing and booting:

```bash
adb shell 'ls -Z /system/product/priv-app/Phonesky /system/product/priv-app/GmsCore'
# u:object_r:system_file:s0 ...
adb shell 'ls -Z /system/product/lib64 | head'
# u:object_r:system_lib_file:s0 ...
```

And check that no GMS denial remains:

```bash
adb logcat -d -b all | grep -i 'avc: denied' | grep -iE 'gms|vending|unlabeled'
```

## 7.5 Common mistakes

| Mistake | Result |
|---|---|
| labels only on APKs, not directories | `search` denials on the parent dir |
| `system_lib_file` on APKs | access denied for the app loader |
| labels on files but not `lib64` | GMS starts then dies in `dlopen` |
| forgetting `\0` terminator in the xattr file | label string is wrong / truncated |
| `setenforce 0` as a "fix" | hides the bug, breaks Play Integrity further, not persistent across flash |
| using `restorecon` on the host image | needs a policy; does nothing offline |

## 7.6 Why `unlabeled` was the real cause here

`debugfs write` creates inodes with no `security.selinux` xattr. On a normal system image,
`mke2fs`/`make_ext4fs` applies labels from the build's `file_contexts`. Injecting after the
fact means you must reproduce that step manually. Android does not "restorecon" system
partitions at boot (they are read-only and dm-verified), so the bad label is permanent until
you reflash a corrected image.

The flash-time symptom is subtle: boot succeeds, Play Store opens, then dies at login with
`MissingWebViewPackageException` or a GMS crash loop — both are consequences of broken
labels/WebView selection, not network issues.
