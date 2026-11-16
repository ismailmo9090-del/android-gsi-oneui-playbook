# 16 — Voice calls: IMS missing and call audio stuck on the earpiece

**Symptom (the one that looks like a broken modem):** mobile data works, but calls do not
connect at all — or they connect and there is no ring/two-way audio, and the speaker button has
to be pressed for every single call. On a VoLTE-only carrier (Jio, `405/871`) the call never
even reaches the network because the GSI has no working IMS stack.

Two **independent** faults are stacked here. Fixing only one gives the confusing half-state
("calls connect, but I have to press Speaker each time").

| # | Fault | Layer | Effect |
|---|---|---|---|
| 1 | MediaTek IMS service missing / not selected | GSI + TrebleApp | VoLTE calls never connect (CS fallback does not exist on Jio) |
| 2 | Vendor audio policy declares an **Earpiece** the tablet does not have | vendor `audio_policy_configuration.xml` | `audioserver` crashes on call setup, voice routes nowhere → silence until the user forces Speaker |

Both fixes are **carrier- and SIM-independent**: the policy has no SIM concept, and the MTK IMS
APK is chosen by the vendor radio HAL version, not by the operator. The Jio SIM was only the
test case that exposed it.

---

## 16.1 Root cause 1 — the earpiece that does not exist

A tablet has a speaker, no earpiece. This vendor policy still declares one:

```xml
<attachedDevices>
    <item>Speaker</item>
    <item>Earpiece</item>          <!-- ← removed -->
    ...
</attachedDevices>

<devicePort tagName="Earpiece" type="AUDIO_DEVICE_OUT_EARPIECE" role="sink"> … </devicePort>
<route type="mix" sink="Earpiece" sources="primary output,deep_buffer,voip_rx,Voice Call In"/>
<route type="mix" sink="voice tx" sources="Voice Call In"/>
```

At call setup the policy asks for `AUDIO_DEVICE_OUT_EARPIECE`; the vendor HAL cannot build an
output stream for a route whose sink has no reachable output device, and `audioserver` dies:

```text
connectAudioSourceToSink: a swOutput shall always be associated
  … connectTelephonyRxAudioSource … updateCallRoutingInternal … setPhoneState
```

Three separate declarations must go — removing only one is not enough:

| Removed | If it stays behind |
|---|---|
| `<item>Earpiece</item>` in `attachedDevices` | policy still treats Earpiece as available |
| `<devicePort tagName="Earpiece" …>` | MediaTek AIDL converter fails: `convertModuleConfigToAidl … BAD_VALUE` |
| `<route … sink="Earpiece" …>` | voice/`voip_rx` streams target a dead port |
| `<route type="mix" sink="voice tx" sources="Voice Call In"/>` | uplink (mic) has no matching sink after the earpiece route is gone |

`Speaker` stays the `defaultOutputDevice`, so every call (and VoIP) comes out of the speaker
automatically — no button press, no per-app setting.

Final policy: **18861 bytes**, `sha256 9c4dd6d8e82f6f5ced6557ac25ef9a4bf7fd458d07bf62227f7c5266a1c1e4b7`
(stock: 19587 bytes, `ae815b685a062a6ec784d38cba3a76e24f48f7c2bd07882cbbfd1888581da121`).

## 16.2 Root cause 2 — no usable MediaTek IMS on a GSI

A GSI ships AOSP telephony but not the OEM IMS implementation. Without it there is no
`ImsService` for the carrier and `com.android.phone` has nothing useful to bind.

The vendor side of this tablet is **AIDL**, not HIDL:

```text
$ adb shell service list | grep -i ims
android.hardware.radio.ims.IRadioIms/slot1
android.hardware.radio.ims.IRadioIms/slot2
vendor.mediatek.hardware.mtkradioex.ims.IMtkRadioExIms/slot1
vendor.mediatek.hardware.mtkradioex.ims.IMtkRadioExIms/slot2
$ adb shell ls /vendor/lib64 | grep -i ims
android.hardware.radio.ims-V2-ndk.so
vendor.mediatek.hardware.mtkradioex.ims-V2-ndk.so
```

phh's published MTK IMS APKs (`ims-mtk-r.apk`, `ims-mtk-s.apk`) are **HIDL-only** — their dex
references `android.hardware.radio@1.0..1.5::IRadio/imsAospSlot*` and nothing AIDL. Installing
them "works" (the app binds as `ImsService`) but every second the log repeats:

```text
E IMS_RILA: getRadioProxy: NoSuchElementException  [SUB0]
I HidlServiceManagement: Trying to get transport of android.hardware.radio@1.0::IRadio/imsAospSlot1
```

