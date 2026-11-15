# Potato Massah
<div align="center">
  <img src="Potato.ico" alt="Potato Massah" width="84" height="84" />
  <h1>Potato Massah</h1>
  <p><strong>Hardware Volume Wheel &amp; Solo FX Controller for VoiceMeeter Potato</strong></p>
  <p>
    <a href="https://grandfirephoenix.github.io/Potato-Massah/"><strong>🌐 Interactive Live Website &amp; Simulator</strong></a>
    &nbsp;•&nbsp;
    <a href="https://github.com/grandfirephoenix/Potato-Massah/releases/latest"><strong>⬇️ Download Standalone .EXE (v1.0.0)</strong></a>
  </p>
</div>

---

### Overview
**Potato Massah** is a lightweight, dark-mode Windows utility written in 64-bit AutoHotkey v2 that intercepts your hardware media volume keys (`Volume_Up`, `Volume_Down`, `Volume_Mute`) and controls **VoiceMeeter Potato** directly through `VoicemeeterRemote64.dll`—eliminating Windows master volume drift and the default OS volume overlay.

### Key Features
* **Exponential Acceleration & 20 ms Smooth Glide:** Single-notch clicks adjust by `0.2 dB`, while fast spins scale exponentially up to `4.5 dB` per notch with `20 ms` fader interpolation and instant direction-reversal braking.
* **Single-Target & Multi-Group Modes:** Focus on a single strip/bus or link multiple channels together with spread-locked clamping (`-60.0 dB` to `+12.0 dB`) so relative volume balances stay intact.
* **16-Channel Target Cycling:** Step through all 3 Virtual Inputs (`VAIO`, `AUX`, `VAIO3`), 5 Hardware Inputs (`1–5`), and 8 Output Buses (`A1–A5`, `B1–B3`) via `Ctrl + Shift + Left / Right`.
* **Solo FX & EQ Navigation:** Cycle and adjust per-channel DSP effects (`Comp`, `Gate`, `Denoiser`, `Reverb`, `Delay`, `FX1/FX2 Sends`, 3-band Virtual EQ, and Bus FX Returns) using `Ctrl + Alt + Arrows` (`Ctrl + Alt + 0` to reset).
* **Car Head-Unit Pop-Up HUD:** Opaque, click-through bottom-center overlay displaying the active channel, live dB / `MUTED` badge, Solo FX readout, and level meter whenever the Control Panel isn't focused.
* **Hover-Scrolling, Custom Labels & Watchdog:** Scroll over any row inside the Control Panel (`±1.0 dB`, or `Shift + Wheel` for `±0.2 dB`), rename channels (`✎`), rebind all shortcuts in the Keybind Manager, and auto-reconnect if VoiceMeeter restarts.

### Quick Start
1. Make sure **VoiceMeeter Potato** is installed on Windows 10/11 (64-bit).
2. Download **`Potato Massah.exe`** from the [**Latest Release**](https://github.com/grandfirephoenix/Potato-Massah/releases/latest) (no AutoHotkey installation required).
3. Press **`Ctrl + Alt + V`** or click the system tray icon to open the Control Panel. All preferences and custom keybinds save automatically to `volume_settings.ini`.

### License
Licensed under the **PolyForm Noncommercial License 1.0.0** — free for personal and noncommercial use; commercial redistribution or resale is prohibited. See [`License.md`](License.md) for full terms.
