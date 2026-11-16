# Hinglish quickstart (मानव के लिए)

Ye page un logon ke liye hai jo English docs padhna nahi chahte. AI agent se kaam karwa rahe
ho to usse `AGENTS.md` padhne ko bolo — wo poori safety ke saath chalayega.

---

## 1. Sabse pehle: 3 sach

1. **Bootloader unlock = saara data delete.** Photo, WhatsApp, sab jaayega.
2. **Stock ROM wapas milega ya nahi, ye OEM par hai.** Lava/MTK jaise devices me aksar
   public firmware nahi hota — matlab flash ke baad wapas jaana mushkil.
3. **Banking / UPI apps GSI par nahi chalenge.** Play Integrity fail hoti hai.

Ye teen baatein user ko pehle bata do. Uske baad hi aage badho.

---

## 2. Zaroori cheezein

- Windows/Linux PC + **data cable** (charge-only cable se device detect nahi hota)
- Tablet ka battery **40% se zyada**
- PC me **10 GB free space**
- `platform-tools` (adb + fastboot)

---

## 3. Steps (short)

```text
1) Tablet off karo. Volume Down + Power ~10 sec → fastboot mode
2) PC par:  fastboot devices          → serial dikhna chahiye
3) Unlock:  fastboot oem unlock       (kuch devices: fastboot flashing unlock)
4) GSI file download karo (Android 15, arm64-ab, vanilla)
5) fastboot reboot fastboot           → is-userspace: yes hona chahiye
6) fastboot flash system_b gsi.img
7) fastboot erase metadata
8) fastboot format:f2fs userdata      ← space, colon nahi
9) fastboot reboot bootloader
10) vbmeta_empty.img ko vbmeta_b / vbmeta_system_b / vbmeta_vendor_b me flash karo
11) fastboot erase misc ; fastboot erase para ; fastboot --set-active=b
12) fastboot reboot
13) 1–3 min wait. Phir: adb shell getprop sys.boot_completed  → 1
14) adb shell bootctl mark-boot-successful
```

Google apps chahiye? `docs/06` + `docs/07` follow karo (offline image me GApps daalna +
SELinux labels). Ye step skip karoge to Play Store crash karega.

---

## 4. OneUI jaisa look (bina root)

```bash
adb install -r Lawnchair.apk
adb shell cmd package set-home-activity app.lawnchair/app.lawnchair.LawnchairLauncher
adb shell cmd overlay enable-exclusive --category com.android.internal.systemui.navbar.gestural
```

Phir launcher settings me:
- icon pack = OneUI pack
- icons size = chhota (Home screen → Icons)
- grid = 5×5 ya 4×6
- wallpaper = OneUI style

Font badalna hai to `docs/08` (system image me Inter daalna, bina data wipe).

---

## 5. Root (optional, risk)

```text
Magisk → init_boot patch → flash init_boot_b
```

Poora tarika `docs/10` me hai. **Lekin dhyan do:** TrebleDroid/PHH GSI me pehle se `phh-su`
root hota hai, jo Magisk se takraata hai — modules/Zygisk kaam nahi karte. Agar sirf root
chahiye to ROM ka built-in `su` kaafi hai.

---

## 6. Kuch galat ho gaya?

| Problem | Fix |
|---|---|
| `fastboot devices` khaali | cable/port badlo, udev rule lagao |
| sirf `0e8d:2000` dikh raha | bootloop — Power 15–20 s dabao, phir Vol Down+Power |
| recovery me boot ho raha | GSI version mismatch ya data format nahi hua |
| Play Store sign-in par band | `cmd webviewupdate set-webview-implementation com.android.webview` |
| GMS crash | SELinux labels missing — `docs/07` |
| Bluetooth earbuds connect par awaaz speaker se | `adb shell su -c 'setprop persist.bluetooth.system_audio_hal.enabled false'` + reboot — detail `docs/15` |
| Incoming call nahi aati / outgoing me ringback nahi | floss-ims register kar raha hai — uninstall + `flossims` off, detail `docs/16` |
| Call connect hoti hai par awaaz nahi / har baar Speaker dabana | vendor audio policy me Earpiece — patch karna padta hai, `docs/16` |
| boot loop after Magisk | `fastboot flash init_boot_b init_boot_b_stock.img` |

Poori rescue guide: `docs/12-rescue.md`.

---

## 7. Call nahi lag rahi / call me awaaz nahi

Teen alag problem hoti hain, sab **SIM/operator se independent**:

1. **Incoming call kabhi nahi aati**, outgoing jaati hai par ringback nahi: floss-ims
   (`me.phh.ims`) ne IMS register kar liya hai aur MT call handle nahi karta. Wo APK uninstall
   karo, `flossims` overlay off, `persist.sys.phh.ims.floss=false` — phir calls CS/CSFB se
   chalti hain (`docs/16` §16.5).
2. **Call connect nahi hoti** (LTE-only area me): is vendor par koi IMS register nahi kar sakta
   (AIDL radio vs phh ke HIDL-only `ims-mtk-*`). 2G/3G wale area me CS/CSFB se chalti hai.
3. **Call connect hoti hai par awaaz nahi, ya har baar Speaker dabana padta hai**: vendor ka
   audio policy ek "Earpiece" declare karta hai jo tablet me hi nahi hai — `audioserver` crash
   hota hai. Vendor policy se Earpiece ke chaar block hataane padte hain (`docs/16`).

Flash kit wale PC par ek command:

```bash
./call-audio-fix.sh          # vendor patch + CS/CSFB lock + reboot + verify
./call-audio-fix.sh --verify
./call-audio-fix.sh --rollback   # stock vendor wapas
```

Data safe rehta hai (`userdata` touch nahi hota). `flash-lt4901.sh` ye kaam naye tablet par
khud kar deta hai.

## 8. Kya sach me possible nahi

- Samsung Settings, Dialer, Camera, Weather, AOD, Knox → **nahi**
- "Bilkul S25 jaisa" → **nahi**, launcher + icons + font se 80% feel aa jaata hai
- Banking apps → **nahi**
- OEM OTA updates → **nahi**

Jo possible hai wo `docs/11-oneui-look.md` me table ke saath likha hai.