…so `com.mediatek.ims` can never register. There is no stock LT4901 firmware dump available to
extract the tablet's own AIDL-era APK. Check the vendor's own daemons too: `volte_imsm_93`,
`volte_stack`, `volte_ua`, `volte_imcb` run from `/vendor/bin` but hold **no SIP socket and no
XFRM/IPsec state** on Airtel (`ip xfrm state` empty, no TCP to port 5060) — they are not
registering either.

**Consequence:** on this vendor the only reliable voice mode is **CS/CSFB with no IMS
registration at all**. Outgoing calls fall back to GSM/WCDMA by themselves; incoming calls arrive
via SGs paging. That state must be protected, because a *registering* IMS stack breaks it (see
§16.5).

## 16.3 Diagnose

```bash
# IMS present / bound?
adb shell pm list packages | grep -i 'mediatek.ims'
adb shell service list | grep -i mtkradioex.ims
adb shell dumpsys telephony.registry | grep -m1 -i ims
adb shell cmd overlay list | grep mtkims          # must be [x]

# IMS-related props
adb shell getprop persist.vendor.vilte_support            # 0 = don't wait for vendor vilte
adb shell getprop persist.sys.phh.disable_voice_call_in    # must be false
adb shell getprop persist.dbg.volte_avail_ovr              # 1 = force the 4G Calling switch

# the audio-policy side
adb shell su -c 'sha256sum /vendor/etc/audio_policy_configuration.xml'
adb shell logcat -d -b all | grep -cE 'connectAudioSourceToSink|convertModuleConfigToAidl'
adb shell dumpsys audio | grep -m1 'Communication device'
```

`dumpsys telephony.registry` on an affected unit shows `mVoiceRegState=1(OUT_OF_SERVICE)` while
data is registered, plus `mImsCallDisconnectCause` noise.

## 16.4 Fix A — patch the vendor audio policy (permanent, survives reboot)

The policy lives inside the **EROFS** `vendor_<slot>` partition, so it cannot be edited in
place. Two options:

1. **Flash the prepared image** (what the kit does) — the partition is byte-identical across
   this firmware, so one patched image serves the whole batch.
2. **Rebuild from the device's own dump** when the vendor build differs.

### Prepared image (LT4901, vendor `AP3A.240905.015.A2`)

```text
partition      vendor_b (fastbootd)      0x18309000 = 405835776 bytes
stock image    f3ad6ad24a4a77965b5a336bc9ade1161d9e33f7a23ceca0f601e992a59b845b
patched image  468bcd2ddd19a9cd3455bf9f3b93335628937a7de842cd0d660015de0e57750a
```

Both images are exactly `405835776` bytes (padded). Flashing is slot-local and **does not touch
`userdata`**:

```bash
adb reboot fastboot
fastboot getvar is-userspace        # yes  (fastbootd)
fastboot getvar current-slot        # b
fastboot flash vendor_b vendor_patched_lt4901.img
fastboot reboot
```

### Rebuild (any other vendor build)

`erofs-utils` 1.9 and the device's own metadata reproduce a bootable image without AVB
hashtree (this device runs `verifiedbootstate=orange`, `dm-verity` off on vendor):

```bash
# 0) backup + identify
adb shell su -c 'dd if=/dev/block/mapper/vendor_b of=/data/local/tmp/vendor_stock.img bs=1M'
adb pull /data/local/tmp/vendor_stock.img
dump.erofs -s vendor_stock.img           # 4096 block, lz4hc, UUID 66151b1b-…
fsck.erofs --extract=root vendor_stock.img

# 1) edit root/etc/audio_policy_configuration.xml  (remove the 4 blocks in §16.1)

# 2) capture SELinux labels + ownership/mode from the *running* device
adb shell su -c "find /vendor -xdev -exec stat -c '%C|%n' {} +"        > labels.txt
adb shell su -c "find /vendor -xdev -exec stat -c '%F|%a|%u|%g|%n' {} +" > meta.txt

# 3) labels.txt → file_contexts ("/vendor/path u:object_r:….s0", regex-escaped)
#    vendor_file_contexts alone is NOT enough: generic /vendor/etc rules come from the
#    platform policy, so a rebuild with only the vendor file_contexts yields "unlabeled".

# 4) apply gid/mode from meta.txt inside fakeroot (vendor uses uid 0, gid 0 or 2000)
fakeroot bash -c 'while IFS="|" read -r t m u g p; do …chown/chmod…; done < meta.txt; \
  mkfs.erofs -zlz4hc,9 -C16384 -T1230768000 --all-time \
    -U 66151b1b-874a-5fd2-a025-a59946b213cb \
    --mount-point=/vendor --file-contexts=labels.fc vendor_patched.img root'

# 5) pad to the partition size and pre-flight *on the device* (kernel compatibility)
truncate -s 405835776 vendor_patched.img
adb push vendor_patched.img /data/local/tmp/
adb shell su -c 'mount -o loop,ro /data/local/tmp/vendor_patched.img /data/local/tmp/vmnt'
# compare all 2480 paths: label + type + mode + uid + gid against the live /vendor
```

