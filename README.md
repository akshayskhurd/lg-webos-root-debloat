# LG webOS TV (webOS 4.x / 5.x) — Root & Safe Debloat Guide

A streamlined, tested guide to rooting LG webOS TVs (such as the 2019 UM7300 series on webOS 4.5) and safely debloating them to free up memory and stop background lag.

> [!NOTE]
> **Tested on:** LG 43UM7300PTA running webOS 4.5 (Firmware `05.40.97`, SoC: armv7l).  
> These steps generally apply to webOS 4.0–4.9 and similar models vulnerable to the `faultmanager` exploit.

---

## ⚡ Overview & Performance Gains

Older webOS smart TVs often suffer from low usable RAM (~1 GB total, running at ~95–97% utilization), causing stuttering menus, slow app launches, and background crashes.

This guide helps you:
- Gain persistent **root access** via the Developer Mode `faultmanager` exploit.
- Install **webOS Homebrew Channel** for homebrew apps and tweaks.
- Apply a **100% reversible debloat** (hides unused system bloat, disables 24/7 background browser preloading, turns off ACR / telemetry).
- **RAM freed:** Increases available RAM by **~25–30 MB** (e.g., from ~190 MB to ~212 MB `MemAvailable`), significantly improving overall TV responsiveness.

---

## 📋 Prerequisites

