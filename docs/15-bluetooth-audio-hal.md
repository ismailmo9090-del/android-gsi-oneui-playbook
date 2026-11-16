# 15 — Bluetooth audio (A2DP): connected but sound stays on the speaker

**Symptom (the classic one):** the earbuds/headset pairs and shows *Connected* in Settings,
media plays, but the sound comes out of the tablet's speakers. Voice calls often work, so it
looks like "Bluetooth is fine, media is broken".

On MediaTek devices running a TrebleDroid/phh GSI this is **not** an earbuds or settings
problem. It is a **Bluetooth audio HAL provider mismatch**, and it has a one-property fix.

---

## 15.1 The architecture behind it

Since Android 13, the Bluetooth stack does not talk to an audio HAL directly. It asks a
**Bluetooth audio provider** to expose the A2DP session. Two providers can exist:

| Provider | Where it comes from | Who expects it |
|---|---|---|
| `sysbta` (AIDL provider bundled with the GSI) | phh/TrebleDroid system image | pure-AOSP audio HALs |
| `vendor/default` (`MtkBTAudioProviderFactoryAIDL`, `AHAL_ModuleBluetooth`, …) | the OEM vendor partition | the vendor audio HAL (`audio.primary.*`), i.e. **the one this device really uses** |

`AudioFlinger`'s `bluetooth` module is loaded from the **vendor** audio HAL. If the Bluetooth
stack creates its provider session in `sysbta` while the vendor HAL waits for
`vendor/default`, the A2DP software-encoding port is never registered. The audio policy then
cannot make `AUDIO_DEVICE_OUT_BLUETOOTH_A2DP` available and media stays on the speaker.

The provider is chosen by one persistent property:

```text
persist.bluetooth.system_audio_hal.enabled
  true  → sysbta (GSI bundled provider)
  false → vendor/default (OEM provider)
  unset → build default; on TrebleDroid this behaves like "true"
```

## 15.2 The evidence chain (LT4901 + Buds Pro 2R case study)

Before the fix, `adb logcat -b all | grep -Ei 'AHAL|APM|A2DP'` shows, in this order:

```text
AHAL_ModuleBluetooth: createProxy: failed to register BT port
AHAL_BluetoothAudioPort: initSessionType ... A2DP_SOFTWARE_ENCODING_DATAPATH is not ready
APM_AudioPolicyManager: Error -38 while setting AUDIO_DEVICE_OUT_BLUETOOTH_A2DP
AS.AudioDeviceInventory: APM failed to make available A2DP device error=1
AudioSystem-JNI: AudioSystem::setDeviceConnectionState ... -38
```

and routing stays on the speaker:

```text
$ adb shell dumpsys media.audio_flinger | grep -A1 'Output thread'
Output devices: 0x2 (AUDIO_DEVICE_OUT_SPEAKER)
```

After setting the property to `false` and rebooting, the same device shows:

```text
MtkBTAudioProviderFactoryAIDL: getProviderCapabilities / openProvider
MtkBTAudioProviderStub: streamStarted - SessionType=A2DP_SOFTWARE_ENCODING_DATAPATH, status=SUCCESS
AHAL_BluetoothAudioPort: start: session_type=A2DP_SOFTWARE_ENCODING_DATAPATH ... state=STARTED
```

```text
Output devices: 0x80 (AUDIO_DEVICE_OUT_BLUETOOTH_A2DP)     # AudioOut_35
```

```text
$ adb shell dumpsys media.audio_policy | grep 'BT A2DP'
Port ID: 25; "BT A2DP Out"; {AUDIO_DEVICE_OUT_BLUETOOTH_A2DP, @:41:42:1B:6E:BE:13}
```

Zero occurrences of `createProxy failed`, `APM failed`, `not ready` after the fix.

Note the MAC in `dumpsys` may be **redacted as `XX:XX:XX:XX:…`** by the framework; grep on the
device-type token (`AUDIO_DEVICE_OUT_BLUETOOTH_A2DP`) instead of the address when scripting.

## 15.3 Diagnose

```bash
adb shell su -c 'getprop persist.bluetooth.system_audio_hal.enabled'
adb shell dumpsys bluetooth_manager | grep -E 'mConnectionState|mCodecConfig'
adb shell dumpsys media.audio_policy | grep -i 'A2DP'
adb shell dumpsys media.audio_flinger | grep -E 'Output thread|Output devices'
adb logcat -d -b all | grep -cE 'createProxy: failed to register BT port|APM failed to make available A2DP|initSessionType.*not ready'
```

Reading the property needs root (`su -c getprop …`): SELinux denies `shell` direct access to
`persist.bluetooth.*`.

## 15.4 Fix (survives reboot, no re-flash)