`mkfs.erofs` here emits `lz4_0padding compr_cfgs big_pcluster` (needs kernel ≥ 5.13); the LT4901
runs 6.6.x, and the loop-mount pre-flight proves it before anything is flashed.

## 16.5 Fix B — lock the tablet into CS/CSFB (no IMS registration)

Nothing on this vendor can register IMS successfully, so the goal is the opposite of a normal
VoLTE guide: **make sure no IMS stack registers**, then let ordinary CS/CSFB carry the calls.

| Option | Result on LT4901 + GSI |
|---|---|
| `ims-mtk-r.apk` / `ims-mtk-s.apk` (phh) | HIDL-only → `mRadioProxy == null`, never registers. Keep installed as a harmless framework placeholder, do not expect calls from it. |
| **floss-ims `me.phh.ims`** (TCP build) | SIP registers fine (`200 OK`, `setImsRegistrationState registered=true`), **but** outgoing INVITE never gets ACKed, no 180/183 handling, and **incoming calls never arrive** (0 INVITEs). Breaks both directions. |
| floss-ims UDP builds | P-CSCF never answers; no registration at all. |
| vendor `volte_*` daemons | Running, but no SIP socket / no IPsec SAs → not registered. |

**Final recipe** (applied by `call-audio-fix.sh`):

```bash
# 1. remove the only stack that actually registers (floss)
adb shell pm uninstall --user 0 me.phh.ims
adb shell pm disable-user --user 0 me.phh.ims        # belt & braces
adb shell cmd overlay disable me.phh.treble.overlay.flossims_telephony
adb shell su -c 'setprop persist.sys.phh.ims.floss false'

# 2. keep the MTK framework binding (it never registers; calls stay CS)
adb shell cmd overlay enable me.phh.treble.overlay.mtkims_telephony
adb shell settings put global verifier_verify_adb_installs 0
adb install -r -g ims-mtk-r.apk                     # Play Protect otherwise blocks it
```

Why `pm uninstall` and not just disabling: **TrebleApp re-enables the floss overlay at every
boot when `me.phh.ims` is still installed** (`flossims_telephony` string is compiled into
`/system/priv-app/TrebleApp/TrebleApp.apk`, and it re-applies the overlay + `persist.sys.phh.ims.floss=true`).
It is not a UserPrefs toggle you can flip; removing the APK is what stops it.

Keep the audio prop at its default on purpose:

```bash
adb shell getprop persist.sys.phh.disable_voice_call_in   # false (never set true here)
```

`true` is meant for devices whose vendor policy points voice at an input with no PCM path; on
this vendor it destabilises boot audio and does **not** fix call routing.

What those TrebleApp settings do under the hood (`Ims.kt` / `ImsSettings.kt` in
`phhusson/treble_app`) — kept for reference:

| Setting | Action |
|---|---|
| `key_ims_request_network` | `ConnectivityManager.requestNetwork(NET_CAPABILITY_IMS)` so an IMS PDN can come up |
| `key_ims_force_enable_setting` | `persist.dbg.volte_avail_ovr=1`, `persist.dbg.wfc_avail_ovr=1`, `persist.dbg.allow_ims_off=0` |
| install APK | also `setprop persist.vendor.vilte_support 0` |

## 16.6 Verify

```bash
adb shell getprop sys.boot_completed                       # 1
adb shell su -c 'sha256sum /vendor/etc/audio_policy_configuration.xml'   # 9c4dd6d8…
adb shell su -c 'ls -lZ /vendor/etc/audio_policy_configuration.xml'      # vendor_configs_file
adb shell 'grep -c Earpiece /vendor/etc/audio_policy_configuration.xml'  # 0
adb shell 'service check media.audio_policy; service check media.audio_flinger; pidof audioserver'
adb shell logcat -d -b all | grep -cE 'connectAudioSourceToSink|convertModuleConfigToAidl'   # 0
adb shell dumpsys audio | grep -m1 'Communication device'  # type:speaker after a call
```

