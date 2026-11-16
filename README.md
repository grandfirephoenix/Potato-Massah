<div align="center">
  <img src="Potato.ico" alt="Potato Massah" width="84" height="84" />
  <h1>Potato Massah</h1>
  <p><strong>Hardware Volume Wheel, Solo FX Controller, Submix Layer &amp; Automation Controller for VoiceMeeter Potato</strong></p>
  <p>
    <a href="https://grandfirephoenix.github.io/Potato-Massah/"><strong>🌐 Interactive Live Website &amp; Simulator</strong></a>
    &nbsp;•&nbsp;
    <a href="https://github.com/grandfirephoenix/Potato-Massah/releases/latest"><strong>⬇️ Download Standalone .EXE (v1.2.2)</strong></a>
  </p>
</div>

---

### Overview
**Potato Massah** (`v1.2.2`) is a lightweight, dark-mode Windows utility written in 64-bit AutoHotkey v2 that intercepts your hardware media volume keys (`Volume_Up`, `Volume_Down`, `Volume_Mute`) and controls **VoiceMeeter Potato** directly through `VoicemeeterRemote64.dll`—eliminating Windows master volume drift and the default OS volume popup while adding Potato-exclusive submixing, sidechain auto-ducking, and device protection.

### Key Features
* **Exponential Acceleration & 20 ms Smooth Glide:** Slow single-notch ticks adjust by `0.2 dB`, while fast spins accelerate exponentially up to `4.5 dB` per notch with `20 ms` fader interpolation and instant direction-reversal braking.
* **Pro Drawer — Per-Bus Gain Layers (`Strip[i].GainLayer[j]`):** Click **`Pro ▾`** (or press `Ctrl + Shift + Up / Down`) on any Virtual or Hardware Input to switch between **Master Gain** and independent output bus submixes (`A1–A5`, `B1–B3`)—letting you set separate headphone (`A1`) and stream/recording (`B1`) levels.
* **Strip Output Routing Matrix (`A1–B3`) & Mixer Snapshots (`P1–P3`):** Toggle `A1–B3` bus routing live for the selected input strip, save/recall 3 full mixer snapshots (`P1–P3`), or restore defaults with 1-click **`Reset Layers`**, **`Reset Routes`**, and **`Default Mixer`** safety buttons.
* **Sidechain Auto-Ducking Studio:** Monitors your chosen mic with live level (`dBFS`) and gain-reduction (`GR`) meters and smoothly ducks selected channels (or a single bus layer) with configurable **Duck Depth**, **Voice Threshold**, **Attack Speed**, **Hold Time**, **Release Speed**, mute guard, and 4 quick presets (*Podcast*, *Gaming*, *Radio*, *Tight*).
* **Windows Default Device Lock ("Anti-Hijack") & Auto-Reset:** Locks your Windows Playback & Recording defaults so newly plugged-in controllers, headsets, or monitors can't steal audio, and automatically restarts VoiceMeeter's audio engine `1.8s` after a USB/HDMI/Bluetooth audio device reconnects.
* **Solo FX, 3-Band Virtual EQ & Bus Return Navigation:** Cycle and dial in per-channel DSP effects (`Comp`, `Gate`, `Denoiser`, `Reverb`, `Delay`, `FX1/FX2 Sends`, 3-band Virtual EQ, and Bus FX Returns) via `Ctrl + Alt + Arrows` (`Ctrl + Alt + 0` to reset).
* **Full Mouse Control & Inline Mixer Badges:** Hover-scroll any row (`±1.0 dB`, or `Shift + Scroll` for `±0.2 dB`), **middle-click** any row to mute, click **`✎`** (or right-click) to rename **any** Virtual Input, Hardware Input, or Output Bus, and view live dB / `MUTED` badges on every channel.
* **Floating Pop-Up HUD, Startup Automation & Update Checks:** Opaque, click-through bottom-center overlay when the Control Panel isn't focused, optional Windows auto-start, VoiceMeeter auto-launch/minimize, and automatic GitHub release update checks.

### Default Shortcuts
| Action | Default Shortcut |
| :--- | :--- |
| Toggle Control Panel | `Ctrl + Alt + V` |
| Cycle Active Channel (All 16 I/O) | `Ctrl + Shift + Left / Right` |
| Cycle Bus Submix Layer (`Master`, `A1–B3`) | `Ctrl + Shift + Up / Down` |
| Cycle Solo FX / EQ Parameter | `Ctrl + Alt + Left / Right` |
| Adjust Selected Solo FX / EQ | `Ctrl + Alt + Up / Down` (`+ Shift` for `±0.1`) |
| Reset Selected Solo FX / EQ to `0` | `Ctrl + Alt + 0` |
| Hover-Scroll Any Row / Fine Hover-Scroll | `Mouse Wheel` (`±1.0 dB`) / `Shift + Wheel` (`±0.2 dB`) |
| Mute Hovered Channel Row | `Middle-Click` |

### Quick Start
1. Ensure **VoiceMeeter Potato** is installed on Windows 10/11 (64-bit).
2. Download **`Potato Massah.exe`** from the [**Latest Release**](https://github.com/grandfirephoenix/Potato-Massah/releases/latest) (standalone—no AutoHotkey installation required).
3. Press **`Ctrl + Alt + V`** or click the system tray icon to open the Control Panel. All preferences, custom labels, snapshots, and keybinds save automatically to `volume_settings.ini`.

### License
Licensed under the **PolyForm Noncommercial License 1.0.0** — free for personal and noncommercial use; commercial redistribution or resale is prohibited. See [`License.md`](License.md) for full terms.