```bash
adb shell su -c 'setprop persist.bluetooth.system_audio_hal.enabled false'
adb shell su -c 'am force-stop com.android.bluetooth'   # restart the BT stack
# wait for the earbuds to reconnect (10–90 s), then play something
```

The Bluetooth stack re-reads the property when it restarts, so a full reboot is not
required. Verified on LT4901: `true` → set `false` → `am force-stop com.android.bluetooth`
→ earbuds reconnect → A2DP routed. Also verified with Bluetooth **off**: set `false` → enable
Bluetooth → the stack picks the MTK provider immediately (this is exactly what the flash kit
does right after first boot, when Wi-Fi/Bluetooth are still off). A reboot does the same thing
more deterministically. Because the key starts
with `persist.`, the value is stored in `/data/property` and survives every normal reboot and
any **system-only** re-flash (data is kept).

Revert to the GSI default if you ever want to test `sysbta`:

```bash
adb shell su -c 'setprop persist.bluetooth.system_audio_hal.enabled true'
adb reboot
```

## 15.5 Verify

```bash
# HAL provider (should be the MTK/vendor one, not sysbta)
adb logcat -d -b all | grep -E 'MtkBTAudioProviderFactoryAIDL|AHAL_ModuleBluetooth' | tail -5

# routing while media plays
adb shell dumpsys media.audio_flinger | grep -B2 'AUDIO_DEVICE_OUT_BLUETOOTH_A2DP'
adb shell dumpsys media.audio_policy | grep 'BT A2DP'
adb shell dumpsys bluetooth_manager | grep mCodecConfig   # AAC/SBC/…
```

Healthy output: `streamStarted … SUCCESS`, `state=STARTED`, an output thread with
`0x80 (AUDIO_DEVICE_OUT_BLUETOOTH_A2DP)`, and no `-38`/`createProxy` errors in logcat.

## 15.6 What does *not* work (tested and reverted)

| Attempt | Result |
|---|---|
| `resetprop ro.bluetooth.a2dp_offload.supported` / `a2dp_offload.disabled` | zygote-forked BT app never sees the new `ro.*` value; offload flags are not the issue anyway |
| Bind-mounting a patched `/vendor` lib audio HAL | `/sysbta` never gets loaded; the vendor HAL path is what is used |
| `ro.bluetooth.*` in `/data/local.prop` | `ro.*` is read-only after init; nothing changes at runtime |
| Disabling "HD audio" in earbud settings | forces SBC, still uses the wrong provider → still on speaker |

The property above is the minimal, intended switch. Everything else is fighting the
architecture.

## 15.7 Generic checklist for other devices

1. Does the device have an MTK/Qualcomm **vendor** audio HAL? (`adb shell getprop | grep -i hal`, `dumpsys media.audio_flinger` module list)
2. Does logcat show `sysbta`/`BluetoothAudioProvider` from the **system** partition while the HAL is vendor (`AHAL_ModuleBluetooth`)?
   → set `persist.bluetooth.system_audio_hal.enabled=false`.
3. Does it show `APM failed to make available A2DP device` while the provider is already vendor?
   → check the vendor `audio_policy_configuration.xml` for an A2DP output profile; that is an
   image/vendor fix, not a property fix.
4. Always confirm **during playback**, not at idle: a lingering output thread can still list an
   A2DP device after playback stops.

## 15.8 Automation

The playbook's flash kit applies the property automatically after the first boot
(`flash-lt4901.sh`, step "BT audio"), and ships two small tools for already-flashed tablets:

```bash
./bt-audio-check.sh            # read-only diagnosis (exit 0 = routed/ready)
./bt-audio-check.sh --fix      # apply + restart BT + wait for reconnect
./fix-bt-audio.sh              # wrapper for the above
```

`bt-audio-check.sh` exits `0` routed, `3` no device, `4` not connected, `5` connected but not
routed, `6` fix failed.

For fleets, the kit also ships a **zero-touch watcher** (`auto-fix.sh`) that polls `adb devices`
and fixes any tablet that appears — but only when its property is not already `false`, so a
healthy device is never disturbed (no BT restart, no earbud drop):

```bash
./install-autofix-service.sh     # systemd user service: starts at login, survives reboots
./auto-fix.sh --once             # one-shot for whatever is connected now
./install-autofix-service.sh --status
```

The service log is `auto-fix.log` in the kit folder (rotated at 1 MB). This is how a batch of
already-flashed tablets gets fixed without touching each one by hand: plug the tablet into the
PC, wait ~5 s, done.

Scripting note: with `set -o pipefail`, never use
`printf '%s' "$big" | grep -q …` — `grep -q` exits early, `printf` dies of SIGPIPE (141) and
the pipeline reports failure. Use a here-string (`grep -q … <<< "$big"`) instead.