IMS/CS state (this is the part that protects incoming calls):

```bash
adb shell pm list packages | grep me.phh.ims                 # EMPTY (floss must be gone)
adb shell cmd overlay list | grep -E 'flossims|mtkims'       # [ ] flossims, [x] mtkims
adb shell getprop persist.sys.phh.ims.floss                  # false
adb shell getprop persist.dbg.volte_avail_ovr                # 1
adb shell cat /proc/net/tcp6 | grep -c ':13C4'               # 0 SIP sockets = nothing registered
```

Call proof (after one outgoing + one incoming test):

```bash
adb shell content query --uri content://call_log/calls --projection number:type:duration | tail -2
# type=2 (OUTGOING) with duration>0 and type=1 (INCOMING) with duration>0
adb shell logcat -d -b all | grep -a 'GsmCdmaCallTracker: \[0\] dialGsm'   # MO went CS, not IMS
```

`dumpsys telephony.registry` should show `mVoiceRegState=0(IN_SERVICE)` with
`availableServices=[VOICE,SMS,VIDEO]` on the CS domain — that is the SGs/CSFB registration that
delivers MT calls.

## 16.7 Rollback

`userdata` is untouched by both fixes. To get the stock routing back:

```bash
adb reboot fastboot
fastboot getvar current-slot        # b
fastboot flash vendor_b vendor_stock_lt4901.img
fastboot reboot
# stock policy back: ae815b68… (19587 bytes)
```

The IMS APK and props are harmless on stock policy; remove them only if you want the exact
factory state:

```bash
adb shell pm uninstall com.mediatek.ims
adb shell su -c 'setprop persist.dbg.volte_avail_ovr 0; setprop persist.dbg.wfc_avail_ovr 0'
```

## 16.8 SIM / operator independence (+ other devices)

| Question | Answer |
|---|---|
| Does the vendor patch depend on the SIM? | No — it is a static routing table in the vendor partition. |
| Does the working IMS mode depend on the SIM? | No — no IMS stack can register on this vendor (AIDL radio, HIDL-only APKs). Calls work because they stay on CS/CSFB, which is carrier-independent as long as 2G/3G CS exists. |
| Will Airtel/Vi/BSNL work? | Same policy + same CS/CSFB behaviour; carrier config (`CarrierConfigManager`) varies per MCC/MNC, not the fix. |
| Dual SIM? | Both slots are declared by the same policy (`voice tx` sink removal removes it for both). Slot-local? No, policy is device-wide. |
| After a vendor OTA? | Take a new backup and re-apply the same 4 removals — never flash an old full vendor image. |
| LTE-only area (no 2G/3G)? | CS/CSFB cannot work there. That case needs a real AIDL MTK IMS APK (`com.mediatek.ims` built against `android.hardware.radio.ims.IRadioIms`), which this device has no source for. |

Checklist for a **different** device/ROM with the same symptom:

1. `grep -c Earpiece /vendor/etc/audio_policy_configuration.xml` — any tablet policy that lists
   Earpiece with no earpiece hardware is a candidate.
2. Confirm the crash signature `connectAudioSourceToSink: a swOutput shall always be associated`
   while a call is ringing (that proves it is routing, not the modem).
3. Compare `defaultOutputDevice`; leave it pointing at the real speaker.
4. Verify the vendor partition is not inside a dm-verity/AVB chain before rebuilding it
   (`ro.boot.verifiedbootstate=orange` and empty `vbmeta` in this playbook).

## 16.9 Automation

Kit (`lt4901-flash-kit`):

```bash
./call-audio-fix.sh              # vendor policy patch + CS/CSFB lock + reboot + verify
./call-audio-fix.sh --verify     # read-only, exit 0 = all green
./call-audio-fix.sh --rollback   # stock vendor back
./call-audio-fix.sh --loop       # fleet of already-flashed tablets: plug, fix, unplug, next
```

The flasher runs it automatically at the end of every install (`--no-call-fix` to skip), so the
production line stays: put the tablet in fastboot → `./flash-lt4901.sh --yes --apps --loop`.
`auto-fix.sh` (systemd user service) re-runs a per-boot **call guard** that removes floss-ims and
forces `flossims off / mtkims on / persist.sys.phh.ims.floss=false`, so a tablet that sits on a
desk for weeks cannot silently drift back into the broken IMS-registered state.
The script refuses to flash the vendor image when the tablet's full `vendor_<slot>` hash is not
the known stock build (exit 7), so a mixed batch cannot be corrupted by a blind vendor write.
