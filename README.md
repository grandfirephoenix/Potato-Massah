# Potato Massah (`v1.4.7`)

[![Version](https://img.shields.io/badge/version-v1.4.7-38BDF8?style=flat-square)](https://github.com/grandfirephoenix/Potato-Massah/releases/latest)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11%20(64--bit)-152433?style=flat-square)](#installation--compilation)
[![Engine](https://img.shields.io/badge/AutoHotkey-v2.0%20U64-F59E0B?style=flat-square)](#running-or-compiling-from-source)
[![License](https://img.shields.io/badge/license-PolyForm%20Noncommercial%201.0.0-34D399?style=flat-square)](License.md)

**Hardware Volume Wheel, 1-Click MIDI Learn, Submix Layers, Shift-Locked Monitoring Synchro Delay & Automation Suite for VoiceMeeter Potato.**

> **[Try the Live Interactive Control Panel & Floating HUD Simulator →](https://grandfirephoenix.github.io/Potato-Massah/)**

---

## Overview

**Potato Massah** is a lightweight, 64-bit AutoHotkey v2 companion utility that takes over your hardware volume wheel (`Volume_Up`, `Volume_Down`, `Volume_Mute`) and drives `VoicemeeterRemote64.dll` and `winmm.dll` MIDI directly—suppressing the bulky Windows volume flyout while delivering **20 ms smooth fader glide**, **per-bus submix layers**, **Shift-locked speaker sync delay**, **5-stage sidechain auto-ducking**, **momentary Push-to-Talk**, **Windows default audio device anti-hijack**, and an **always-topmost Floating Pop-Up HUD**.

All settings, custom channel labels, MIDI mappings, mixer snapshots, automation rules, and custom shortcuts persist automatically in a portable `volume_settings.ini` file beside the executable.

---

## Key Features

### 1. Exponential Volume Wheel & 20 ms Smooth Glide
* **Adaptive Velocity Curve:** Single slow clicks trim by **0.2 dB** for surgical control; rapid wheel spins accelerate smoothly up to **4.5 dB per notch**.
* **20 ms Interpolation Loop:** Drives `VoicemeeterRemote64.dll` with smooth fader gliding and instant direction-reversal braking so reversing wheel direction never overshoots.
* **Single-Target & Multi-Group Modes:** Control one strip/bus at a time (`◉ Single`) or link multiple channels together (`◎ Group`) with spread-locked `-60.0 dB` to `+12.0 dB` bounds.

### 2. Always-Topmost Floating Pop-Up HUD (`VMHeadUnitOSD`)
* **Top-Most Z-Order Lock:** Uses `SetWindowPos` (`HWND_TOPMOST` + `SWP_NOACTIVATE`) so the bottom-center HUD stays cleanly above Windows 11 File Explorer, browsers, and borderless games without stealing window focus.
* **Context-Aware Telemetry:** Displays active channel name(s), live dB readout, mute state, submix bus target, active Solo FX parameter, or MIDI encoder/pad feedback.

### 3. Pro Drawer: Per-Bus Submix Layers, Sync Delay, Routing & Snapshots
* **Per-Bus Submix Gain Layers (`GainLayer[0..7]`):** Cycle any input strip between **Master Gain** and independent submix levels for **A1–A5** and **B1–B3** (`Ctrl + Shift + Up/Down` or click/right-click the Layer pill).
* **Shift-Locked Monitoring Synchro Delay (`Option.delay[0..4]`, `0–500 ms`):**
  * Select any hardware output bus (**A1–A5**) in Single-Target mode with the **Pro** drawer open to turn the Pro bar into a live **Sync Delay** controller.
  * **Safety Lock:** Plain scrolling over the bar is blocked to prevent accidental phase drift. Hold **`Shift + Scroll`** for **`±1 ms`** steps, **`Ctrl + Shift + Scroll`** for **`±10 ms`** jumps, or **`Shift + Right-Click`** to reset to **`0 ms`**.
* **Live Output Routing Matrix (`A1–B3`):** Toggle strip bus assignments directly from the Pro drawer.
* **3 Full-Mixer Snapshots (`P1`, `P2`, `P3`):** Right-click `P1–P3` to save all 16 fader gains and `A1–B3` routes; left-click (or use a custom keybind / MIDI pad) to recall instantaneously.

### 4. 1-Click MIDI Learn (`winmm.dll`)
* **Faders & Endless Encoders:** Map physical sliders or knobs with custom **Min/Max dB** bounds, **Absolute (`0–127`)** or **Relative (`+/-`)** encoder modes, and **Linear dB** or **Log Taper** curves.
* **Submixes, Solo FX & Drum Pads:** Bind MIDI CCs to individual `A1–B3` submix layers or strip/bus DSP effects, and map **Note On/Off** drum pads to **Toggle Mute**, **Load Snapshot P1–P3**, or **Momentary Push-to-Talk**.

### 5. Mixing & Mouse Ergonomics
* **Hover-Scroll Any Row:** Point over any channel row and roll your mouse wheel (`±1.0 dB/notch`, or hold **`Shift + Scroll`** for **`±0.2 dB`** fine trim) without changing your active wheel target.
* **Middle-Click Mute & Inline Rename (`✎`):** Middle-click any channel pill to toggle mute; click `✎` (or right-click) to rename any strip or bus.
* **Solo `[S]`, Bus Mono `[M]` & Peak Clip Alerts:** Toggle hardware input PFL Solo (`Strip[i].Solo`), check phase with output bus Mono (`Bus[i].Mono`), and catch debounced `0.0 dBFS` peak clipping without false triggers on idle channels.
* **Context-Aware Solo FX & 3-Band EQ:** Adjust `Comp / Gate / Denoiser / Reverb / Delay / FX1–2` on hardware strips, `3-band EQ` on virtual strips, and `FX Returns` on buses via `Ctrl + Alt + Arrows`.

### 6. Automation & Protection Suite
* **5-Stage Sidechain Auto-Ducking:** Automatically attenuates selected target channels when your mic exceeds a dBFS threshold, featuring **Attack / Hold / Release** envelope shaping, live **dBFS & Gain Reduction** meters, and 4 built-in presets (*Podcast, Gaming, Radio, Tight*).
* **Momentary Push-to-Talk (`PTT`):** Keeps your chosen mic strip muted until your assigned PTT key or MIDI pad is held down.
* **Windows Default Device Lock (`Anti-Hijack`):** Locks Windows Playback and Recording defaults via Core Audio COM so newly plugged USB/HDMI/Bluetooth devices cannot hijack your audio routing.
* **PnP Auto-Reset (`WM_DEVICECHANGE`):** Automatically restarts VoiceMeeter's audio engine `1.8s` after audio hardware reconnects.

---

## Default Keyboard & Mouse Shortcuts

| Action | Default Shortcut | Notes |
| :--- | :--- | :--- |
| **Toggle Control Panel** | `Ctrl + Alt + V` | Shows or hides the main window to the system tray |
| **Hardware Volume Wheel** | `Volume_Up` / `Volume_Down` | `0.2–4.5 dB` exponential `20 ms` smooth fader glide |
| **Hardware Mute Toggle** | `Volume_Mute` | Mutes/unmutes active target(s) and updates tray icon |
| **Target: Previous / Next Channel** | `Ctrl + Shift + Left / Right` | Cycles through all 16 I/O channels in Single-Target mode |
| **Bus Layer: Previous / Next** | `Ctrl + Shift + Up / Down` | Cycles Master Gain and `A1–B3` submix layers (Input Strips) |
| **Sync Delay Adjust (`A1–A5`)** | `Shift + Wheel` / `Ctrl + Shift + Wheel` | Hover Pro Sync Delay bar (`±1 ms` / `±10 ms`); `Shift + R-Click` resets to `0 ms` |
| **Solo FX: Cycle Effect** | `Ctrl + Alt + Left / Right` | Cycles strip DSP chain, 3-band EQ, or bus FX returns |
| **Solo FX: Adjust / Fine / Reset** | `Ctrl + Alt + Up / Down` (`+Shift` / `0`) | Adjusts active FX parameter (`+Shift` for `±0.1`, `0` to reset) |
| **GUI Row Hover-Scroll** | `Wheel` / `Shift + Wheel` | Trims hovered row (`±1.0 dB` or `±0.2 dB` fine) |
| **GUI Row Mute / Rename** | `Middle-Click` / `Right-Click` | Mutes hovered row or opens inline rename dialog |
| **Quick Target: VAIO3 / Mic** | `Shift + 1` / `Shift + 2` | Jumps straight to `Strip[7]` or `Strip[0]` (all 16 channels rebindable) |

---

## Installation & Compilation

### Option A: Standalone `.EXE` Release (Recommended)
1. Ensure **VoiceMeeter Potato** is installed at `C:\Program Files (x86)\VB\Voicemeeter\` on **Windows 10 or Windows 11 (64-bit)**.
2. Download **`Potato Massah.exe`** from the [Latest GitHub Release](https://github.com/grandfirephoenix/Potato-Massah/releases/latest) and place it in its own folder (for example, `C:\Tools\PotatoMassah\`).
3. Launch `Potato Massah.exe`. On first run, it automatically generates `volume_settings.ini` in the same folder to store your configuration.

### Option B: Running or Compiling from Source
1. Install **AutoHotkey v2.0+ (64-bit)** (`AutoHotkey64.exe`).
2. Keep `Potato.ico` in the same directory as `PotatoMassah.ahk` (embedded automatically via `;@Ahk2Exe-SetMainIcon Potato.ico`).
3. To compile a standalone executable, open **Ahk2Exe (`Convert .ahk to .exe`)** and select **`v2.0.x U64 AutoHotkey64.exe`** as the Base File. *(A 64-bit base binary is required so Windows can load `VoicemeeterRemote64.dll`.)*

---

## License & Disclaimer

* **License:** Copyright (c) 2026 Gabriel Harvey — Released under the [PolyForm Noncommercial License 1.0.0](License.md).
* **Disclaimer:** Potato Massah is an independent open-source utility and is not affiliated with or endorsed by VB-Audio Software.