1. **LG Smart TV** connected to your local network (Wi-Fi or Ethernet).
2. **Computer** (macOS, Linux, or Windows with WSL) on the same local network.
3. **LG Developer Account** (free to register at [webostv.developer.lge.com](https://webostv.developer.lge.com/)).
4. **webOS CLI tools** installed on your computer:
   ```bash
   npm install -g @webosose/ares-cli
   ```
5. **Download Homebrew Channel package (`hbchannel.ipk`)**:
   Download the latest release from [webOS Homebrew Channel releases](https://github.com/webosbrew/webos-homebrew-channel/releases):
   ```bash
   curl -L -o hbchannel.ipk https://github.com/webosbrew/webos-homebrew-channel/releases/latest/download/org.webosbrew.hbchannel_0.7.3_all.ipk
   ```

---

## 🚀 Step 1: Install & Set Up Developer Mode

1. On your TV, open the **LG Content Store** and install the **Developer Mode** app.
2. Launch the app and log in with your LG Developer Account credentials.
3. Toggle **Developer Mode** to **ON**.
4. Toggle **Key Server** to **ON**.
5. Note the **6-character passphrase** shown on screen.
6. The TV will prompt to restart; let it reboot.

---

## 🔑 Step 2: Connect from Your Computer

Find your TV's local IP address (e.g. from TV **Settings → Network → Connection** or your router).

1. Register your TV in the CLI:
   ```bash
   ares-setup-device --add tv -i host=<TV_IP> -i port=9922 -i username=prisoner
   ```
2. Retrieve the SSH key using the 6-character passphrase from the Developer Mode app:
   ```bash
   ares-novacom --device tv --getkey
   ```
3. Test your connection:
   ```bash
   ssh -oHostKeyAlgorithms=+ssh-rsa -oPubkeyAcceptedAlgorithms=+ssh-rsa -p 9922 prisoner@<TV_IP> 'id'
   ```
   *(Expected output: `uid=... gid=... groups=...` as user `prisoner`)*

---

## 🔓 Step 3: Gain Root & Install Homebrew Channel

1. Ensure `hbchannel.ipk` is downloaded locally:
   ```bash
   curl -L -o hbchannel.ipk https://github.com/webosbrew/webos-homebrew-channel/releases/latest/download/org.webosbrew.hbchannel_0.7.3_all.ipk
   ```
2. Upload `autoroot.sh` and `hbchannel.ipk` to the TV's `/tmp` directory:
   ```bash
   # Upload files (Dropbear does not have SFTP, stream via SSH)
   ssh -p 9922 prisoner@<TV_IP> 'cat > /tmp/autoroot.sh' < autoroot.sh
   ssh -p 9922 prisoner@<TV_IP> 'cat > /tmp/hbchannel.ipk' < hbchannel.ipk
   ```
3. Run the autoroot exploit:
   ```bash
   ssh -p 9922 prisoner@<TV_IP> 'sh /tmp/autoroot.sh'
   ```
4. Wait until the output prints:
   ```text
   Payload complete
   ```
5. Look at the TV screen: once an on-screen notification confirms the installation, **Homebrew Channel** will appear in your app launcher.

---

## ⚠️ Step 4: Critical Boot-Chain Preservation Rule

> [!WARNING]
> ### 🛑 DO NOT DELETE THE DEVMODE SERVICE DIRECTORY!
> When you are done rooting, you can uninstall the **Developer Mode app** from the home screen (Hover over tile → Press Up → Click `X` to remove).
> 
> **NEVER manually delete:**  
> `/media/cryptofs/apps/usr/palm/services/com.palmdts.devmode.service/`
> 
> **Why?** The firmware checks and runs `start-devmode.sh` from that directory during every boot to mount `/media/developer` (where Homebrew Channel and root hooks reside). If deleted, your TV will lose root access on restart.

Reboot the TV once (turn off **Quick Start+** in TV Settings or unplug the TV for 30 seconds for a full cold reboot).

---

## 🛡️ Step 5: Verify Root & Harden SSH

After the reboot, open the **Homebrew Channel** app on your TV:
- Go to Homebrew Channel **Settings**.
- Turn **Root status: Elevated** (should be checked).
- Turn **Telnet** ON temporarily to verify root access.

### Access Root via Telnet
From your computer terminal:
```bash
telnet <TV_IP>
# Or via netcat on macOS:
nc <TV_IP> 23
```
Run:
```bash
id
# Expected output: uid=0(root) gid=0(root)
```

### Harden Access (Switch to SSH on Port 22)
1. On your computer, generate an SSH key if you don't have one:
   ```bash
   ssh-keygen -t rsa -b 3072 -f ~/.ssh/lg_tv_root
   ```
2. In your root telnet session, install the public key and enable the Dropbear SSH daemon:
   ```bash
   mkdir -p /home/root/.ssh
   echo "YOUR_PUBLIC_KEY_CONTENT_HERE" >> /home/root/.ssh/authorized_keys
   chmod 700 /home/root/.ssh
   chmod 600 /home/root/.ssh/authorized_keys
   touch /var/luna/preferences/webosbrew_sshd_enabled
   ```
3. Reboot the TV. Now verify you can log in directly via SSH as root:
   ```bash
   ssh -i ~/.ssh/lg_tv_root root@<TV_IP>
   ```
4. Once SSH works, disable Telnet for security:
   ```bash
   touch /var/luna/preferences/webosbrew_telnet_disabled
   ```

---

## 🧹 Step 6: Safe & Reversible Debloat

This debloat method **does not delete system partitions or core packages**. Instead, it utilizes webOS's built-in application blocking mechanism and standard preference toggles.

### 1. Hide Unused Bloat Apps
webOS application manager supports hiding apps via `/var/preferences/com.webos.applicationManager/blockedSystemAppList/USA.json` (or your regional code file).

Connect via root SSH and add bloatware/telemetry app IDs to the blocked list:
- ACR / LivePlus trackers: `com.webos.app.acrhdmi2`, `com.webos.app.acroverlay`
- Demo and diagnostics: `com.webos.app.store-demo`, `com.webos.app.sync-demo`, `com.webos.app.factorywin`, `com.webos.app.remoteservice`
- Telemetry client: `cmp-client`

### 2. Disable Always-On Web Browser Preload
By default, webOS keeps the Web Browser preloaded in memory 24/7, consuming precious RAM.
To disable browser preloading:
```bash
# Adjust preload policy so web browser only loads when launched
luna-send -n 1 -f luna://com.webos.service.applicationmanager/setPreloadPolicy '{"preloadBrowser": false}'
```

### 3. Turn Off Ad & Promotion Toggles
Run these commands via root shell to turn off promotional popups and content tracking:
```bash
# Disable home promotion tiles
luna-send -n 1 -f luna://com.webos.settingsservice/setSystemSettings '{"category":"general", "settings":{"homePromotion":"off"}}'

# Disable promotional video playback
luna-send -n 1 -f luna://com.webos.settingsservice/setSystemSettings '{"category":"option", "settings":{"webOSPromotionVideo":"off"}}'

# Disable LivePlus (Automatic Content Recognition / ACR)
luna-send -n 1 -f luna://com.webos.settingsservice/setSystemSettings '{"category":"option", "settings":{"livePlus":"off"}}'
```

### 4. Check Free Memory
Check available memory anytime:
```bash
grep MemAvailable /proc/meminfo
```

---

## 🔄 How to Undo / Restore Defaults

Everything changed above is stored in `/var/` and is fully reversible.

- **To unhide blocked apps:**  
  Remove the blocked apps file or clear the array:
  ```bash
  rm -f /var/preferences/com.webos.applicationManager/blockedSystemAppList/*.json
  ```
- **To re-enable promotions & ACR:**  
  Toggle them back in **Settings → General → Additional Settings** on your TV, or send `{"homePromotion":"on"}`, `{"livePlus":"on"}` via `luna-send`.
- **To restore factory defaults:**  
  A standard **Reset to Initial Settings** from the TV settings menu cleanly restores the TV to factory state.

---

## 🛑 What NOT to Do

- ❌ **Do not delete `com.palmdts.devmode.service`**: This breaks the Homebrew boot chain.
- ❌ **Do not hand-edit `/var/lib/webosbrew/startup.sh`**: Let Homebrew Channel manage this file.
- ❌ **Do not write directly to flash/block devices (`/dev/mmcblk0p*`)**: Modifying raw partitions can permanently brick your TV.
- ❌ **Do not leave unencrypted Telnet open on untrusted networks**: Always set up SSH keys and disable telnet when done.

---

## 💡 Quick Reference Cheat Sheet

| Task | Command |
|---|---|
| **Root SSH Login** | `ssh -i ~/.ssh/lg_tv_root root@<TV_IP>` |
| **Check Available RAM** | `grep MemAvailable /proc/meminfo` |
| **Block LG OTA Updates** | `touch /var/luna/preferences/webosbrew_block_updates` |
| **List Installed Apps** | `luna-send -n 1 -f luna://com.webos.applicationManager/listApps '{}'` |
| **Launch App** | `luna-send -n 1 -f luna://com.webos.service.applicationmanager/launch '{"id":"<app_id>"}'` |
| **Reboot TV cleanly** | `reboot` |

---

## 📜 Credits & References
- [webosbrew.org](https://webosbrew.org/) & [webosbrew GitHub](https://github.com/webosbrew/)
- [throwaway96/faultmanager-autoroot](https://github.com/throwaway96/faultmanager-autoroot)
- [LG webOS Open Source Developer Docs](https://webostv.developer.lge.com/)

---

## 🛠️ Included Tools & Scripts

This repository includes both root-level scripts for the TV and computer-side management tools:

| File | Type | Description |
|---|---|---|
| `webos-debloat.sh` | Shell (TV) | Reversible root debloat script (hides bloat, disables browser preload, turns off ACR). |
| `autoroot.sh` | Shell (TV) | The `faultmanager` privilege escalation script (from throwaway96). |
| `lg-connect.js` | Node.js (PC) | Diagnostic and control link over WebSocket (system info, app list, toasts, app launch). |
| `lg-sweep.js` | Node.js (PC) | Closes non-essential resident background apps on demand to free RAM without root. |
| `lg-bench.js` | Node.js (PC) | Measures launch timing for streaming apps (e.g., Netflix, YouTube). |

*(Note: `hbchannel.ipk` is downloaded directly via [webosbrew releases](https://github.com/webosbrew/webos-homebrew-channel/releases) during Step 3)*

### Using the Node.js Control Tools
1. Install dependencies on your computer:
   ```bash
   npm install
   ```
2. Query system info or control the TV:
   ```bash
   node lg-connect.js ws://<TV_IP>:3000 info
   node lg-connect.js ws://<TV_IP>:3000 apps
   node lg-connect.js ws://<TV_IP>:3000 toast "Hello from PC"
   ```
   *(First run will prompt on your TV screen to allow pairing. The pairing key is automatically saved locally to `.lg-client-key.json`.)*
3. Free background RAM on demand:
   ```bash
   node lg-sweep.js ws://<TV_IP>:3000
   ```
4. Benchmark app launch speeds:
   ```bash
   node lg-bench.js ws://<TV_IP>:3000 netflix,youtube.leanback.v4
   ```
