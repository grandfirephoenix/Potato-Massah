#Requires AutoHotkey v2.0
#SingleInstance Force
InstallKeybdHook()
;@Ahk2Exe-SetMainIcon Potato.ico

; ==============================================================================
; 1. VERSION, VOICEMEETER REMOTE API, DARK THEME & ICON INITIALIZATION
; ==============================================================================
APP_VERSION    := "v1.4.7"
GITHUB_REPO    := "grandfirephoenix/Potato-Massah"
customIconPath := A_ScriptDir "\Potato.ico"
mutedIconPath  := A_ScriptDir "\icon_muted.ico"

dllPath := "C:\Program Files (x86)\VB\Voicemeeter\VoicemeeterRemote64.dll"
hModule := DllCall("LoadLibrary", "Str", dllPath, "Ptr")
if !hModule {
    MsgBox("Could not load VoicemeeterRemote64.dll. Check your VoiceMeeter installation path.")
    ExitApp()
}

pLogin    := DllCall("GetProcAddress", "Ptr", hModule, "AStr", "VBVMR_Login", "Ptr")
pLogout   := DllCall("GetProcAddress", "Ptr", hModule, "AStr", "VBVMR_Logout", "Ptr")
pGetType  := DllCall("GetProcAddress", "Ptr", hModule, "AStr", "VBVMR_GetVoicemeeterType", "Ptr")
pIsDirty  := DllCall("GetProcAddress", "Ptr", hModule, "AStr", "VBVMR_IsParametersDirty", "Ptr")
pGetFloat := DllCall("GetProcAddress", "Ptr", hModule, "AStr", "VBVMR_GetParameterFloat", "Ptr")
pSetFloat := DllCall("GetProcAddress", "Ptr", hModule, "AStr", "VBVMR_SetParameterFloat", "Ptr")
pGetLevel := DllCall("GetProcAddress", "Ptr", hModule, "AStr", "VBVMR_GetLevel", "Ptr")

if (!pLogin || !pLogout || !pGetType || !pIsDirty || !pGetFloat || !pSetFloat) {
    MsgBox("Loaded VoicemeeterRemote64.dll, but could not resolve API functions.")
    ExitApp()
}

DllCall(pLogin)
OnExit(CleanupVM)

CleanupVM(*) {
    SetTimer(GlideStep, 0)
    SetTimer(FlushOwnDirtyFlag, 0)
    SetTimer(WatchdogCheck, 0)
    SetTimer(GuiLiveSyncTick, 0)
    SetTimer(ClearQuickTip, 0)
    SetTimer(HideHeadUnitOsd, 0)
    SetTimer(ForceOsdTopmost, 0)
    SetTimer(HoverLeaveWatch, 0)
    SetTimer(AutoResetEngineCallback, 0)
    SetTimer(AutoDuckTick, 0)
    SetTimer(UpdateDuckLiveMeter, 0)
    SetTimer(EnforceDefaultDevicesSilent, 0)
    SetTimer(EnforceDefaultDevicesLoud, 0)
    SetTimer(WatchPttKey, 0)
    SetTimer(WatchMidiPttHeld, 0)
    CloseMidiDevice()
    RestoreAllDuckedChannels()
    if (hDevNotify)
        DllCall("UnregisterDeviceNotification", "Ptr", hDevNotify)
    DllCall(pLogout)
    DllCall("FreeLibrary", "Ptr", hModule)
}

EnableDarkSystemMenus() {
    try {
        hUx := DllCall("GetModuleHandle", "Str", "uxtheme.dll", "Ptr")
        if !hUx
            hUx := DllCall("LoadLibrary", "Str", "uxtheme.dll", "Ptr")
        if hUx {
            pSetPreferredAppMode := DllCall("GetProcAddress", "Ptr", hUx, "Ptr", 135, "Ptr")
            pFlushMenuThemes     := DllCall("GetProcAddress", "Ptr", hUx, "Ptr", 136, "Ptr")
            if pSetPreferredAppMode
                DllCall(pSetPreferredAppMode, "Int", 2)
            if pFlushMenuThemes
                DllCall(pFlushMenuThemes)
        }
    }
}

ApplyWindowIcon(guiObj) {
    try {
        hIconSm := 0
        hIconLg := 0
        if FileExist(customIconPath) {
            hIconSm := DllCall("LoadImageW", "Ptr", 0, "WStr", customIconPath, "UInt", 1, "Int", 16, "Int", 16, "UInt", 0x10, "Ptr")
            hIconLg := DllCall("LoadImageW", "Ptr", 0, "WStr", customIconPath, "UInt", 1, "Int", 32, "Int", 32, "UInt", 0x10, "Ptr")
        } else if A_IsCompiled {
            hInst := DllCall("GetModuleHandle", "Ptr", 0, "Ptr")
            hIconSm := DllCall("LoadImageW", "Ptr", hInst, "UPtr", 1, "UInt", 1, "Int", 16, "Int", 16, "UInt", 0, "Ptr")
            hIconLg := DllCall("LoadImageW", "Ptr", hInst, "UPtr", 1, "UInt", 1, "Int", 32, "Int", 32, "UInt", 0, "Ptr")
        }
        if hIconSm
            SendMessage(0x0080, 0, hIconSm, guiObj.Hwnd)
        if hIconLg
            SendMessage(0x0080, 1, hIconLg, guiObj.Hwnd)
    }
}

ApplySleekWindowTheme(guiObj, isOsd := false) {
    try {
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", guiObj.Hwnd, "UInt", 20, "Int*", 1, "UInt", 4)
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", guiObj.Hwnd, "UInt", 19, "Int*", 1, "UInt", 4)
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", guiObj.Hwnd, "UInt", 33, "Int*", 2, "UInt", 4)
        if !isOsd {
            DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", guiObj.Hwnd, "UInt", 35, "UInt*", 0x00110D0D, "UInt", 4)
            DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", guiObj.Hwnd, "UInt", 34, "UInt*", 0x00322626, "UInt", 4)
            ApplyWindowIcon(guiObj)
        } else {
            DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", guiObj.Hwnd, "UInt", 34, "UInt*", 0x004A3818, "UInt", 4)
        }
    }
}

IsGuiAlive(g) {
    if !IsObject(g)
        return false
    try {
        return WinExist("ahk_id " g.Hwnd) != 0
    } catch {
        return false
    }
}

ParseFloatOrDefault(rawStr, fallback) {
    cleaned := Trim(String(rawStr))
    return IsNumber(cleaned) ? Float(cleaned) : Float(fallback)
}

EnableDarkSystemMenus()

; ==============================================================================
; 2. CONFIGURATION, EFFECT DEFINITIONS & PERSISTENT STATE
; ==============================================================================
iniPath    := A_ScriptDir "\volume_settings.ini"
isFirstRun := !FileExist(iniPath)

minStep     := 0.2
maxStep     := 4.5
slowMs      := 250.0
fastMs      := 15.0
glideFactor := 0.35

virtualInputs := [
    { param: "Strip[5]", name: "Voicemeeter VAIO" },
    { param: "Strip[6]", name: "Voicemeeter AUX" },
    { param: "Strip[7]", name: "VAIO3" }
]

hardwareInputs := [
    { param: "Strip[0]", name: "Hardware In 1" },
    { param: "Strip[1]", name: "Hardware In 2" },
    { param: "Strip[2]", name: "Hardware In 3" },
    { param: "Strip[3]", name: "Hardware In 4" },
    { param: "Strip[4]", name: "Hardware In 5" }
]

inputStrips := [
    { param: "Strip[0]", idx: 0 }, { param: "Strip[1]", idx: 1 },
    { param: "Strip[2]", idx: 2 }, { param: "Strip[3]", idx: 3 },
    { param: "Strip[4]", idx: 4 }, { param: "Strip[5]", idx: 5 },
    { param: "Strip[6]", idx: 6 }, { param: "Strip[7]", idx: 7 }
]

outputBuses := [
    { param: "Bus[0]", name: "A1" }, { param: "Bus[1]", name: "A2" },
    { param: "Bus[2]", name: "A3" }, { param: "Bus[3]", name: "A4" },
    { param: "Bus[4]", name: "A5" }, { param: "Bus[5]", name: "B1" },
    { param: "Bus[6]", name: "B2" }, { param: "Bus[7]", name: "B3" }
]

allChannels := []
for item in virtualInputs
    allChannels.Push(item)
for item in hardwareInputs
    allChannels.Push(item)
for item in outputBuses
    allChannels.Push(item)

hwEffects := [
    { key: "Comp",     label: "Comp.",    min: 0.0, max: 10.0, step: 0.2, unit: "" },
    { key: "Gate",     label: "Gate",     min: 0.0, max: 10.0, step: 0.2, unit: "" },
    { key: "Denoiser", label: "Denoiser", min: 0.0, max: 10.0, step: 0.2, unit: "" },
    { key: "Reverb",   label: "Reverb",   min: 0.0, max: 10.0, step: 0.2, unit: "" },
    { key: "Delay",    label: "Delay",    min: 0.0, max: 10.0, step: 0.2, unit: "" },
    { key: "Fx1",      label: "FX1 Send", min: 0.0, max: 10.0, step: 0.2, unit: "" },
    { key: "Fx2",      label: "FX2 Send", min: 0.0, max: 10.0, step: 0.2, unit: "" }
]

virtEffects := [
    { key: "EQGain3", label: "EQ Treble", min: -12.0, max: 12.0, step: 0.5, unit: " dB" },
    { key: "EQGain2", label: "EQ Mid",    min: -12.0, max: 12.0, step: 0.5, unit: " dB" },
    { key: "EQGain1", label: "EQ Bass",   min: -12.0, max: 12.0, step: 0.5, unit: " dB" }
]

busEffects := [
    { key: "ReturnReverb", label: "Reverb Return", min: 0.0, max: 10.0, step: 0.2, unit: "" },
    { key: "ReturnDelay",  label: "Delay Return",  min: 0.0, max: 10.0, step: 0.2, unit: "" },
    { key: "ReturnFx1",    label: "FX1 Return",    min: 0.0, max: 10.0, step: 0.2, unit: "" },
    { key: "ReturnFx2",    label: "FX2 Return",    min: 0.0, max: 10.0, step: 0.2, unit: "" }
]

GetChannelEffects(param) {
    if (SubStr(param, 1, 4) = "Bus[")
        return busEffects
    idx := Integer(RegExReplace(param, "\D"))
    return (idx <= 4) ? hwEffects : virtEffects
}

IsInputStrip(param) {
    return (SubStr(param, 1, 6) = "Strip[")
}

defaultNameMap := Map()
nameMap        := Map()

for item in allChannels {
    defaultNameMap[item.param] := item.name
    savedName := IniRead(iniPath, "Names", item.param, "")
    nameMap[item.param] := (savedName != "") ? savedName : item.name
}

hotkeyDefs := [
    { id: "toggleGui",   group: "general", param: "", label: "Toggle Control Panel",      def: "^!v",     fn: (*) => ToggleGui() },
    { id: "pttHold",     group: "general", param: "", label: "Push-to-Talk (Hold Mic)",   def: "",        fn: (*) => OnPttKeyDown() },
    { id: "togglePtt",   group: "general", param: "", label: "Toggle Push-to-Talk Mode",  def: "",        fn: (*) => TogglePushToTalk() },
    { id: "chanPrev",    group: "general", param: "", label: "Target: Previous Channel",  def: "^+Left",  fn: (*) => CycleSoloChannel(-1) },
    { id: "chanNext",    group: "general", param: "", label: "Target: Next Channel",      def: "^+Right", fn: (*) => CycleSoloChannel(1) },
    { id: "layerPrev",   group: "general", param: "", label: "Bus Layer: Previous",       def: "^+Up",    fn: (*) => CycleGainLayer(-1) },
    { id: "layerNext",   group: "general", param: "", label: "Bus Layer: Next",           def: "^+Down",  fn: (*) => CycleGainLayer(1) },
    { id: "fxPrev",      group: "general", param: "", label: "Solo FX: Previous Effect",  def: "^!Left",  fn: (*) => CycleSoloEffect(-1) },
    { id: "fxNext",      group: "general", param: "", label: "Solo FX: Next Effect",      def: "^!Right", fn: (*) => CycleSoloEffect(1) },
    { id: "fxUp",        group: "general", param: "", label: "Solo FX: Increase",         def: "^!Up",    fn: (*) => AdjustSoloEffect(1, false) },
    { id: "fxDown",      group: "general", param: "", label: "Solo FX: Decrease",         def: "^!Down",  fn: (*) => AdjustSoloEffect(-1, false) },
    { id: "fxFineUp",    group: "general", param: "", label: "Solo FX: Fine Increase",    def: "^!+Up",   fn: (*) => AdjustSoloEffect(1, true) },
    { id: "fxFineDown",  group: "general", param: "", label: "Solo FX: Fine Decrease",    def: "^!+Down", fn: (*) => AdjustSoloEffect(-1, true) },
    { id: "fxReset",     group: "general", param: "", label: "Solo FX: Reset to 0",       def: "^!0",     fn: (*) => ResetSoloEffect() },
    { id: "toggleDuck",  group: "general", param: "", label: "Toggle Auto-Ducking",       def: "",        fn: (*) => ToggleAutoDuck() },
    { id: "toggleLock",  group: "general", param: "", label: "Toggle Device Anti-Hijack", def: "",        fn: (*) => ToggleDeviceLock() },
    { id: "snap1",       group: "general", param: "", label: "Load Snapshot P1",          def: "",        fn: (*) => LoadMixerSnapshot(1) },
    { id: "snap2",       group: "general", param: "", label: "Load Snapshot P2",          def: "",        fn: (*) => LoadMixerSnapshot(2) },
    { id: "snap3",       group: "general", param: "", label: "Load Snapshot P3",          def: "",        fn: (*) => LoadMixerSnapshot(3) },
    { id: "snap4",       group: "general", param: "", label: "Load Snapshot P4",          def: "",        fn: (*) => LoadMixerSnapshot(4) }
]

for item in virtualInputs {
    defKey := (item.param = "Strip[7]") ? "+1" : ""
    hotkeyDefs.Push({ id: "target_" item.param, group: "virtual", param: item.param, label: nameMap[item.param], def: defKey, fn: ApplyQuickPreset.Bind(item.param) })
}
for item in hardwareInputs {
    defKey := (item.param = "Strip[0]") ? "+2" : ""
    hotkeyDefs.Push({ id: "target_" item.param, group: "hardware", param: item.param, label: nameMap[item.param], def: defKey, fn: ApplyQuickPreset.Bind(item.param) })
}
for item in outputBuses {
    hotkeyDefs.Push({ id: "target_" item.param, group: "bus", param: item.param, label: nameMap[item.param], def: "", fn: ApplyQuickPreset.Bind(item.param) })
}

keybinds          := Map()
registeredHotkeys := Map()
pttUpHotkey       := ""

for item in hotkeyDefs {
    rawVal := IniRead(iniPath, "Hotkeys", item.id, "__MISSING__")
    if (rawVal = "__MISSING__") {
        if (item.id = "target_Strip[7]")
            rawVal := IniRead(iniPath, "Hotkeys", "preset1", item.def)
        else if (item.id = "target_Strip[0]")
            rawVal := IniRead(iniPath, "Hotkeys", "preset2", item.def)
        else
            rawVal := item.def
    }
    keybinds[item.id] := rawVal
}

savedTargets      := IniRead(iniPath, "Settings", "Targets", "Strip[7]")
exclusiveMode     := Integer(IniRead(iniPath, "Settings", "ExclusiveMode", "1"))
autoResetDevice   := Integer(IniRead(iniPath, "Settings", "AutoResetDevice", "1"))
showWelcomeBanner := Integer(IniRead(iniPath, "Settings", "ShowWelcome", isFirstRun ? "1" : "0"))
showAdvancedPanel := Integer(IniRead(iniPath, "Settings", "ShowAdvanced", "0"))

pttEnabled        := Integer(IniRead(iniPath, "PushToTalk", "Enabled", "0"))
pttMicStrip       := IniRead(iniPath, "PushToTalk", "MicStrip", "Strip[0]")
pttHeldActive     := false

deviceLockEnabled := Integer(IniRead(iniPath, "DeviceLock", "Enabled", "0"))
lockedPlaybackId  := IniRead(iniPath, "DeviceLock", "PlaybackId", "")
lockedPlaybackName:= IniRead(iniPath, "DeviceLock", "PlaybackName", "Not Set")
lockedRecordId    := IniRead(iniPath, "DeviceLock", "RecordId", "")
lockedRecordName  := IniRead(iniPath, "DeviceLock", "RecordName", "Not Set")

duckEnabled       := Integer(IniRead(iniPath, "AutoDuck", "Enabled", "0"))
duckTriggerStrip  := IniRead(iniPath, "AutoDuck", "TriggerStrip", "Strip[0]")
duckTargetsRaw    := IniRead(iniPath, "AutoDuck", "Targets", "Strip[7]")
duckBusLayer      := Integer(IniRead(iniPath, "AutoDuck", "BusLayer", "0"))
duckAmountDb      := Float(IniRead(iniPath, "AutoDuck", "AmountDb", "12.0"))
duckThresholdDb   := Float(IniRead(iniPath, "AutoDuck", "ThresholdDb", "-28.0"))
duckAttackMs      := Integer(IniRead(iniPath, "AutoDuck", "AttackMs", "80"))
duckHoldMs        := Integer(IniRead(iniPath, "AutoDuck", "HoldMs", "400"))
duckReleaseMs     := Integer(IniRead(iniPath, "AutoDuck", "ReleaseMs", "350"))
duckIgnoreMuted   := Integer(IniRead(iniPath, "AutoDuck", "IgnoreMuted", "1"))

duckTargets := []
for item in StrSplit(duckTargetsRaw, ",") {
    t := Trim(item)
    if (t != "")
        duckTargets.Push(t)
}

autoLaunchVM      := Integer(IniRead(iniPath, "Startup", "AutoLaunchVM", "0"))
hideVMOnLaunch    := Integer(IniRead(iniPath, "Startup", "HideVMOnLaunch", "0"))
checkUpdatesStart := Integer(IniRead(iniPath, "Startup", "CheckUpdatesOnStart", "1"))

midiHandle        := 0
midiDeviceIdx     := Integer(IniRead(iniPath, "MIDI", "DeviceIdx", "-1"))
midiLearnArmed    := false
midiHeldPads      := Map()
midiRelStepDb     := 0.25
midiMappings      := Map()

rawMidiMaps := IniRead(iniPath, "MIDI", "Mappings", "")
if (rawMidiMaps != "") {
    for entry in StrSplit(rawMidiMaps, "|") {
        parts := StrSplit(entry, "=")
        if (parts.Length = 2) {
            vals := StrSplit(parts[2], ",")
            if (vals.Length >= 7) {
                midiMappings[parts[1]] := {
                    target: vals[1],
                    type: vals[2],
                    val: vals[3],
                    minDb: ParseFloatOrDefault(vals[4], -60.0),
                    maxDb: ParseFloatOrDefault(vals[5], 0.0),
                    mode: vals[6],
                    curve: vals[7]
                }
            } else if (vals.Length >= 5) {
                midiMappings[parts[1]] := {
                    target: vals[1],
                    type: vals[2],
                    val: vals[3],
                    minDb: ParseFloatOrDefault(vals[4], -60.0),
                    maxDb: ParseFloatOrDefault(vals[5], 0.0),
                    mode: "abs",
                    curve: "lin"
                }
            } else if (vals.Length >= 3) {
                midiMappings[parts[1]] := {
                    target: vals[1],
                    type: vals[2],
                    val: vals[3],
                    minDb: -60.0,
                    maxDb: 0.0,
                    mode: "abs",
                    curve: "lin"
                }
            } else {
                lyr := (vals.Length >= 2 && IsInteger(vals[2])) ? Integer(vals[2]) : 0
                midiMappings[parts[1]] := {
                    target: vals[1],
                    type: (lyr > 0 ? "layer" : "gain"),
                    val: String(lyr),
                    minDb: -60.0,
                    maxDb: 0.0,
                    mode: "abs",
                    curve: "lin"
                }
            }
        }
    }
}

lastAutoReset     := 0
hDevNotify        := 0
duckCurrentOffset := 0.0
duckTargetOffset  := 0.0
duckLastLoudTick  := 0
duckTestUntilTick := 0
duckStageLabel    := "IDLE"
duckBaseGains     := Map()
clippingChannels  := Map()
clipHoldUntil     := Map()
clipStreak        := Map()

activeTargets := []
for item in StrSplit(savedTargets, ",") {
    trimmed := Trim(item)
    if (trimmed != "")
        activeTargets.Push(trimmed)
}
if (activeTargets.Length = 0)
    activeTargets.Push("Strip[7]")

vm := {
    connected:     true,
    gains:         Map(),
    mutes:         Map(),
    layerIndex:    Map(),
    fxIndex:       Map(),
    fxValues:      Map(),
    gliding:       false,
    lastTick:      0,
    lastWriteTick: 0,
    lastDir:       0
}

; ==============================================================================
; 3. SLEEK DARK-MODE CONTROL PANEL GUI, COLOR-CODED PRO DRAWER & TRAY MENU
; ==============================================================================
UpdateTrayIcon(false)

rowVisualMap       := Map()
rowBadgeCache      := Map()
rowStyleCache      := Map()
ctrlHwndToParam    := Map()
hoverZones         := []
hoverCache         := Map()
bodyControls       := []
welcomeControls    := []
advControls        := []
routeBtnMap        := Map()
routeStateCache    := Map()
snapBtnMap         := Map()
currentBodyStartY  := 0
defaultFooterHint  := ""

hoverStyleMap      := Map()
hoverHintMap       := Map()
lastHoverKey       := ""
popupTipActive     := false

AddBodyControl(ctrl, relY) {
    bodyControls.Push({ ctrl: ctrl, relY: relY })
    return ctrl
}

RegisterHoverRow(param, x1, relY1, x2, relY2, ctrls*) {
    hoverZones.Push({ param: param, x1: x1, relY1: relY1, x2: x2, relY2: relY2 })
    for c in ctrls
        ctrlHwndToParam[c.Hwnd] := param
}

RegisterButtonHover(ctrl, baseBg, hoverBg, tipText := "", isMainPanel := true) {
    key := "btn_" ctrl.Hwnd
    hoverStyleMap[ctrl.Hwnd] := {
        key: key,
        ctrls: [ctrl],
        isMain: isMainPanel,
        getBg: (*) => baseBg,
        hoverBg: hoverBg
    }
    if (tipText != "")
        hoverHintMap[key] := tipText
}

RegisterSoloMonoHover(btn, param, isSolo, tipText) {
    key := (isSolo ? "solo_" : "mono_") param
    hoverStyleMap[btn.Hwnd] := {
        key: key,
        ctrls: [btn],
        isMain: true,
        getBg: (*) => isSolo ? (IsStripSoloed(param) ? "423114" : "1C1C26") : (IsBusMono(param) ? "193B4D" : "1C1C26"),
        hoverBg: (*) => isSolo ? (IsStripSoloed(param) ? "57401B" : "2E2614") : (IsBusMono(param) ? "214F66" : "152E38")
    }
    hoverHintMap[key] := tipText
}

CleanupSubGuiHovers() {
    toDelete := []
    for h, item in hoverStyleMap {
        if !item.isMain
            toDelete.Push(h)
    }
    for h in toDelete
        hoverStyleMap.Delete(h)
}

GetChannelRowBg(param, isHover := false) {
    if (clippingChannels.Has(param) && clippingChannels[param])
        return isHover ? "7A1920" : "5C1218"
    if IsTargetActive(param)
        return isHover ? "1B3146" : "152433"
    return isHover ? "1E1E28" : "16161E"
}

RegisterPillHover(param, ctrls*) {
    key := "pill_" param
    entry := {
        key: key,
        ctrls: ctrls,
        isMain: true,
        getBg: (*) => GetChannelRowBg(param, false),
        hoverBg: (*) => GetChannelRowBg(param, true)
    }
    for c in ctrls
        hoverStyleMap[c.Hwnd] := entry
    hoverHintMap[key] := "Target wheel  •  Scroll: ±1 dB (Shift: ±0.2)  •  M-Click: Mute  •  R-Click: Rename"
}

RegisterRouteButtonHover(rBtn, busName, busDesc) {
    rKey := "route_" busName
    hoverStyleMap[rBtn.Hwnd] := {
        key: rKey,
        ctrls: [rBtn],
        isMain: true,
        getBg: (*) => (routeStateCache.Has(busName) && routeStateCache[busName]) ? "332614" : "1A1A22",
        hoverBg: (*) => (routeStateCache.Has(busName) && routeStateCache[busName]) ? "45331B" : "242430"
    }
    hoverHintMap[rKey] := "Toggle " busName " (" busDesc ") routing for selected strip"
}

RegisterSnapshotButtonHover(sBtn, snapIdx) {
    sKey := "snap_" snapIdx
    hoverStyleMap[sBtn.Hwnd] := {
        key: sKey,
        ctrls: [sBtn],
        isMain: true,
        getBg: (*) => (IniRead(iniPath, "Snapshot" snapIdx, "Saved", "0") = "1") ? "261E12" : "1E1E28",
        hoverBg: (*) => (IniRead(iniPath, "Snapshot" snapIdx, "Saved", "0") = "1") ? "382B19" : "282836"
    }
    hoverHintMap[sKey] := "Snapshot P" snapIdx ": Click to load  •  Right-click to save"
}

UpdateSmartFooterHint(hoverKey) {
    static lastHint := ""
    rawHint  := (hoverKey != "" && hoverHintMap.Has(hoverKey)) ? hoverHintMap[hoverKey] : ""
    nextText := IsObject(rawHint) ? rawHint.Call() : ((rawHint != "") ? rawHint : defaultFooterHint)
    nextCol  := (rawHint != "") ? "38BDF8" : "71717A"
    sig := nextText "|" nextCol
    if (sig = lastHint)
        return
    lastHint := sig
    footerHintText.SetFont("s8 Norm c" nextCol)
    footerHintText.Value := nextText
}

OnGuiMouseMove(wParam, lParam, msg, hwnd) {
    global lastHoverKey, popupTipActive
    MouseGetPos(, , &hoverWin, &hoverCtrl, 2)

    if (hoverWin && WinGetClass("ahk_id " hoverWin) = "tooltips_class32")
        return

    newKey := ""
    if (hoverCtrl && hoverStyleMap.Has(hoverCtrl)) {
        item := hoverStyleMap[hoverCtrl]
        newKey := item.key
        if (newKey != lastHoverKey) {
            ResetLastHover()
            lastHoverKey := newKey
            hv := IsObject(item.hoverBg) ? item.hoverBg.Call() : item.hoverBg
            if (hv != "") {
                for c in item.ctrls {
                    try c.Opt("Background" hv)
                }
            }
            if item.isMain {
                UpdateSmartFooterHint(newKey)
            } else if hoverHintMap.Has(newKey) {
                ToolTip(hoverHintMap[newKey])
                popupTipActive := true
            }
            SetTimer(HoverLeaveWatch, 90)
        }
    } else if (lastHoverKey != "") {
        ResetLastHover()
    }
}

ResetLastHover() {
    global lastHoverKey, popupTipActive
    if (lastHoverKey = "")
        return
    for _, item in hoverStyleMap {
        if (item.key = lastHoverKey) {
            bg := item.getBg.Call()
            if (bg != "") {
                for c in item.ctrls {
                    try c.Opt("Background" bg)
                }
            }
            break
        }
    }
    lastHoverKey := ""
    if popupTipActive {
        ToolTip()
        popupTipActive := false
    }
    UpdateSmartFooterHint("")
}

HoverLeaveWatch() {
    MouseGetPos(, , &hoverWin, &hoverCtrl, 2)
    if (hoverWin && WinGetClass("ahk_id " hoverWin) = "tooltips_class32")
        return
    if (!hoverCtrl || !hoverStyleMap.Has(hoverCtrl)) {
        ResetLastHover()
        SetTimer(HoverLeaveWatch, 0)
    }
}

OnGuiMiddleClick(wParam, lParam, msg, hwnd) {
    if (hwnd != settingsGui.Hwnd && DllCall("GetParent", "Ptr", hwnd, "Ptr") != settingsGui.Hwnd)
        return
    param := GetHoveredChannel()
    if (param != "") {
        ToggleSpecificChannelMute(param)
        return 0
    }
}

OnMessage(0x0200, OnGuiMouseMove)
OnMessage(0x0207, OnGuiMiddleClick)

settingsGui := Gui("+AlwaysOnTop -MaximizeBox", "VoiceMeeter Potato Massah")
settingsGui.MarginX := 16
settingsGui.MarginY := 14
settingsGui.BackColor := "0D0D11"
settingsGui.SetFont("s9 cF4F4F5", "Segoe UI")
ApplySleekWindowTheme(settingsGui, false)

; --- Optional First-Run Welcome Card ---
welAccent := settingsGui.AddProgress("x16 y12 w460 h2 Background0D0D11 c38BDF8", 100)
welBg     := settingsGui.AddText("x16 y14 w460 h52 Background13202C", "")
settingsGui.SetFont("s8 Bold c38BDF8", "Segoe UI")
welTitle  := settingsGui.AddText("x26 y19 w380 h16 Background13202C", "WELCOME TO POTATO MASSAH  •  QUICK START")
welClose  := settingsGui.AddText("x414 y18 w54 h18 Center +0x200 Background1B2E3E", "Got it " Chr(0x2715))
welClose.OnEvent("Click", DismissWelcomeBanner)
RegisterButtonHover(welClose, "1B2E3E", "243D52", "Dismiss welcome tips")

settingsGui.SetFont("s8 Norm cD4D4D8", "Segoe UI")
welBody := settingsGui.AddText("x26 y37 w440 h26 Background13202C", "Roll your volume wheel anywhere  •  Hover any row to scroll it (Shift = fine)  •  Middle-click to mute  •  Right-click to rename")

welcomeControls.Push(welAccent, welBg, welTitle, welClose, welBody)

; --- Hero Telemetry Panel ---
heroAccent := settingsGui.AddProgress("x16 y12 w460 h2 Background0D0D11 c38BDF8", 100)
heroBg     := settingsGui.AddText("x16 y14 w460 h166 Background15151C", "")

settingsGui.SetFont("s8 Bold c71717A", "Segoe UI")
heroTitleLbl := settingsGui.AddText("x28 y20 w134 h16 +0x200 Background15151C", "ACTIVE TARGET")

settingsGui.SetFont("s7 Bold cA1A1AA", "Segoe UI")
heroMutePill := settingsGui.AddText("x166 y18 w56 h20 Center +0x200 Background1E1E28", "MUTE")
heroMutePill.OnEvent("Click", (*) => ToggleVMMute())
hoverStyleMap[heroMutePill.Hwnd] := {
    key: "heroMutePill",
    ctrls: [heroMutePill],
    isMain: true,
    getBg: (*) => IsAnyActiveTargetMuted() ? "3A1A20" : "1E1E28",
    hoverBg: (*) => IsAnyActiveTargetMuted() ? "4D222A" : "2A2A38"
}
hoverHintMap["heroMutePill"] := "Mute active target(s)  •  Middle-click any row to mute"

settingsGui.SetFont("s7 Bold cA1A1AA", "Segoe UI")
heroSoloPill := settingsGui.AddText("x228 y18 w56 h20 Center +0x200 Background1E1E28", "SOLO")
heroSoloPill.OnEvent("Click", (*) => ToggleActiveSolo())
hoverStyleMap[heroSoloPill.Hwnd] := {
    key: "heroSoloPill",
    ctrls: [heroSoloPill],
    isMain: true,
    getBg: (*) => IsActiveTargetSoloed() ? "3A2E14" : "1E1E28",
    hoverBg: (*) => IsActiveTargetSoloed() ? "4D3D1B" : "2A2A38"
}
hoverHintMap["heroSoloPill"] := "Solo (PFL) active input strip in headphones"

settingsGui.SetFont("s7 Bold c38BDF8", "Segoe UI")
modePill := settingsGui.AddText("x290 y18 w110 h20 Center +0x200 Background1B2B3A", "◉ Single")
modePill.OnEvent("Click", OnModeToggle)
hoverStyleMap[modePill.Hwnd] := {
    key: "modePill",
    ctrls: [modePill],
    isMain: true,
    getBg: (*) => (exclusiveMode = 1) ? "1B2B3A" : "22222E",
    hoverBg: (*) => (exclusiveMode = 1) ? "23384C" : "2C2C3B"
}
hoverHintMap["modePill"] := "Switch Single-Target or Multi-Group spread-locked mode"

settingsGui.SetFont("s7 Bold cF59E0B", "Segoe UI")
proTogglePill := settingsGui.AddText("x406 y18 w58 h20 Center +0x200 Background261E12", "Pro " Chr(0x25BE))
proTogglePill.OnEvent("Click", ToggleAdvancedPanel)
hoverStyleMap[proTogglePill.Hwnd] := {
    key: "proTogglePill",
    ctrls: [proTogglePill],
    isMain: true,
    getBg: (*) => (showAdvancedPanel = 1) ? "332614" : "261E12",
    hoverBg: (*) => "3F2F18"
}
hoverHintMap["proTogglePill"] := "Toggle Submix Layers, A1–B3 Routing && Snapshots"

settingsGui.SetFont("s10 Bold c38BDF8", "Segoe UI")
statusText := settingsGui.AddText("x28 y42 w436 h20 Background15151C", "")

settingsGui.SetFont("s8 Norm cA1A1AA", "Segoe UI")
heroSubText := settingsGui.AddText("x28 y64 w436 h18 +0x200 Background15151C", "")

; --- Collapsible Advanced Submix, Routing & Snapshots Drawer (Amber Color-Coded) ---
advDivider := settingsGui.AddText("x28 y86 w436 h1 Background332818", "")

settingsGui.SetFont("s8 Bold cF59E0B", "Segoe UI")
advWarnLbl := settingsGui.AddText("x28 y92 w204 h20 +0x200 Background15151C", Chr(0x26A0) " PRO: Submix, Routing && Snapshots")

settingsGui.SetFont("s7 Bold cFBBF24", "Segoe UI")
rstLayersBtn := settingsGui.AddText("x234 y92 w74 h20 Center +0x200 Background261E12", "Reset Layers")
rstLayersBtn.OnEvent("Click", ResetActiveStripLayers)
RegisterButtonHover(rstLayersBtn, "261E12", "382B19", "Reset A1–B3 submix layers on this strip to 0.0 dB")

rstRoutesBtn := settingsGui.AddText("x311 y92 w74 h20 Center +0x200 Background261E12", "Reset Routes")
rstRoutesBtn.OnEvent("Click", ResetActiveStripRoutes)
RegisterButtonHover(rstRoutesBtn, "261E12", "382B19", "Reset strip output routing to A1 only")

rstMixerBtn := settingsGui.AddText("x388 y92 w76 h20 Center +0x200 Background261E12", "Default Mixer")
rstMixerBtn.OnEvent("Click", ResetEntireMixerDefault)
RegisterButtonHover(rstMixerBtn, "261E12", "382B19", "Reset all 16 faders, submix layers && A1 routes")

settingsGui.SetFont("s8 Bold cF59E0B", "Segoe UI")
layerPill := settingsGui.AddText("x28 y116 w436 h22 +0x200 Background221B11", "  ↳  Layer: Master Gain")
layerPill.OnEvent("Click", OnLayerPillClick)
layerPill.OnEvent("ContextMenu", OnLayerPillContextMenu)
hoverStyleMap[layerPill.Hwnd] := {
    key: "layerPill",
    ctrls: [layerPill],
    isMain: true,
    getBg: (*) => IsLayerPillHighlighted() ? "332614" : "221B11",
    hoverBg: (*) => IsLayerPillHighlighted() ? "42311A" : "2E2416"
}
hoverHintMap["layerPill"] := (*) => GetLayerPillHoverHint()

advControls.Push(advDivider, advWarnLbl, rstLayersBtn, rstRoutesBtn, rstMixerBtn, layerPill)

for idx, b in outputBuses {
    xR := 28 + ((idx - 1) * 55)
    settingsGui.SetFont("s8 Bold c71717A", "Segoe UI")
    rBtn := settingsGui.AddText("x" xR " y142 w51 h22 Center +0x200 Background1A1A22", b.name)
    rBtn.OnEvent("Click", ToggleStripBusRoute.Bind(b.name))
    routeBtnMap[b.name] := rBtn
    advControls.Push(rBtn)
    RegisterRouteButtonHover(rBtn, b.name, nameMap[b.param])
}

settingsGui.SetFont("s8 Bold cA1A1AA", "Segoe UI")
snapLbl := settingsGui.AddText("x28 y168 w82 h44 +0x200 Background15151C", "SNAPSHOTS:`n(P1–P4)")
advControls.Push(snapLbl)

Loop 4 {
    sIdx := A_Index
    col := Mod(sIdx - 1, 2)
    row := (sIdx - 1) // 2
    xS := 114 + (col * 176)
    yS := 168 + (row * 24)
    settingsGui.SetFont("s8 Bold cD4D4D8", "Segoe UI")
    sBtn := settingsGui.AddText("x" xS " y" yS " w170 h21 Center +0x200 Background1E1E28", "P" sIdx ": Empty")
    sBtn.OnEvent("Click", LoadMixerSnapshot.Bind(sIdx))
    sBtn.OnEvent("ContextMenu", SaveMixerSnapshot.Bind(sIdx))
    snapBtnMap[sIdx] := sBtn
    advControls.Push(sBtn)
    RegisterSnapshotButtonHover(sBtn, sIdx)
}

; --- Body Section 1: Virtual Inputs ---
settingsGui.SetFont("s8 Bold c71717A", "Segoe UI")
AddBodyControl(settingsGui.AddText("x16 y0 w460 h16 +0x200 Background0D0D11", "VIRTUAL INPUTS"), 0)

relY := 20
for item in virtualInputs {
    active := IsTargetActive(item.param)
    bgHex  := active ? "152433" : "16161E"

    pillBg := AddBodyControl(settingsGui.AddText("x16 y" relY " w394 h26 Background" bgHex, ""), relY)

    settingsGui.SetFont("s9 Bold c" (active ? "38BDF8" : "52525B"), "Segoe UI")
    dotCtrl := AddBodyControl(settingsGui.AddText("x24 y" relY " w14 h26 +0x200 Background" bgHex, active ? "●" : "○"), relY)

    settingsGui.SetFont("s9 " (active ? "Bold cF4F4F5" : "Norm cD4D4D8"), "Segoe UI")
    lblCtrl := AddBodyControl(settingsGui.AddText("x40 y" relY " w230 h26 +0x200 Background" bgHex, nameMap[item.param]), relY)

    settingsGui.SetFont("s8 Norm c52525B", "Segoe UI")
    tagCtrl := AddBodyControl(settingsGui.AddText("x272 y" relY " w56 h26 Right +0x200 Background" bgHex, item.param), relY)

    settingsGui.SetFont("s8 Bold cA1A1AA", "Segoe UI")
    dbCtrl  := AddBodyControl(settingsGui.AddText("x332 y" relY " w70 h26 Right +0x200 Background" bgHex, "0.0 dB"), relY)

    settingsGui.SetFont("s8 Norm cA1A1AA", "Segoe UI")
    renBtn := AddBodyControl(settingsGui.AddText("x414 y" relY " w26 h26 Center +0x200 Background1C1C26", Chr(0x270E)), relY)

    settingsGui.SetFont("s8 Bold cA1A1AA", "Segoe UI")
    rstBtn := AddBodyControl(settingsGui.AddText("x443 y" relY " w33 h26 Center +0x200 Background1C1C26", "0dB"), relY)

    for c in [pillBg, dotCtrl, lblCtrl, tagCtrl, dbCtrl] {
        c.OnEvent("Click", OnTargetClick.Bind(item.param))
        c.OnEvent("ContextMenu", OnRenameChannel.Bind(item.param))
    }
    renBtn.OnEvent("Click", OnRenameChannel.Bind(item.param))
    rstBtn.OnEvent("Click", ResetChannelGain.Bind(item.param))

    rowVisualMap[item.param] := { bg: pillBg, dot: dotCtrl, lbl: lblCtrl, tag: tagCtrl, db: dbCtrl, actBtn: "" }
    RegisterPillHover(item.param, pillBg, dotCtrl, lblCtrl, tagCtrl, dbCtrl)
    RegisterButtonHover(renBtn, "1C1C26", "282836", "Rename " nameMap[item.param])
    RegisterButtonHover(rstBtn, "1C1C26", "282836", "Reset " nameMap[item.param] " to 0.0 dB")
    RegisterHoverRow(item.param, 16, relY - 1, 410, relY + 27, pillBg, dotCtrl, lblCtrl, tagCtrl, dbCtrl)
    relY += 30
}

; --- Body Section 2: Hardware Inputs (with Solo [S] button per strip) ---
settingsGui.SetFont("s8 Bold c71717A", "Segoe UI")
AddBodyControl(settingsGui.AddText("x16 y" (relY + 8) " w460 h16 +0x200 Background0D0D11", "HARDWARE INPUTS"), relY + 8)
relY += 28
for idx, item in hardwareInputs {
    active := IsTargetActive(item.param)
    bgHex  := active ? "152433" : "16161E"
    isLeft := (Mod(idx, 2) = 1)
    xCol   := isLeft ? 16 : 250

    pillBg := AddBodyControl(settingsGui.AddText("x" xCol " y" relY " w144 h26 Background" bgHex, ""), relY)

    settingsGui.SetFont("s9 Bold c" (active ? "38BDF8" : "52525B"), "Segoe UI")
    dotCtrl := AddBodyControl(settingsGui.AddText("x" (xCol + 6) " y" relY " w12 h26 +0x200 Background" bgHex, active ? "●" : "○"), relY)

    settingsGui.SetFont("s9 " (active ? "Bold cF4F4F5" : "Norm cD4D4D8"), "Segoe UI")
    lblCtrl := AddBodyControl(settingsGui.AddText("x" (xCol + 19) " y" relY " w76 h26 +0x200 Background" bgHex, nameMap[item.param]), relY)

    settingsGui.SetFont("s8 Bold cA1A1AA", "Segoe UI")
    dbCtrl  := AddBodyControl(settingsGui.AddText("x" (xCol + 95) " y" relY " w46 h26 Right +0x200 Background" bgHex, "0.0dB"), relY)

    soloRowBtn := AddBodyControl(settingsGui.AddText("x" (xCol + 147) " y" relY " w20 h26 Center +0x200 Background1C1C26", "S"), relY)
    soloRowBtn.SetFont("s7 Bold cA1A1AA")

    renBtn := AddBodyControl(settingsGui.AddText("x" (xCol + 170) " y" relY " w22 h26 Center +0x200 Background1C1C26", Chr(0x270E)), relY)
    renBtn.SetFont("s8 Norm cA1A1AA")

    rstBtn := AddBodyControl(settingsGui.AddText("x" (xCol + 195) " y" relY " w31 h26 Center +0x200 Background1C1C26", "0dB"), relY)
    rstBtn.SetFont("s7 Bold cA1A1AA")

    for c in [pillBg, dotCtrl, lblCtrl, dbCtrl] {
        c.OnEvent("Click", OnTargetClick.Bind(item.param))
        c.OnEvent("ContextMenu", OnRenameChannel.Bind(item.param))
    }
    soloRowBtn.OnEvent("Click", ToggleStripSolo.Bind(item.param))
    renBtn.OnEvent("Click", OnRenameChannel.Bind(item.param))
    rstBtn.OnEvent("Click", ResetChannelGain.Bind(item.param))

    rowVisualMap[item.param] := { bg: pillBg, dot: dotCtrl, lbl: lblCtrl, tag: "", db: dbCtrl, actBtn: soloRowBtn, actType: "solo" }
    RegisterPillHover(item.param, pillBg, dotCtrl, lblCtrl, dbCtrl)
    RegisterSoloMonoHover(soloRowBtn, item.param, true, "Solo (PFL) " nameMap[item.param])
    RegisterButtonHover(renBtn, "1C1C26", "282836", "Rename " nameMap[item.param])
    RegisterButtonHover(rstBtn, "1C1C26", "282836", "Reset " nameMap[item.param] " to 0.0 dB")
    RegisterHoverRow(item.param, xCol, relY - 1, xCol + 144, relY + 27, pillBg, dotCtrl, lblCtrl, dbCtrl)

    if (!isLeft || idx = hardwareInputs.Length)
        relY += 30
}

; --- Body Section 3: Output Buses (with Mono [M] button per bus) ---
settingsGui.SetFont("s8 Bold c71717A", "Segoe UI")
AddBodyControl(settingsGui.AddText("x16 y" (relY + 8) " w460 h16 +0x200 Background0D0D11", "OUTPUT BUSES"), relY + 8)
relY += 28
for idx, item in outputBuses {
    active := IsTargetActive(item.param)
    bgHex  := active ? "152433" : "16161E"
    isLeft := (Mod(idx, 2) = 1)
    xCol   := isLeft ? 16 : 250

    pillBg := AddBodyControl(settingsGui.AddText("x" xCol " y" relY " w144 h26 Background" bgHex, ""), relY)

    settingsGui.SetFont("s9 Bold c" (active ? "38BDF8" : "52525B"), "Segoe UI")
    dotCtrl := AddBodyControl(settingsGui.AddText("x" (xCol + 6) " y" relY " w12 h26 +0x200 Background" bgHex, active ? "●" : "○"), relY)

    settingsGui.SetFont("s9 " (active ? "Bold cF4F4F5" : "Norm cD4D4D8"), "Segoe UI")
    lblCtrl := AddBodyControl(settingsGui.AddText("x" (xCol + 19) " y" relY " w76 h26 +0x200 Background" bgHex, nameMap[item.param]), relY)

    settingsGui.SetFont("s8 Bold cA1A1AA", "Segoe UI")
    dbCtrl  := AddBodyControl(settingsGui.AddText("x" (xCol + 95) " y" relY " w46 h26 Right +0x200 Background" bgHex, "0.0dB"), relY)

    monoRowBtn := AddBodyControl(settingsGui.AddText("x" (xCol + 147) " y" relY " w20 h26 Center +0x200 Background1C1C26", "M"), relY)
    monoRowBtn.SetFont("s7 Bold cA1A1AA")

    renBtn := AddBodyControl(settingsGui.AddText("x" (xCol + 170) " y" relY " w22 h26 Center +0x200 Background1C1C26", Chr(0x270E)), relY)
    renBtn.SetFont("s8 Norm cA1A1AA")

    rstBtn := AddBodyControl(settingsGui.AddText("x" (xCol + 195) " y" relY " w31 h26 Center +0x200 Background1C1C26", "0dB"), relY)
    rstBtn.SetFont("s7 Bold cA1A1AA")

    for c in [pillBg, dotCtrl, lblCtrl, dbCtrl] {
        c.OnEvent("Click", OnTargetClick.Bind(item.param))
        c.OnEvent("ContextMenu", OnRenameChannel.Bind(item.param))
    }
    monoRowBtn.OnEvent("Click", ToggleBusMono.Bind(item.param))
    renBtn.OnEvent("Click", OnRenameChannel.Bind(item.param))
    rstBtn.OnEvent("Click", ResetChannelGain.Bind(item.param))

    rowVisualMap[item.param] := { bg: pillBg, dot: dotCtrl, lbl: lblCtrl, tag: "", db: dbCtrl, actBtn: monoRowBtn, actType: "mono" }
    RegisterPillHover(item.param, pillBg, dotCtrl, lblCtrl, dbCtrl)
    RegisterSoloMonoHover(monoRowBtn, item.param, false, "Mono sum on " nameMap[item.param])
    RegisterButtonHover(renBtn, "1C1C26", "282836", "Rename " nameMap[item.param])
    RegisterButtonHover(rstBtn, "1C1C26", "282836", "Reset " nameMap[item.param] " to 0.0 dB")
    RegisterHoverRow(item.param, xCol, relY - 1, xCol + 144, relY + 27, pillBg, dotCtrl, lblCtrl, dbCtrl)

    if (!isLeft || idx = outputBuses.Length)
        relY += 30
}

; --- Body Section 4: Automation & Protection Quick Toggles ---
AddBodyControl(settingsGui.AddText("x16 y" (relY + 4) " w460 h1 Background22222E", ""), relY + 4)

settingsGui.SetFont("s8 Bold c71717A", "Segoe UI")
AddBodyControl(settingsGui.AddText("x16 y" (relY + 12) " w460 h16 +0x200 Background0D0D11", "AUTOMATION && PROTECTION  (CLICK TO TOGGLE  •  RIGHT-CLICK TO CONFIGURE)"), relY + 12)

relToggle := relY + 32

settingsGui.SetFont("s8 Bold c38BDF8", "Segoe UI")
autoResetPill := AddBodyControl(settingsGui.AddText("x16 y" relToggle " w112 h26 Center +0x200 Background152433", "● Auto-Reset: ON"), relToggle)
autoResetPill.OnEvent("Click", ToggleAutoResetDevice)
hoverStyleMap[autoResetPill.Hwnd] := {
    key: "autoResetPill",
    ctrls: [autoResetPill],
    isMain: true,
    getBg: (*) => (autoResetDevice = 1) ? "152433" : "16161E",
    hoverBg: (*) => (autoResetDevice = 1) ? "1C3247" : "20202C"
}
hoverHintMap["autoResetPill"] := "Auto-restart VM engine when audio gear reconnects"

devLockPill := AddBodyControl(settingsGui.AddText("x132 y" relToggle " w112 h26 Center +0x200 Background16161E", "○ Anti-Hijack: OFF"), relToggle)
devLockPill.OnEvent("Click", ToggleDeviceLock)
devLockPill.OnEvent("ContextMenu", (*) => OpenAntiHijackGui())
hoverStyleMap[devLockPill.Hwnd] := {
    key: "devLockPill",
    ctrls: [devLockPill],
    isMain: true,
    getBg: (*) => (deviceLockEnabled = 1) ? "152433" : "16161E",
    hoverBg: (*) => (deviceLockEnabled = 1) ? "1C3247" : "20202C"
}
hoverHintMap["devLockPill"] := "Lock Windows defaults (R-Click: pick devices)"

duckPill := AddBodyControl(settingsGui.AddText("x248 y" relToggle " w112 h26 Center +0x200 Background16161E", "○ Auto-Duck: OFF"), relToggle)
duckPill.OnEvent("Click", ToggleAutoDuck)
duckPill.OnEvent("ContextMenu", (*) => OpenDuckingGui())
hoverStyleMap[duckPill.Hwnd] := {
    key: "duckPill",
    ctrls: [duckPill],
    isMain: true,
    getBg: (*) => (duckEnabled = 1) ? "152433" : "16161E",
    hoverBg: (*) => (duckEnabled = 1) ? "1C3247" : "20202C"
}
hoverHintMap["duckPill"] := "Sidechain ducking on voice (R-Click: configure)"

pttPill := AddBodyControl(settingsGui.AddText("x364 y" relToggle " w112 h26 Center +0x200 Background16161E", "○ PTT: OFF"), relToggle)
pttPill.OnEvent("Click", TogglePushToTalk)
pttPill.OnEvent("ContextMenu", (*) => OpenPttGui())
hoverStyleMap[pttPill.Hwnd] := {
    key: "pttPill",
    ctrls: [pttPill],
    isMain: true,
    getBg: (*) => (pttEnabled = 1) ? "152433" : "16161E",
    hoverBg: (*) => (pttEnabled = 1) ? "1C3247" : "20202C"
}
hoverHintMap["pttPill"] := "Push-to-Talk mic mute/hold (R-Click: setup)"

; --- Footer Divider, 5 Action Pills & Unified Smart Hint Bar ---
relFoot := relToggle + 34
AddBodyControl(settingsGui.AddText("x16 y" relFoot " w460 h1 Background22222E", ""), relFoot)

relBtn := relFoot + 8

settingsGui.SetFont("s8 Bold cD4D4D8", "Segoe UI")
startupBtn := AddBodyControl(settingsGui.AddText("x16 y" relBtn " w86 h28 Center +0x200 Background191922", "Startup"), relBtn)
startupBtn.OnEvent("Click", (*) => OpenStartupGui())
RegisterButtonHover(startupBtn, "191922", "242432", "Startup, VM auto-launch && GitHub updates")

settingsGui.SetFont("s8 Bold c38BDF8", "Segoe UI")
keybindBtn := AddBodyControl(settingsGui.AddText("x106 y" relBtn " w88 h28 Center +0x200 Background152433", "Keybinds"), relBtn)
keybindBtn.OnEvent("Click", (*) => OpenKeybindGui())
RegisterButtonHover(keybindBtn, "152433", "1C3247", "Edit keyboard shortcuts & PTT key")

settingsGui.SetFont("s8 Bold cF59E0B", "Segoe UI")
midiBtn := AddBodyControl(settingsGui.AddText("x198 y" relBtn " w80 h28 Center +0x200 Background261E12", "MIDI Learn"), relBtn)
midiBtn.OnEvent("Click", (*) => OpenMidiGui())
RegisterButtonHover(midiBtn, "261E12", "382B19", "Bind MIDI sliders, encoders, FX && pads")

settingsGui.SetFont("s8 Bold cD4D4D8", "Segoe UI")
featuresBtn := AddBodyControl(settingsGui.AddText("x282 y" relBtn " w82 h28 Center +0x200 Background191922", "Features"), relBtn)
featuresBtn.OnEvent("Click", (*) => OpenFeaturesGui())
RegisterButtonHover(featuresBtn, "191922", "242432", "Open user manual & live shortcut list")

restartBtn := AddBodyControl(settingsGui.AddText("x368 y" relBtn " w108 h28 Center +0x200 Background191922", "Restart Engine"), relBtn)
restartBtn.OnEvent("Click", RestartAudioEngine)
RegisterButtonHover(restartBtn, "191922", "242432", "Restart VoiceMeeter audio engine")

relHint := relBtn + 34
settingsGui.SetFont("s8 Norm c71717A", "Segoe UI")
footerHintText := AddBodyControl(settingsGui.AddText("x16 y" relHint " w460 h28 Background0D0D11", ""), relHint)

relHide := relHint + 30
settingsGui.SetFont("s8 Bold cA1A1AA", "Segoe UI")
hideBtn := AddBodyControl(settingsGui.AddText("x386 y" relHide " w90 h18 Right +0x200 Background0D0D11", "Hide to Tray"), relHide)
hideBtn.OnEvent("Click", (*) => settingsGui.Hide())
hoverStyleMap[hideBtn.Hwnd] := { key: "hideBtn", ctrls: [hideBtn], isMain: true, getBg: (*) => "0D0D11", hoverBg: (*) => "0D0D11" }
hoverHintMap["hideBtn"] := "Hide window to system tray"

settingsGui.OnEvent("Close", (*) => (settingsGui.Hide(), 1))
settingsGui.OnEvent("Escape", (*) => settingsGui.Hide())

; ==============================================================================
; 4. FLOATING POP-UP HUD (SHOWN WHEN MAIN GUI IS NOT ACTIVE)
; ==============================================================================
osdVisible := false
osdGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 +E0x08000000", "VMHeadUnitOSD")
osdGui.BackColor := "0D0D11"
osdGui.MarginX := 0
osdGui.MarginY := 0
ApplySleekWindowTheme(osdGui, true)

osdAccent := osdGui.AddProgress("x0 y0 w390 h3 Background0D0D11 c38BDF8", 100)

osdGui.SetFont("s11 Bold cF4F4F5", "Segoe UI")
osdChannelText := osdGui.AddText("x16 y11 w256 h22 +0x200 Background0D0D11", "")
osdGui.SetFont("s11 Bold c38BDF8", "Segoe UI")
osdGainText := osdGui.AddText("x274 y11 w100 h22 Right +0x200 Background0D0D11", "")

osdGui.SetFont("s9 Bold cA1A1AA", "Segoe UI")
osdFxLabelText := osdGui.AddText("x16 y37 w268 h18 +0x200 Background0D0D11", "")
osdGui.SetFont("s9 Bold cF4F4F5", "Segoe UI")
osdFxValText := osdGui.AddText("x286 y37 w88 h18 Right +0x200 Background0D0D11", "")

osdMeter := osdGui.AddProgress("x16 y62 w358 h7 Range0-100 Background1E1E28 c38BDF8", 50)

ForceOsdTopmost() {
    global osdVisible
    if (!osdVisible || !IsGuiAlive(osdGui))
        return
    ; HWND_TOPMOST (-1) | SWP_NOSIZE (0x1) | SWP_NOMOVE (0x2) | SWP_NOACTIVATE (0x10) | SWP_SHOWWINDOW (0x40)
    DllCall("SetWindowPos", "Ptr", osdGui.Hwnd, "Ptr", -1, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x0053)
}

ShowHeadUnitOsd(mode := "volume", midiInfo := "") {
    global osdVisible

    if WinActive("ahk_id " settingsGui.Hwnd)
        return

    if (!vm.connected) {
        osdChannelText.Value := "VoiceMeeter Offline"
        osdGainText.Value    := "--"
        osdFxLabelText.Value := "Waiting for VoiceMeeter Potato..."
        osdFxValText.Value   := ""
        osdAccent.Opt("c71717A")
        osdMeter.Opt("c71717A")
        osdMeter.Value := 0
    } else if IsObject(midiInfo) {
        primary := midiInfo.target
        chanTitle := nameMap.Has(primary) ? nameMap[primary] : primary

        mVal := 0.0
        DllCall(pGetFloat, "AStr", primary ".Mute", "Float*", &mVal)
        isMuted := (mVal >= 0.5)

        if (midiInfo.type = "pad_ptt") {
            osdChannelText.Value := nameMap.Has(pttMicStrip) ? nameMap[pttMicStrip] : pttMicStrip
            if midiInfo.held {
                osdGainText.SetFont("s11 Bold c34D399")
                osdGainText.Value := "LIVE (PTT)"
                osdAccent.Opt("c34D399")
                osdMeter.Opt("c34D399")
                osdMeter.Value := 100
            } else {
                osdGainText.SetFont("s11 Bold cF87171")
                osdGainText.Value := "MUTED"
                osdAccent.Opt("cF87171")
                osdMeter.Opt("cF87171")
                osdMeter.Value := 0
            }
            osdFxLabelText.SetFont("s9 Bold cA1A1AA")
            osdFxLabelText.Value := "MIDI Push-to-Talk (" midiInfo.mapKey ")"
            osdFxValText.Value   := midiInfo.held ? "Release to mute" : "Hold pad to talk"
        } else if (midiInfo.type = "pad_mute") {
            osdChannelText.Value := chanTitle
            osdGainText.SetFont(isMuted ? "s11 Bold cF87171" : "s11 Bold c38BDF8")
            osdGainText.Value := isMuted ? "MUTED" : "UNMUTED"
            osdAccent.Opt(isMuted ? "cF87171" : "c38BDF8")
            osdFxLabelText.SetFont("s9 Bold cA1A1AA")
            osdFxLabelText.Value := "MIDI Pad Mute (" midiInfo.mapKey ")"
            osdFxValText.Value   := isMuted ? "Muted" : "Active"
            osdMeter.Opt(isMuted ? "cF87171" : "c38BDF8")
            osdMeter.Value := isMuted ? 0 : 85
        } else if (midiInfo.type = "pad_snap") {
            gVal := 0.0
            DllCall(pGetFloat, "AStr", primary ".Gain", "Float*", &gVal)
            if (Abs(gVal) < 0.05)
                gVal := 0.0
            osdChannelText.Value := "Snapshot P" midiInfo.val
            osdGainText.SetFont("s11 Bold cF59E0B")
            osdGainText.Value := "RECALLED"
            osdAccent.Opt("cF59E0B")
            osdFxLabelText.SetFont("s9 Bold cA1A1AA")
            osdFxLabelText.Value := "MIDI Pad Snapshot (" midiInfo.mapKey ")"
            osdFxValText.Value   := chanTitle " " (gVal > 0 ? "+" : "") Format("{:.1f} dB", gVal)
            osdMeter.Opt("cF59E0B")
            osdMeter.Value := Max(0, Min(100, Round(((gVal + 60.0) / 72.0) * 100)))
        } else if (midiInfo.type = "fx") {
            fxObj := midiInfo.fxObj
            fxVal := midiInfo.curVal
            gVal  := 0.0
            DllCall(pGetFloat, "AStr", primary ".Gain", "Float*", &gVal)
            if (Abs(gVal) < 0.05)
                gVal := 0.0

            osdChannelText.Value := chanTitle
            if isMuted {
                osdGainText.SetFont("s11 Bold cF87171")
                osdGainText.Value := "MUTED"
                osdAccent.Opt("cF87171")
            } else {
                osdGainText.SetFont("s11 Bold c38BDF8")
                osdGainText.Value := (gVal > 0 ? "+" : "") Format("{:.1f} dB", gVal)
                osdAccent.Opt("c38BDF8")
            }

            osdFxLabelText.SetFont("s9 Bold c38BDF8")
            osdFxLabelText.Value := "FX  " Chr(0x25C2) "  " fxObj.label "  " Chr(0x25B8)
            osdFxValText.Value   := FormatEffectValue(fxObj, fxVal)

            span := Max(0.1, midiInfo.maxVal - midiInfo.minVal)
            pct := Round(((fxVal - midiInfo.minVal) / span) * 100)
            osdMeter.Opt("c38BDF8")
            osdMeter.Value := Max(0, Min(100, pct))
        } else {
            lIdx := (midiInfo.type = "layer") ? Integer(midiInfo.val) : 0
            if (lIdx > 0 && lIdx <= outputBuses.Length) {
                busParam := outputBuses[lIdx].param
                busLabel := nameMap.Has(busParam) ? nameMap[busParam] : outputBuses[lIdx].name
                chanTitle .= "  " Chr(0x2192) "  " busLabel
            }

            val := Round(midiInfo.curVal, 1)
            if (Abs(val) < 0.05)
                val := 0.0

            osdChannelText.Value := chanTitle
            if isMuted {
                osdGainText.SetFont("s11 Bold cF87171")
                osdGainText.Value := "MUTED"
                osdAccent.Opt("cF87171")
            } else if (lIdx > 0) {
                osdGainText.SetFont("s11 Bold cF59E0B")
                osdGainText.Value := (val > 0 ? "+" : "") Format("{:.1f} dB", val)
                osdAccent.Opt("cF59E0B")
            } else {
                osdGainText.SetFont("s11 Bold c38BDF8")
                osdGainText.Value := (val > 0 ? "+" : "") Format("{:.1f} dB", val)
                osdAccent.Opt("c38BDF8")
            }

            modeTag := (midiInfo.mode = "rel") ? "REL" : ((midiInfo.curve = "log") ? "LOG" : "LIN")
            rangeStr := Format("{:.0f}..{:+.0f} dB", midiInfo.minVal, midiInfo.maxVal)
            osdFxLabelText.SetFont("s9 Bold c" (lIdx > 0 ? "F59E0B" : "A1A1AA"))
            osdFxLabelText.Value := "MIDI " modeTag " (" midiInfo.mapKey ")"
            osdFxValText.Value   := rangeStr

            span := Max(0.1, midiInfo.maxVal - midiInfo.minVal)
            pct := Round(((val - midiInfo.minVal) / span) * 100)
            osdMeter.Opt(isMuted ? "cF87171" : (lIdx > 0 ? "cF59E0B" : "c38BDF8"))
            osdMeter.Value := Max(0, Min(100, pct))
        }
    } else if (activeTargets.Length = 0) {
        osdChannelText.Value := "No Target Selected"
        osdGainText.Value    := "--"
        osdFxLabelText.Value := "Open Control Panel to pick a strip"
        osdFxValText.Value   := ""
        osdMeter.Value       := 0
    } else {
        primary := activeTargets[1]
        chanTitle := nameMap.Has(primary) ? nameMap[primary] : primary
        layerIdx := GetActiveGainLayerIndex()

        if (activeTargets.Length > 1) {
            chanTitle .= "  +" (activeTargets.Length - 1) " linked"
        } else if (layerIdx > 0) {
            busParam := outputBuses[layerIdx].param
            busLabel := nameMap.Has(busParam) ? nameMap[busParam] : outputBuses[layerIdx].name
            chanTitle .= "  " Chr(0x2192) "  " busLabel
        }

        val := vm.gains.Has(primary) ? Round(vm.gains[primary].current, 1) : 0.0
        if (Abs(val) < 0.05)
            val := 0.0

        anyMuted := IsAnyActiveTargetMuted()

        osdChannelText.Value := chanTitle
        if anyMuted {
            osdGainText.SetFont("s11 Bold cF87171")
            osdGainText.Value := "MUTED"
            osdAccent.Opt("cF87171")
        } else if (layerIdx > 0) {
            osdGainText.SetFont("s11 Bold cF59E0B")
            osdGainText.Value := (val > 0 ? "+" : "") Format("{:.1f} dB", val)
            osdAccent.Opt("cF59E0B")
        } else {
            osdGainText.SetFont("s11 Bold c38BDF8")
            osdGainText.Value := (val > 0 ? "+" : "") Format("{:.1f} dB", val)
            osdAccent.Opt("c38BDF8")
        }

        soloParam := GetSoloTarget()
        if (soloParam != "") {
            fxObj := GetSelectedEffectObj(soloParam)
            fullParam := soloParam "." fxObj.key
            fxVal := vm.fxValues.Has(fullParam) ? vm.fxValues[fullParam].val : 0.0
            fxValStr := FormatEffectValue(fxObj, fxVal)

            if (mode = "layer" && layerIdx > 0) {
                osdFxLabelText.SetFont("s9 Bold cF59E0B")
                osdFxLabelText.Value := "Pro Submix Layer  (" outputBuses[layerIdx].name ")"
                osdFxValText.Value   := "GainLayer[" (layerIdx - 1) "]"
            } else {
                osdFxLabelText.SetFont(mode = "fx" ? "s9 Bold c38BDF8" : "s9 Bold cA1A1AA")
                osdFxLabelText.Value := "FX  " Chr(0x25C2) "  " fxObj.label "  " Chr(0x25B8)
                osdFxValText.Value   := fxValStr
            }

            if (mode = "fx") {
                pct := Round(((fxVal - fxObj.min) / (fxObj.max - fxObj.min)) * 100)
                osdMeter.Opt("c38BDF8")
                osdMeter.Value := Max(0, Min(100, pct))
            } else {
                pct := Round(((val + 60.0) / 72.0) * 100)
                osdMeter.Opt(anyMuted ? "cF87171" : (layerIdx > 0 ? "cF59E0B" : "c38BDF8"))
                osdMeter.Value := Max(0, Min(100, pct))
            }
        } else {
            osdFxLabelText.SetFont("s9 Norm c71717A")
            osdFxLabelText.Value := "Multi-Target Group Mode"
            osdFxValText.Value   := activeTargets.Length " ch"
            pct := Round(((val + 60.0) / 72.0) * 100)
            osdMeter.Opt(anyMuted ? "cF87171" : "c38BDF8")
            osdMeter.Value := Max(0, Min(100, pct))
        }
    }

    if !osdVisible {
        MonitorGetWorkArea(, &mLeft, &mTop, &mRight, &mBottom)
        osdW := 390
        osdH := 80
        xPos := mLeft + ((mRight - mLeft - osdW) // 2)
        yPos := mBottom - osdH - 22
        osdGui.Opt("+AlwaysOnTop")
        osdGui.Show("x" xPos " y" yPos " w" osdW " h" osdH " NoActivate")
        osdVisible := true
    }

    ForceOsdTopmost()
    SetTimer(ForceOsdTopmost, 100)
    SetTimer(HideHeadUnitOsd, -1500)
}

HideHeadUnitOsd() {
    global osdVisible
    SetTimer(ForceOsdTopmost, 0)
    osdGui.Hide()
    osdVisible := false
}

; ==============================================================================
; 5. PRO SIDECHAIN AUTO-DUCKING, PUSH-TO-TALK, ANTI-HIJACK, STARTUP & GUIDE
; ==============================================================================
duckGui           := ""
duckCheckBoxes    := Map()
duckTrigDDL       := ""
duckLayerDDL      := ""
duckIgnoreMuteChk := ""
duckAmtSlider     := ""
duckAmtValTxt     := ""
duckThreshSlider  := ""
duckThreshValTxt  := ""
duckAttackSlider  := ""
duckAttackValTxt  := ""
duckHoldSlider    := ""
duckHoldValTxt    := ""
duckReleaseSlider := ""
duckReleaseValTxt := ""
duckLiveMeter     := ""
duckGrMeter       := ""
duckMicReadout    := ""
duckGrReadout     := ""
duckStageBadge    := ""

CloseDuckingGui(*) {
    global duckGui
    SetTimer(UpdateDuckLiveMeter, 0)
    ResetLastHover()
    CleanupSubGuiHovers()
    if IsObject(duckGui) {
        try duckGui.Destroy()
    }
    duckGui := ""
}

FormatTimeLabel(ms) {
    if (ms = 0)
        return "0 ms (None)"
    if (ms < 1000)
        return ms " ms"
    return Format("{:.2f} s", ms / 1000.0)
}

ApplyDuckPreset(depthDb, threshDb, attMs, hldMs, relMs, presetName, *) {
    duckAmtSlider.Value     := depthDb
    duckThreshSlider.Value  := threshDb
    duckAttackSlider.Value  := attMs
    duckHoldSlider.Value    := hldMs
    duckReleaseSlider.Value := relMs

    duckAmtValTxt.Value     := "-" depthDb " dB"
    duckThreshValTxt.Value  := threshDb " dBFS"
    duckAttackValTxt.Value  := FormatTimeLabel(attMs)
    duckHoldValTxt.Value    := FormatTimeLabel(hldMs)
    duckReleaseValTxt.Value := FormatTimeLabel(relMs)

    ShowQuickTip("Loaded '" presetName "' ducking curve — click Save & Enable to apply.", 1400)
}

SetDuckTargetSelection(mode, *) {
    for idx, ch in allChannels {
        if !duckCheckBoxes.Has(ch.param)
            continue
        if (mode = "all") {
            duckCheckBoxes[ch.param].Value := 1
        } else if (mode = "none") {
            duckCheckBoxes[ch.param].Value := 0
        } else if (mode = "virtual") {
            isVirt := (ch.param = "Strip[5]" || ch.param = "Strip[6]" || ch.param = "Strip[7]")
            duckCheckBoxes[ch.param].Value := isVirt ? 1 : 0
        }
    }
}

OpenDuckingGui() {
    global duckGui, duckCheckBoxes, duckTrigDDL, duckLayerDDL, duckIgnoreMuteChk
    global duckAmtSlider, duckAmtValTxt, duckThreshSlider, duckThreshValTxt
    global duckAttackSlider, duckAttackValTxt, duckHoldSlider, duckHoldValTxt
    global duckReleaseSlider, duckReleaseValTxt
    global duckLiveMeter, duckGrMeter, duckMicReadout, duckGrReadout, duckStageBadge

    if IsGuiAlive(duckGui) {
        duckGui.Show()
        SetTimer(UpdateDuckLiveMeter, 50)
        return
    }

    duckCheckBoxes := Map()

    duckGui := Gui("+AlwaysOnTop -MaximizeBox", "Sidechain Auto-Ducking Studio")
    duckGui.MarginX := 16
    duckGui.MarginY := 14
    duckGui.BackColor := "0D0D11"
    ApplySleekWindowTheme(duckGui, false)

    duckGui.AddProgress("x16 y12 w620 h2 Background0D0D11 c38BDF8", 100)
    duckGui.SetFont("s11 Bold cF4F4F5", "Segoe UI")
    duckGui.AddText("x16 y20 w420 h22 Background0D0D11", "Sidechain Auto-Ducking")
    duckGui.SetFont("s9 Norm cA1A1AA", "Segoe UI")
    duckGui.AddText("x16 y42 w620 h17 Background0D0D11", "Automatically lowers background audio when you speak, then smoothly restores it after you finish.")

    duckGui.AddText("x16 y66 w620 h96 Background15151C", "")

    duckGui.SetFont("s8 Bold c38BDF8", "Segoe UI")
    duckGui.AddText("x28 y74 w286 h15 Background15151C", "1. TRIGGER INPUT (YOUR MICROPHONE)")
    duckGui.AddText("x334 y74 w290 h15 Background15151C", "2. DUCKING SCOPE (WHERE TO LOWER AUDIO)")

    stripChoices := []
    trigSelIdx := 1
    for idx, st in inputStrips {
        stripChoices.Push(nameMap[st.param] "  (" st.param ")")
        if (st.param = duckTriggerStrip)
            trigSelIdx := idx
    }

    duckGui.SetFont("s9 Norm cF4F4F5", "Segoe UI")
    duckTrigDDL := duckGui.AddDropDownList("x28 y92 w286 Background1C1C26 cF4F4F5 Choose" trigSelIdx, stripChoices)

    layerChoices := ["All Output Buses (Main Channel Fader)"]
    for b in outputBuses
        layerChoices.Push("Only in " b.name " — " nameMap[b.param] " (Submix Layer)")
    duckLayerDDL := duckGui.AddDropDownList("x334 y92 w290 Background1C1C26 cF4F4F5 Choose" (duckBusLayer + 1), layerChoices)

    duckGui.SetFont("s8 Norm cE4E4E7", "Segoe UI")
    duckIgnoreMuteChk := duckGui.AddCheckBox("x28 y127 w290 h22 Background15151C cE4E4E7 Checked" duckIgnoreMuted, "Ignore mic trigger when strip is muted")

    duckGui.SetFont("s8 Bold c71717A", "Segoe UI")
    duckGui.AddText("x334 y127 w54 h22 +0x200 Background15151C", "PRESETS:")

    duckGui.SetFont("s8 Bold c38BDF8", "Segoe UI")
    pPodBtn := duckGui.AddText("x392 y126 w56 h22 Center +0x200 Background1B2B3A", "Podcast")
    pPodBtn.OnEvent("Click", ApplyDuckPreset.Bind(14, -30, 60, 400, 350, "Podcast / Voiceover"))
    RegisterButtonHover(pPodBtn, "1B2B3A", "23384C", "Balanced voiceover curve (-14 dB, 60 ms attack, 350 ms release)", false)

    pGamBtn := duckGui.AddText("x452 y126 w56 h22 Center +0x200 Background1B2B3A", "Gaming")
    pGamBtn.OnEvent("Click", ApplyDuckPreset.Bind(10, -26, 40, 280, 240, "Gaming / Discord"))
    RegisterButtonHover(pGamBtn, "1B2B3A", "23384C", "Subtle background dip for game audio (-10 dB, 40 ms attack, 240 ms release)", false)

    pRadBtn := duckGui.AddText("x512 y126 w52 h22 Center +0x200 Background1B2B3A", "Radio")
    pRadBtn.OnEvent("Click", ApplyDuckPreset.Bind(18, -32, 120, 600, 850, "Smooth Radio Fade"))
    RegisterButtonHover(pRadBtn, "1B2B3A", "23384C", "Deep broadcast music fade (-18 dB, 120 ms attack, 850 ms release)", false)

    pTgtBtn := duckGui.AddText("x568 y126 w56 h22 Center +0x200 Background1B2B3A", "Tight")
    pTgtBtn.OnEvent("Click", ApplyDuckPreset.Bind(12, -28, 15, 90, 60, "Snappy / Tight"))
    RegisterButtonHover(pTgtBtn, "1B2B3A", "23384C", "Fast, punchy response (-12 dB, 15 ms attack, 60 ms release)", false)

    duckGui.AddText("x16 y170 w620 h68 Background15151C", "")

    duckGui.SetFont("s8 Bold c71717A", "Segoe UI")
    duckGui.AddText("x28 y178 w150 h16 Background15151C", "LIVE MIC INPUT LEVEL")
    duckGui.SetFont("s8 Bold cA1A1AA", "Segoe UI")
    duckMicReadout := duckGui.AddText("x180 y178 w146 h16 Right Background15151C", "-60.0 dBFS")

    duckGui.SetFont("s8 Bold c71717A", "Segoe UI")
    duckGui.AddText("x344 y178 w150 h16 Background15151C", "ACTIVE GAIN REDUCTION")
    duckGui.SetFont("s8 Bold c38BDF8", "Segoe UI")
    duckGrReadout := duckGui.AddText("x496 y178 w128 h16 Right Background15151C", "0.0 dB")

    duckLiveMeter := duckGui.AddProgress("x28 y196 w298 h8 Range-60-0 Background1C1C26 c52525B", -60)
    duckGrMeter   := duckGui.AddProgress("x344 y196 w280 h8 Range0-48 Background1C1C26 c38BDF8", 0)

    duckGui.SetFont("s8 Bold c71717A", "Segoe UI")
    duckStageBadge := duckGui.AddText("x28 y211 w596 h18 Background15151C", "STAGE: IDLE  •  Speak into your mic or click Test Duck below to preview the envelope")

    duckGui.AddText("x16 y246 w620 h176 Background15151C", "")

    initAmt    := Max(1, Min(48, Round(Abs(duckAmountDb))))
    initThresh := Max(-60, Min(0, Round(duckThresholdDb)))

    duckGui.SetFont("s9 Bold cF4F4F5", "Segoe UI")
    duckGui.AddText("x28 y254 w180 h18 Background15151C", "3. Duck Depth (Amount)")
    duckGui.SetFont("s9 Bold c38BDF8", "Segoe UI")
    duckAmtValTxt := duckGui.AddText("x212 y254 w102 h18 Right Background15151C", "-" initAmt " dB")

    duckAmtSlider := duckGui.AddSlider("x24 y273 w294 h24 Range1-48 TickInterval6 AltSubmit Background15151C", initAmt)
    try DllCall("uxtheme\SetWindowTheme", "Ptr", duckAmtSlider.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
    duckAmtSlider.OnEvent("Change", (*) => (duckAmtValTxt.Value := "-" duckAmtSlider.Value " dB"))

    duckGui.SetFont("s8 Norm c71717A", "Segoe UI")
    duckGui.AddText("x28 y298 w286 h15 Background15151C", "How much quieter target channels get while talking")

    duckGui.SetFont("s9 Bold cF4F4F5", "Segoe UI")
    duckGui.AddText("x334 y254 w180 h18 Background15151C", "4. Voice Threshold")
    duckGui.SetFont("s9 Bold c38BDF8", "Segoe UI")
    duckThreshValTxt := duckGui.AddText("x518 y254 w106 h18 Right Background15151C", initThresh " dBFS")

    duckThreshSlider := duckGui.AddSlider("x330 y273 w298 h24 Range-60-0 TickInterval10 AltSubmit Background15151C", initThresh)
    try DllCall("uxtheme\SetWindowTheme", "Ptr", duckThreshSlider.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
    duckThreshSlider.OnEvent("Change", (*) => (duckThreshValTxt.Value := duckThreshSlider.Value " dBFS"))

    duckGui.SetFont("s8 Norm c71717A", "Segoe UI")
    duckGui.AddText("x334 y298 w290 h15 Background15151C", "Set just below your normal speaking level above")

    duckGui.AddText("x28 y321 w596 h1 Background22222E", "")

    initAttack  := Max(10, Min(1000, duckAttackMs))
    initHold    := Max(0, Min(3000, duckHoldMs))
    initRelease := Max(40, Min(3000, duckReleaseMs))

    duckGui.SetFont("s9 Bold cF4F4F5", "Segoe UI")
    duckGui.AddText("x28 y330 w105 h18 Background15151C", "5. Attack Speed")
    duckGui.SetFont("s9 Bold c38BDF8", "Segoe UI")
    duckAttackValTxt := duckGui.AddText("x135 y330 w80 h18 Right Background15151C", FormatTimeLabel(initAttack))

    duckAttackSlider := duckGui.AddSlider("x24 y350 w195 h24 Range10-1000 TickInterval150 AltSubmit Background15151C", initAttack)
    try DllCall("uxtheme\SetWindowTheme", "Ptr", duckAttackSlider.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
    duckAttackSlider.OnEvent("Change", (*) => (duckAttackValTxt.Value := FormatTimeLabel(duckAttackSlider.Value)))

    duckGui.SetFont("s8 Norm c71717A", "Segoe UI")
    duckGui.AddText("x28 y376 w190 h36 Background15151C", "How fast audio dips when you start speaking.")

    duckGui.SetFont("s9 Bold cF4F4F5", "Segoe UI")
    duckGui.AddText("x232 y330 w105 h18 Background15151C", "6. Hold Time")
    duckGui.SetFont("s9 Bold c38BDF8", "Segoe UI")
    duckHoldValTxt := duckGui.AddText("x339 y330 w80 h18 Right Background15151C", FormatTimeLabel(initHold))

    duckHoldSlider := duckGui.AddSlider("x228 y350 w195 h24 Range0-3000 TickInterval500 AltSubmit Background15151C", initHold)
    try DllCall("uxtheme\SetWindowTheme", "Ptr", duckHoldSlider.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
    duckHoldSlider.OnEvent("Change", (*) => (duckHoldValTxt.Value := FormatTimeLabel(duckHoldSlider.Value)))

    duckGui.SetFont("s8 Norm c71717A", "Segoe UI")
    duckGui.AddText("x232 y376 w190 h36 Background15151C", "Pause before recovery (bridges word gaps).")

    duckGui.SetFont("s9 Bold cF4F4F5", "Segoe UI")
    duckGui.AddText("x436 y330 w105 h18 Background15151C", "7. Release Speed")
    duckGui.SetFont("s9 Bold c38BDF8", "Segoe UI")
    duckReleaseValTxt := duckGui.AddText("x543 y330 w81 h18 Right Background15151C", FormatTimeLabel(initRelease))

    duckReleaseSlider := duckGui.AddSlider("x432 y350 w196 h24 Range40-3000 TickInterval500 AltSubmit Background15151C", initRelease)
    try DllCall("uxtheme\SetWindowTheme", "Ptr", duckReleaseSlider.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
    duckReleaseSlider.OnEvent("Change", (*) => (duckReleaseValTxt.Value := FormatTimeLabel(duckReleaseSlider.Value)))

    duckGui.SetFont("s8 Norm c71717A", "Segoe UI")
    duckGui.AddText("x436 y376 w190 h36 Background15151C", "How smoothly volume fades back up after Hold.")

    duckGui.SetFont("s8 Bold c38BDF8", "Segoe UI")
    duckGui.AddText("x16 y432 w370 h20 +0x200 Background0D0D11", "8. TARGET CHANNELS TO DUCK WHEN SPEAKING")

    duckGui.SetFont("s8 Bold cA1A1AA", "Segoe UI")
    selVirtBtn := duckGui.AddText("x418 y431 w92 h20 Center +0x200 Background191922", "Virtual Only")
    selVirtBtn.OnEvent("Click", SetDuckTargetSelection.Bind("virtual"))
    RegisterButtonHover(selVirtBtn, "191922", "242432", "Select only Virtual Inputs (VAIO, AUX, VAIO3)", false)

    selAllBtn := duckGui.AddText("x514 y431 w58 h20 Center +0x200 Background191922", "All")
    selAllBtn.OnEvent("Click", SetDuckTargetSelection.Bind("all"))
    RegisterButtonHover(selAllBtn, "191922", "242432", "Select all 16 channels", false)

    selNoneBtn := duckGui.AddText("x576 y431 w60 h20 Center +0x200 Background191922", "None")
    selNoneBtn.OnEvent("Click", SetDuckTargetSelection.Bind("none"))
    RegisterButtonHover(selNoneBtn, "191922", "242432", "Clear all selected channels", false)

    yChk := 456
    for idx, ch in allChannels {
        col := Mod(idx - 1, 3)
        xC  := 16 + (col * 210)
        isChecked := false
        for dt in duckTargets {
            if (dt = ch.param) {
                isChecked := true
                break
            }
        }
        duckGui.SetFont("s9 Norm cE4E4E7", "Segoe UI")
        cb := duckGui.AddCheckBox("x" xC " y" yChk " w202 h21 Background0D0D11 cE4E4E7 Checked" isChecked, nameMap[ch.param])
        duckCheckBoxes[ch.param] := cb
        if (col = 2 || idx = allChannels.Length)
            yChk += 23
    }

    yAct := yChk + 10
    duckGui.AddText("x16 y" (yAct - 6) " w620 h1 Background22222E", "")

    duckGui.SetFont("s9 Bold cD4D4D8", "Segoe UI")
    testDuckBtn := duckGui.AddText("x16 y" yAct " w154 h28 Center +0x200 Background191922", "Test Duck Curve (1.8s)")
    testDuckBtn.OnEvent("Click", TriggerDuckTest)
    RegisterButtonHover(testDuckBtn, "191922", "242432", "Simulate speaking for 1.8s to audition your Attack, Hold && Release curve", false)

    duckGui.SetFont("s9 Bold c38BDF8", "Segoe UI")
    saveDuckBtn := duckGui.AddText("x420 y" yAct " w128 h28 Center +0x200 Background152433", "Save && Enable")
    saveDuckBtn.OnEvent("Click", SaveDuckingConfig)
    RegisterButtonHover(saveDuckBtn, "152433", "1C3247", "Save Auto-Ducking settings and turn Auto-Ducking ON", false)

    duckGui.SetFont("s9 Bold cA1A1AA", "Segoe UI")
    cancelDuckBtn := duckGui.AddText("x554 y" yAct " w82 h28 Center +0x200 Background191922", "Close")
    cancelDuckBtn.OnEvent("Click", CloseDuckingGui)
    RegisterButtonHover(cancelDuckBtn, "191922", "242432", "", false)

    duckGui.OnEvent("Close", CloseDuckingGui)
    duckGui.OnEvent("Escape", CloseDuckingGui)
    duckGui.Show("AutoSize")
    SetTimer(UpdateDuckLiveMeter, 50)
}

TriggerDuckTest(*) {
    global duckTriggerStrip, duckBusLayer, duckAmountDb, duckThresholdDb, duckAttackMs, duckHoldMs, duckReleaseMs, duckTargets, duckTestUntilTick

    tIdx := duckTrigDDL.Value
    if (tIdx >= 1 && tIdx <= inputStrips.Length)
        duckTriggerStrip := inputStrips[tIdx].param

    duckBusLayer    := Max(0, duckLayerDDL.Value - 1)
    duckAmountDb    := Float(duckAmtSlider.Value)
    duckThresholdDb := Float(duckThreshSlider.Value)
    duckAttackMs    := Integer(duckAttackSlider.Value)
    duckHoldMs      := Integer(duckHoldSlider.Value)
    duckReleaseMs   := Integer(duckReleaseSlider.Value)

    duckTargets := []
    for ch in allChannels {
        if (duckCheckBoxes.Has(ch.param) && duckCheckBoxes[ch.param].Value = 1)
            duckTargets.Push(ch.param)
    }

    duckTestUntilTick := A_TickCount + 1800
    SetTimer(AutoDuckTick, 25)
    ShowQuickTip("Testing Auto-Ducking curve (-" Round(duckAmountDb) " dB)...", 1500)
}

UpdateDuckLiveMeter() {
    if !IsGuiAlive(duckGui) {
        SetTimer(UpdateDuckLiveMeter, 0)
        return
    }
    if (!vm.connected || !pGetLevel) {
        duckStageBadge.Value := "STAGE: OFFLINE  •  Start VoiceMeeter Potato to preview live levels"
        return
    }

    tIdx := duckTrigDDL.Value
    param := (tIdx >= 1 && tIdx <= inputStrips.Length) ? inputStrips[tIdx].param : duckTriggerStrip
    stripIdx := Integer(RegExReplace(param, "\D"))

    isMuted := false
    if (duckIgnoreMuteChk.Value = 1) {
        mVal := 0.0
        DllCall(pGetFloat, "AStr", param ".Mute", "Float*", &mVal)
        isMuted := (mVal >= 0.5)
    }

    lvlL := 0.0
    lvlR := 0.0
    DllCall(pGetLevel, "Int", 0, "Int", stripIdx * 8, "Float*", &lvlL)
    DllCall(pGetLevel, "Int", 0, "Int", (stripIdx * 8) + 1, "Float*", &lvlR)

    peak := isMuted ? 0.0 : Max(lvlL, lvlR)
    db := (peak > 0.000001) ? (20.0 * Log(peak)) : -60.0
    clampedDb := Round(Max(-60, Min(0, db)))
    thresh := duckThreshSlider.Value

    duckLiveMeter.Value := clampedDb
    if isMuted {
        duckLiveMeter.Opt("cF87171")
        duckMicReadout.SetFont("s8 Bold cF87171")
        duckMicReadout.Value := "MUTED (Ignored)"
    } else if (db >= thresh) {
        duckLiveMeter.Opt("c38BDF8")
        duckMicReadout.SetFont("s8 Bold c38BDF8")
        duckMicReadout.Value := Format("{:.1f} dBFS  (TRIGGERED)", Max(-60.0, db))
    } else {
        duckLiveMeter.Opt("c52525B")
        duckMicReadout.SetFont("s8 Bold cA1A1AA")
        duckMicReadout.Value := Format("{:.1f} dBFS", Max(-60.0, db))
    }

    grAbs := Abs(duckCurrentOffset)
    duckGrMeter.Value := Round(Max(0, Min(48, grAbs)))
    duckGrReadout.Value := (grAbs >= 0.05) ? Format("-{:.1f} dB", grAbs) : "0.0 dB"

    if (duckStageLabel = "IDLE") {
        duckStageBadge.SetFont("s8 Bold c71717A")
        duckStageBadge.Value := "STAGE: IDLE  •  Waiting for voice above " thresh " dBFS"
    } else {
        duckStageBadge.SetFont("s8 Bold c38BDF8")
        duckStageBadge.Value := "STAGE: " duckStageLabel "  •  Applying " Format("-{:.1f} dB", grAbs) " reduction"
    }
}

SaveDuckingConfig(*) {
    global duckEnabled, duckTriggerStrip, duckBusLayer, duckAmountDb, duckThresholdDb
    global duckAttackMs, duckHoldMs, duckReleaseMs, duckIgnoreMuted, duckTargets, duckTestUntilTick

    duckTestUntilTick := 0
    RestoreAllDuckedChannels()

    tIdx := duckTrigDDL.Value
    if (tIdx >= 1 && tIdx <= inputStrips.Length)
        duckTriggerStrip := inputStrips[tIdx].param

    duckBusLayer    := Max(0, duckLayerDDL.Value - 1)
    duckAmountDb    := Float(duckAmtSlider.Value)
    duckThresholdDb := Float(duckThreshSlider.Value)
    duckAttackMs    := Integer(duckAttackSlider.Value)
    duckHoldMs      := Integer(duckHoldSlider.Value)
    duckReleaseMs   := Integer(duckReleaseSlider.Value)
    duckIgnoreMuted := duckIgnoreMuteChk.Value

    duckTargets := []
    joined := ""
    for ch in allChannels {
        if (duckCheckBoxes.Has(ch.param) && duckCheckBoxes[ch.param].Value = 1) {
            duckTargets.Push(ch.param)
            joined .= (joined != "" ? "," : "") ch.param
        }
    }

    duckEnabled := 1
    IniWrite(1, iniPath, "AutoDuck", "Enabled")
    IniWrite(duckTriggerStrip, iniPath, "AutoDuck", "TriggerStrip")
    IniWrite(joined, iniPath, "AutoDuck", "Targets")
    IniWrite(duckBusLayer, iniPath, "AutoDuck", "BusLayer")
    IniWrite(Format("{:.1f}", duckAmountDb), iniPath, "AutoDuck", "AmountDb")
    IniWrite(Format("{:.1f}", duckThresholdDb), iniPath, "AutoDuck", "ThresholdDb")
    IniWrite(duckAttackMs, iniPath, "AutoDuck", "AttackMs")
    IniWrite(duckHoldMs, iniPath, "AutoDuck", "HoldMs")
    IniWrite(duckReleaseMs, iniPath, "AutoDuck", "ReleaseMs")
    IniWrite(duckIgnoreMuted, iniPath, "AutoDuck", "IgnoreMuted")

    SetTimer(AutoDuckTick, 25)
    RefreshAutomationPills()
    RefreshShortcutLabels()
    CloseDuckingGui()
    ShowQuickTip("Auto-Ducking saved & enabled (-" Round(duckAmountDb) " dB).", 1500)
}

; --- Dedicated Push-to-Talk (PTT) Setup Window ---
pttGui    := ""
pttMicDDL := ""
pttKeyBtn := ""

ClosePttGui(*) {
    global pttGui, activeInputHook
    if (activeInputHook != "") {
        try activeInputHook.Stop()
        activeInputHook := ""
    }
    Suspend(0)
    ResetLastHover()
    CleanupSubGuiHovers()
    if IsObject(pttGui) {
        try pttGui.Destroy()
    }
    pttGui := ""
}

OpenPttGui() {
    global pttGui, pttMicDDL, pttKeyBtn

    if IsGuiAlive(pttGui) {
        pttGui.Show()
        return
    }

    pttGui := Gui("+AlwaysOnTop -MaximizeBox", "Push-to-Talk (Auto-Mute Mic)")
    pttGui.MarginX := 16
    pttGui.MarginY := 14
    pttGui.BackColor := "0D0D11"
    ApplySleekWindowTheme(pttGui, false)

    pttGui.AddProgress("x16 y12 w440 h2 Background0D0D11 c38BDF8", 100)
    pttGui.SetFont("s11 Bold cF4F4F5", "Segoe UI")
    pttGui.AddText("x16 y20 w440 h22 Background0D0D11", "Push-to-Talk (Auto-Mute Microphone)")
    pttGui.SetFont("s9 Norm cA1A1AA", "Segoe UI")
    pttGui.AddText("x16 y42 w440 h30 Background0D0D11", "Automatically keeps your selected mic strip muted and unmutes it ONLY while holding your Push-to-Talk key.")

    pttGui.AddText("x16 y78 w440 h122 Background15151C", "")

    pttGui.SetFont("s8 Bold c38BDF8", "Segoe UI")
    pttGui.AddText("x28 y88 w416 h16 Background15151C", "1. MICROPHONE INPUT STRIP TO AUTO-MUTE")

    stripChoices := []
    micSelIdx := 1
    for idx, st in inputStrips {
        stripChoices.Push(nameMap[st.param] "  (" st.param ")")
        if (st.param = pttMicStrip)
            micSelIdx := idx
    }

    pttGui.SetFont("s9 Norm cF4F4F5", "Segoe UI")
    pttMicDDL := pttGui.AddDropDownList("x28 y108 w416 Background1C1C26 cF4F4F5 Choose" micSelIdx, stripChoices)

    pttGui.SetFont("s8 Bold c38BDF8", "Segoe UI")
    pttGui.AddText("x28 y144 w416 h16 Background15151C", "2. PUSH-TO-TALK HOLD KEY (UNMUTES WHILE HELD)")

    hkVal := keybinds["pttHold"]
    pttGui.SetFont("s9 Bold c" (hkVal != "" ? "38BDF8" : "71717A"), "Segoe UI")
    pttKeyBtn := pttGui.AddText("x28 y164 w346 h26 Center +0x200 Background" (hkVal != "" ? "152433" : "16161E"), FormatHotkeyHuman(hkVal))
    pttKeyBtn.OnEvent("Click", CapturePttKeyInDialog)

    pttGui.SetFont("s8 Bold cA1A1AA", "Segoe UI")
    clrPttBtn := pttGui.AddText("x380 y164 w64 h26 Center +0x200 Background191922", "Clear")
    clrPttBtn.OnEvent("Click", (*) => (
        keybinds["pttHold"] := "",
        IniWrite("", iniPath, "Hotkeys", "pttHold"),
        RegisterAllHotkeys(),
        pttKeyBtn.SetFont("s9 Bold c71717A"),
        pttKeyBtn.Opt("Background16161E"),
        pttKeyBtn.Value := "Unbound"
    ))
    RegisterButtonHover(clrPttBtn, "191922", "2A1A20", "Clear the Push-to-Talk keyboard key", false)

    pttGui.SetFont("s9 Bold c38BDF8", "Segoe UI")
    savePttBtn := pttGui.AddText("x204 y212 w164 h28 Center +0x200 Background152433", "Save && Enable PTT")
    savePttBtn.OnEvent("Click", SaveAndEnablePtt)
    RegisterButtonHover(savePttBtn, "152433", "1C3247", "Save PTT mic & key and enable auto-mute", false)

    pttGui.SetFont("s9 Bold cA1A1AA", "Segoe UI")
    closePttBtn := pttGui.AddText("x374 y212 w82 h28 Center +0x200 Background191922", "Close")
    closePttBtn.OnEvent("Click", ClosePttGui)
    RegisterButtonHover(closePttBtn, "191922", "242432", "", false)

    pttGui.OnEvent("Close", ClosePttGui)
    pttGui.OnEvent("Escape", ClosePttGui)
    pttGui.Show("AutoSize")
}

CapturePttKeyInDialog(*) {
    global activeInputHook
    if (activeInputHook != "") {
        try activeInputHook.Stop()
    }
    Suspend(1)
    pttKeyBtn.SetFont("s9 Bold cFBBF24")
    pttKeyBtn.Opt("Background2A2212")
    pttKeyBtn.Value := "Press key... (Esc to cancel)"

    ih := InputHook("L0")
    activeInputHook := ih
    ih.KeyOpt("{All}", "E")
    ih.KeyOpt("{LCtrl}{RCtrl}{LAlt}{RAlt}{LShift}{RShift}{LWin}{RWin}{Ctrl}{Alt}{Shift}", "-E")
    ih.Start()
    ih.Wait()

    activeInputHook := ""
    Suspend(0)

    if (ih.EndReason != "EndKey" || ih.EndKey = "Escape") {
        hkVal := keybinds["pttHold"]
        pttKeyBtn.SetFont("s9 Bold c" (hkVal != "" ? "38BDF8" : "71717A"))
        pttKeyBtn.Opt("Background" (hkVal != "" ? "152433" : "16161E"))
        pttKeyBtn.Value := FormatHotkeyHuman(hkVal)
        return
    }

    newHk := ih.EndKey
    keybinds["pttHold"] := newHk
    IniWrite(newHk, iniPath, "Hotkeys", "pttHold")
    RegisterAllHotkeys()

    pttKeyBtn.SetFont("s9 Bold c38BDF8")
    pttKeyBtn.Opt("Background152433")
    pttKeyBtn.Value := FormatHotkeyHuman(newHk)
}

SaveAndEnablePtt(*) {
    global pttMicStrip, pttEnabled, pttHeldActive
    idx := pttMicDDL.Value
    if (idx >= 1 && idx <= inputStrips.Length)
        pttMicStrip := inputStrips[idx].param

    if (keybinds["pttHold"] = "") {
        ShowQuickTip("Bind a Push-to-Talk key first before enabling PTT.", 1500)
        return
    }

    pttEnabled := 1
    pttHeldActive := false
    IniWrite(pttMicStrip, iniPath, "PushToTalk", "MicStrip")
    IniWrite(1, iniPath, "PushToTalk", "Enabled")

    ApplyPttMicState()
    RefreshAutomationPills()
    RefreshShortcutLabels()
    ClosePttGui()
    ShowQuickTip("Push-to-Talk ON (" nameMap[pttMicStrip] " muted until " FormatHotkeyHuman(keybinds["pttHold"]) " held)", 1600)
}

; --- Dedicated Anti-Hijack (Windows Default Device Lock) Window ---
antiHijackGui   := ""
playDevDDL      := ""
recDevDDL       := ""
enumPlayDevices := []
enumRecDevices  := []

CloseAntiHijackGui(*) {
    global antiHijackGui
    ResetLastHover()
    CleanupSubGuiHovers()
    if IsObject(antiHijackGui) {
        try antiHijackGui.Destroy()
    }
    antiHijackGui := ""
}

OpenAntiHijackGui() {
    global antiHijackGui, playDevDDL, recDevDDL, enumPlayDevices, enumRecDevices

    if IsGuiAlive(antiHijackGui) {
        antiHijackGui.Show()
        return
    }

    enumPlayDevices := EnumWindowsAudioDevices(0)
    enumRecDevices  := EnumWindowsAudioDevices(1)

    antiHijackGui := Gui("+AlwaysOnTop -MaximizeBox", "Windows Default Device Lock (Anti-Hijack)")
    antiHijackGui.MarginX := 16
    antiHijackGui.MarginY := 14
    antiHijackGui.BackColor := "0D0D11"
    ApplySleekWindowTheme(antiHijackGui, false)

    antiHijackGui.AddProgress("x16 y12 w480 h2 Background0D0D11 c38BDF8", 100)
    antiHijackGui.SetFont("s11 Bold cF4F4F5", "Segoe UI")
    antiHijackGui.AddText("x16 y20 w480 h22 Background0D0D11", "Windows Default Audio Device Lock (Anti-Hijack)")
    antiHijackGui.SetFont("s9 Norm cA1A1AA", "Segoe UI")
    antiHijackGui.AddText("x16 y42 w480 h18 Background0D0D11", "Prevents USB headsets, controllers, or monitors from stealing Windows audio defaults.")

    antiHijackGui.AddText("x16 y68 w480 h162 Background15151C", "")

    antiHijackGui.SetFont("s8 Bold c38BDF8", "Segoe UI")
    antiHijackGui.AddText("x28 y78 w456 h16 Background15151C", "1. LOCKED PLAYBACK DEVICE (DEFAULT OUTPUT)")

    playNames := []
    playSel := 1
    for idx, d in enumPlayDevices {
        playNames.Push(d.name)
        if (d.id = lockedPlaybackId)
            playSel := idx
    }
    if (playNames.Length = 0)
        playNames.Push("No active playback devices detected")

    antiHijackGui.SetFont("s9 Norm cF4F4F5", "Segoe UI")
    playDevDDL := antiHijackGui.AddDropDownList("x28 y98 w456 Background1C1C26 cF4F4F5 Choose" playSel, playNames)

    antiHijackGui.SetFont("s8 Bold c38BDF8", "Segoe UI")
    antiHijackGui.AddText("x28 y134 w456 h16 Background15151C", "2. LOCKED RECORDING DEVICE (DEFAULT INPUT / MIC)")

    recNames := []
    recSel := 1
    for idx, d in enumRecDevices {
        recNames.Push(d.name)
        if (d.id = lockedRecordId)
            recSel := idx
    }
    if (recNames.Length = 0)
        recNames.Push("No active recording devices detected")

    antiHijackGui.SetFont("s9 Norm cF4F4F5", "Segoe UI")
    recDevDDL := antiHijackGui.AddDropDownList("x28 y154 w456 Background1C1C26 cF4F4F5 Choose" recSel, recNames)

    antiHijackGui.SetFont("s8 Bold c38BDF8", "Segoe UI")
    capBtn := antiHijackGui.AddText("x28 y190 w220 h26 Center +0x200 Background1B2B3A", "Use Current Windows Defaults")
    capBtn.OnEvent("Click", CaptureCurrentDefaultsIntoGui)
    RegisterButtonHover(capBtn, "1B2B3A", "23384C", "Auto-fill dropdowns with your current Windows default devices", false)

    antiHijackGui.SetFont("s8 Norm c71717A", "Segoe UI")
    antiHijackGui.AddText("x258 y190 w226 h26 +0x200 Background15151C", "Usually VoiceMeeter Input && Output")

    antiHijackGui.AddText("x16 y240 w480 h1 Background22222E", "")

    antiHijackGui.SetFont("s9 Bold c38BDF8", "Segoe UI")
    saveLockBtn := antiHijackGui.AddText("x260 y248 w148 h28 Center +0x200 Background152433", "Save && Lock Devices")
    saveLockBtn.OnEvent("Click", SaveAndEnforceDeviceLock)
    RegisterButtonHover(saveLockBtn, "152433", "1C3247", "Lock selected playback and recording devices", false)

    antiHijackGui.SetFont("s9 Bold cA1A1AA", "Segoe UI")
    closeLockBtn := antiHijackGui.AddText("x414 y248 w82 h28 Center +0x200 Background191922", "Close")
    closeLockBtn.OnEvent("Click", CloseAntiHijackGui)
    RegisterButtonHover(closeLockBtn, "191922", "242432", "", false)

    antiHijackGui.OnEvent("Close", CloseAntiHijackGui)
    antiHijackGui.OnEvent("Escape", CloseAntiHijackGui)
    antiHijackGui.Show("AutoSize")
}

CaptureCurrentDefaultsIntoGui(*) {
    curPlay := GetDefaultWindowsEndpoint(0)
    curRec  := GetDefaultWindowsEndpoint(1)

    if (curPlay.id != "") {
        for idx, d in enumPlayDevices {
            if (d.id = curPlay.id) {
                playDevDDL.Choose(idx)
                break
            }
        }
    }
    if (curRec.id != "") {
        for idx, d in enumRecDevices {
            if (d.id = curRec.id) {
                recDevDDL.Choose(idx)
                break
            }
        }
    }
    ShowQuickTip("Captured current Windows Playback & Recording defaults.", 1300)
}

SaveAndEnforceDeviceLock(*) {
    global lockedPlaybackId, lockedPlaybackName, lockedRecordId, lockedRecordName, deviceLockEnabled

    pIdx := playDevDDL.Value
    if (pIdx >= 1 && pIdx <= enumPlayDevices.Length) {
        lockedPlaybackId   := enumPlayDevices[pIdx].id
        lockedPlaybackName := enumPlayDevices[pIdx].name
        IniWrite(lockedPlaybackId, iniPath, "DeviceLock", "PlaybackId")
        IniWrite(lockedPlaybackName, iniPath, "DeviceLock", "PlaybackName")
    }

    rIdx := recDevDDL.Value
    if (rIdx >= 1 && rIdx <= enumRecDevices.Length) {
        lockedRecordId   := enumRecDevices[rIdx].id
        lockedRecordName := enumRecDevices[rIdx].name
        IniWrite(lockedRecordId, iniPath, "DeviceLock", "RecordId")
        IniWrite(lockedRecordName, iniPath, "DeviceLock", "RecordName")
    }

    deviceLockEnabled := 1
    IniWrite(1, iniPath, "DeviceLock", "Enabled")
    RefreshAutomationPills()
    RefreshShortcutLabels()
    EnforceDefaultDevices(true)
    CloseAntiHijackGui()
    ShowQuickTip("Windows Default Devices Locked!", 1400)
}

; --- Plug-and-Play MIDI Controller, Sliders, Encoders & Drum Pads Window ---
midiGui        := ""
midiDevDDL     := ""
midiTargetDDL  := ""
midiParamDDL   := ""
midiModeDDL    := ""
midiCurveDDL   := ""
midiMinEdit    := ""
midiMaxEdit    := ""
midiParamItems := []
midiLearnPill  := ""
midiMapLV      := ""
enumMidiDevs   := []

CloseMidiGui(*) {
    global midiGui, midiLearnArmed
    midiLearnArmed := false
    ResetLastHover()
    CleanupSubGuiHovers()
    if IsObject(midiGui) {
        try midiGui.Destroy()
    }
    midiGui := ""
}

OpenMidiGui() {
    global midiGui, midiDevDDL, midiTargetDDL, midiParamDDL, midiModeDDL, midiCurveDDL
    global midiMinEdit, midiMaxEdit, midiLearnPill, midiMapLV, enumMidiDevs, midiLearnArmed

    if IsGuiAlive(midiGui) {
        midiGui.Show()
        return
    }

    midiLearnArmed := false
    enumMidiDevs := EnumMidiInputDevices()

    midiGui := Gui("+AlwaysOnTop -MaximizeBox", "MIDI Controller, Sliders, Encoders & Pads")
    midiGui.MarginX := 16
    midiGui.MarginY := 14
    midiGui.BackColor := "0D0D11"
    ApplySleekWindowTheme(midiGui, false)

    midiGui.AddProgress("x16 y12 w500 h2 Background0D0D11 cF59E0B", 100)
    midiGui.SetFont("s11 Bold cF4F4F5", "Segoe UI")
    midiGui.AddText("x16 y20 w500 h22 +0x200 Background0D0D11", "MIDI Controller && 1-Click MIDI Learn (winmm.dll)")
    midiGui.SetFont("s9 Norm cA1A1AA", "Segoe UI")
    midiGui.AddText("x16 y42 w500 h18 +0x200 Background0D0D11", "Bind faders, endless encoders (+/-), log curves, FX, and drum pads (Mute / Snaps / PTT).")

    midiGui.AddText("x16 y68 w500 h56 Background15151C", "")
    midiGui.SetFont("s8 Bold cF59E0B", "Segoe UI")
    midiGui.AddText("x28 y75 w476 h15 +0x200 Background15151C", "1. SELECT MIDI INPUT CONTROLLER")

    devNames := ["Disabled (None)"]
    devSel := 1
    for idx, d in enumMidiDevs {
        devNames.Push(d.idx ": " d.name)
        if (d.idx = midiDeviceIdx)
            devSel := idx + 1
    }

    midiGui.SetFont("s9 Norm cF4F4F5", "Segoe UI")
    midiDevDDL := midiGui.AddDropDownList("x28 y93 w384 Background1C1C26 cF4F4F5 Choose" devSel, devNames)
    midiDevDDL.OnEvent("Change", OnMidiDeviceSelect)

    midiGui.SetFont("s8 Bold cD4D4D8", "Segoe UI")
    refMidiBtn := midiGui.AddText("x418 y93 w86 h24 Center +0x200 Background1C1C26", "Refresh")
    refMidiBtn.OnEvent("Click", (*) => (CloseMidiGui(), OpenMidiGui()))
    RegisterButtonHover(refMidiBtn, "1C1C26", "282836", "Rescan connected MIDI controllers", false)

    midiGui.AddText("x16 y134 w500 h162 Background15151C", "")
    midiGui.SetFont("s8 Bold c38BDF8", "Segoe UI")
    midiGui.AddText("x28 y142 w476 h15 +0x200 Background15151C", "2. TARGET ACTION / PARAMETER, ENCODER MODE, CURVE & RANGE")

    chNames := []
    chSel := 1
    curActive := (activeTargets.Length > 0) ? activeTargets[1] : "Strip[7]"
    for idx, ch in allChannels {
        chNames.Push(nameMap[ch.param] "  (" ch.param ")")
        if (ch.param = curActive)
            chSel := idx
    }

    midiGui.SetFont("s9 Norm cF4F4F5", "Segoe UI")
    midiTargetDDL := midiGui.AddDropDownList("x28 y162 w232 Background1C1C26 cF4F4F5 Choose" chSel, chNames)
    midiTargetDDL.OnEvent("Change", (*) => PopulateMidiParamChoices())

    midiParamDDL := midiGui.AddDropDownList("x266 y162 w238 Background1C1C26 cF4F4F5", ["Main Channel Fader"])
    midiParamDDL.OnEvent("Change", (*) => SyncMidiRangeInputsFromChoice())

    midiGui.SetFont("s8 Bold cA1A1AA", "Segoe UI")
    midiGui.AddText("x28 y196 w42 h20 +0x200 Background15151C", "Dial:")
    midiGui.SetFont("s9 Norm cF4F4F5", "Segoe UI")
    midiModeDDL := midiGui.AddDropDownList("x72 y194 w112 Background1C1C26 cF4F4F5 Choose1", ["Absolute", "Relative (+/-)"])
    RegisterButtonHover(midiModeDDL, "", "", "Absolute = direct 0–127 sweep  •  Relative (+/-) = step from current value on endless dials", false)

    midiGui.SetFont("s8 Bold cA1A1AA", "Segoe UI")
    midiGui.AddText("x194 y196 w46 h20 +0x200 Background15151C", "Curve:")
    midiGui.SetFont("s9 Norm cF4F4F5", "Segoe UI")
    midiCurveDDL := midiGui.AddDropDownList("x242 y194 w112 Background1C1C26 cF4F4F5 Choose1", ["Linear dB", "Log Taper"])
    RegisterButtonHover(midiCurveDDL, "", "", "Linear = straight dB sweep  •  Log Taper = finer resolution near -15 dB to 0 dB", false)

    rngUnityBtn := midiGui.AddText("x362 y194 w68 h24 Center +0x200 Background1C1C26", "-60..0dB")
    rngUnityBtn.SetFont("s8 Bold cD4D4D8")
    rngUnityBtn.OnEvent("Click", (*) => (midiMinEdit.Value := "-60.0", midiMaxEdit.Value := "0.0"))
    RegisterButtonHover(rngUnityBtn, "1C1C26", "282836", "Set fader sweep from -60.0 dB to 0.0 dB unity", false)

    rngFullBtn := midiGui.AddText("x434 y194 w70 h24 Center +0x200 Background1C1C26", "-60..+12")
    rngFullBtn.SetFont("s8 Bold cD4D4D8")
    rngFullBtn.OnEvent("Click", (*) => (midiMinEdit.Value := "-60.0", midiMaxEdit.Value := "12.0"))
    RegisterButtonHover(rngFullBtn, "1C1C26", "282836", "Set full VoiceMeeter fader sweep (-60.0 dB to +12.0 dB)", false)

    midiGui.SetFont("s8 Bold cA1A1AA", "Segoe UI")
    midiGui.AddText("x28 y228 w34 h20 +0x200 Background15151C", "Min:")
    midiGui.SetFont("s9 Bold cF4F4F5", "Segoe UI")
    midiMinEdit := midiGui.AddEdit("x64 y225 w76 h23 Center Background1C1C26 cF4F4F5", "-60.0")

    midiGui.SetFont("s8 Bold cA1A1AA", "Segoe UI")
    midiGui.AddText("x148 y228 w36 h20 +0x200 Background15151C", "Max:")
    midiGui.SetFont("s9 Bold cF4F4F5", "Segoe UI")
    midiMaxEdit := midiGui.AddEdit("x186 y225 w76 h23 Center Background1C1C26 cF4F4F5", "0.0")
    PopulateMidiParamChoices()

    midiGui.SetFont("s9 Bold c38BDF8", "Segoe UI")
    midiLearnPill := midiGui.AddText("x28 y255 w476 h32 Center +0x200 Background152433", "Learn Next Input  (Click, then twist a knob/slider or hit a drum pad)")
    midiLearnPill.OnEvent("Click", ToggleMidiLearnArm)
    hoverStyleMap[midiLearnPill.Hwnd] := {
        key: "midiLearnPill",
        ctrls: [midiLearnPill],
        isMain: false,
        getBg: (*) => midiLearnArmed ? "332614" : "152433",
        hoverBg: (*) => midiLearnArmed ? "45331B" : "1C3247"
    }
    hoverHintMap["midiLearnPill"] := "Arm MIDI Learn, then move a slider/encoder or tap/hold a MIDI pad to bind it"

    midiGui.SetFont("s9 Norm cF4F4F5", "Segoe UI")
    midiMapLV := midiGui.AddListView("x16 y306 w500 h130 -Multi Background15151C cF4F4F5", ["MIDI Input", "Target", "Action / Control", "Mode / Curve", "Range"])
    try DllCall("uxtheme\SetWindowTheme", "Ptr", midiMapLV.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
    midiMapLV.ModifyCol(1, 102)
    midiMapLV.ModifyCol(2, 132)
    midiMapLV.ModifyCol(3, 118)
    midiMapLV.ModifyCol(4, 78)
    midiMapLV.ModifyCol(5, 60)
    RefreshMidiMappingsLV()

    midiGui.SetFont("s8 Bold cD4D4D8", "Segoe UI")
    delMapBtn := midiGui.AddText("x16 y444 w148 h28 Center +0x200 Background191922", "Remove Selected")
    delMapBtn.OnEvent("Click", RemoveSelectedMidiMapping)
    RegisterButtonHover(delMapBtn, "191922", "2A1A20", "Delete the highlighted MIDI mapping", false)

    clrMapBtn := midiGui.AddText("x170 y444 w124 h28 Center +0x200 Background191922", "Clear All")
    clrMapBtn.OnEvent("Click", ClearAllMidiMappings)
    RegisterButtonHover(clrMapBtn, "191922", "2A1A20", "Remove all saved MIDI mappings", false)

    midiGui.SetFont("s9 Bold c38BDF8", "Segoe UI")
    closeMidiBtn := midiGui.AddText("x426 y444 w90 h28 Center +0x200 Background152433", "Done")
    closeMidiBtn.OnEvent("Click", CloseMidiGui)
    RegisterButtonHover(closeMidiBtn, "152433", "1C3247", "", false)

    midiGui.OnEvent("Close", CloseMidiGui)
    midiGui.OnEvent("Escape", CloseMidiGui)
    midiGui.Show("AutoSize")
}

PopulateMidiParamChoices() {
    global midiParamItems
    midiParamItems := []
    labels := []

    chIdx := midiTargetDDL.Value
    param := (chIdx >= 1 && chIdx <= allChannels.Length) ? allChannels[chIdx].param : "Strip[7]"

    midiParamItems.Push({ type: "gain", val: "0", desc: "Main Fader", min: -60.0, max: 0.0 })
    labels.Push("Main Channel Fader")

    if IsInputStrip(param) {
        for idx, b in outputBuses {
            bName := nameMap.Has(b.param) ? nameMap[b.param] : b.name
            midiParamItems.Push({ type: "layer", val: String(idx), desc: b.name " Submix", min: -60.0, max: 0.0 })
            labels.Push("Submix: " b.name " (" bName ")")
        }
    }

    for fx in GetChannelEffects(param) {
        midiParamItems.Push({ type: "fx", val: fx.key, desc: "FX: " fx.label, min: fx.min, max: fx.max })
        labels.Push("FX: " fx.label)
    }

    midiParamItems.Push({ type: "pad_mute", val: "0", desc: "Pad: Toggle Mute", min: -60.0, max: 0.0 })
    labels.Push("Pad Trigger: Toggle Mute")

    midiParamItems.Push({ type: "pad_snap", val: "1", desc: "Pad: Snapshot P1", min: -60.0, max: 0.0 })
    labels.Push("Pad Trigger: Load Snapshot P1")

    midiParamItems.Push({ type: "pad_snap", val: "2", desc: "Pad: Snapshot P2", min: -60.0, max: 0.0 })
    labels.Push("Pad Trigger: Load Snapshot P2")

    midiParamItems.Push({ type: "pad_snap", val: "3", desc: "Pad: Snapshot P3", min: -60.0, max: 0.0 })
    labels.Push("Pad Trigger: Load Snapshot P3")

    midiParamItems.Push({ type: "pad_snap", val: "4", desc: "Pad: Snapshot P4", min: -60.0, max: 0.0 })
    labels.Push("Pad Trigger: Load Snapshot P4")

    midiParamItems.Push({ type: "pad_ptt", val: "0", desc: "Pad: Push-to-Talk", min: -60.0, max: 0.0 })
    labels.Push("Pad Trigger: Push-to-Talk (Hold)")

    midiParamDDL.Delete()
    midiParamDDL.Add(labels)
    midiParamDDL.Choose(1)
    SyncMidiRangeInputsFromChoice()
}

SyncMidiRangeInputsFromChoice() {
    pIdx := midiParamDDL.Value
    if (pIdx >= 1 && pIdx <= midiParamItems.Length) {
        item := midiParamItems[pIdx]
        midiMinEdit.Value := Format("{:.1f}", item.min)
        midiMaxEdit.Value := Format("{:.1f}", item.max)
    }
}

OnMidiDeviceSelect(*) {
    global midiDeviceIdx
    idx := midiDevDDL.Value
    midiDeviceIdx := (idx <= 1) ? -1 : enumMidiDevs[idx - 1].idx
    IniWrite(midiDeviceIdx, iniPath, "MIDI", "DeviceIdx")
    InitMidiDevice()
    ShowQuickTip(midiDeviceIdx >= 0 ? "MIDI Controller Connected!" : "MIDI Controller Disabled.", 1200)
}

ToggleMidiLearnArm(*) {
    global midiLearnArmed
    if (midiDeviceIdx < 0) {
        ShowQuickTip("Select your MIDI controller in the dropdown first.", 1400)
        return
    }
    midiLearnArmed := !midiLearnArmed
    if midiLearnArmed {
        midiLearnPill.SetFont("s9 Bold cFBBF24")
        midiLearnPill.Opt("Background332614")
        midiLearnPill.Value := "Listening... Twist a knob/slider or hit a MIDI pad now!"
    } else {
        midiLearnPill.SetFont("s9 Bold c38BDF8")
        midiLearnPill.Opt("Background152433")
        midiLearnPill.Value := "Learn Next Input  (Click, then twist a knob/slider or hit a drum pad)"
    }
}

RefreshMidiMappingsLV() {
    if !IsGuiAlive(midiMapLV)
        return
    midiMapLV.Delete()
    for mapKey, m in midiMappings {
        lbl := nameMap.Has(m.target) ? nameMap[m.target] : m.target
        desc := "Main Fader"
        rngStr := Format("{:.1f}..{:+.1f}", m.minDb, m.maxDb)
        mcStr := ((m.mode = "rel") ? "REL" : "ABS") " / " ((m.curve = "log") ? "LOG" : "LIN")

        if (m.type = "layer") {
            lIdx := Integer(m.val)
            desc := (lIdx > 0 && lIdx <= outputBuses.Length) ? outputBuses[lIdx].name " Submix" : "Main Fader"
        } else if (m.type = "fx") {
            fxLbl := m.val
            for fx in GetChannelEffects(m.target) {
                if (fx.key = m.val) {
                    fxLbl := fx.label
                    break
                }
            }
            desc := "FX: " fxLbl
        } else if (m.type = "pad_mute") {
            desc := "Pad: Mute Toggle"
            mcStr := "PAD"
            rngStr := "--"
        } else if (m.type = "pad_snap") {
            desc := "Pad: Snapshot P" m.val
            mcStr := "PAD"
            rngStr := "--"
        } else if (m.type = "pad_ptt") {
            desc := "Pad: Push-to-Talk"
            mcStr := "HOLD"
            rngStr := "--"
        }

        midiMapLV.Add(, mapKey, lbl, desc, mcStr, rngStr)
    }
}

RemoveSelectedMidiMapping(*) {
    row := midiMapLV.GetNext(0)
    if !row
        return
    mapKey := midiMapLV.GetText(row, 1)
    if midiMappings.Has(mapKey) {
        midiMappings.Delete(mapKey)
        SaveMidiMappings()
        RefreshMidiMappingsLV()
    }
}

ClearAllMidiMappings(*) {
    midiMappings.Clear()
    SaveMidiMappings()
    RefreshMidiMappingsLV()
}

SaveMidiMappings() {
    joined := ""
    for k, m in midiMappings
        joined .= (joined != "" ? "|" : "") k "=" m.target "," m.type "," m.val "," Format("{:.2f}", m.minDb) "," Format("{:.2f}", m.maxDb) "," m.mode "," m.curve
    IniWrite(joined, iniPath, "MIDI", "Mappings")
}

; --- Startup & GitHub Updates Window ---
startupGui      := ""
winStartChk     := ""
autoLaunchVmChk := ""
hideVmChk       := ""
chkUpdateChk    := ""
updateStatusTxt := ""

CloseStartupGui(*) {
    global startupGui
    ResetLastHover()
    CleanupSubGuiHovers()
    if IsObject(startupGui) {
        try startupGui.Destroy()
    }
    startupGui := ""
}

OpenStartupGui() {
    global startupGui, winStartChk, autoLaunchVmChk, hideVmChk, chkUpdateChk, updateStatusTxt

    if IsGuiAlive(startupGui) {
        startupGui.Show()
        return
    }

    startupGui := Gui("+AlwaysOnTop -MaximizeBox", "Startup, VoiceMeeter Boot & Updates")
    startupGui.MarginX := 16
    startupGui.MarginY := 14
    startupGui.BackColor := "0D0D11"
    ApplySleekWindowTheme(startupGui, false)

    startupGui.AddProgress("x16 y12 w480 h2 Background0D0D11 c38BDF8", 100)
    startupGui.SetFont("s11 Bold cF4F4F5", "Segoe UI")
    startupGui.AddText("x16 y20 w480 h22 +0x200 Background0D0D11", "Startup, VoiceMeeter Boot && Updates")

    startupGui.AddText("x16 y50 w480 h138 Background15151C", "")
    startupGui.SetFont("s8 Bold c38BDF8", "Segoe UI")
    startupGui.AddText("x28 y58 w456 h16 +0x200 Background15151C", "STARTUP && VOICEMEETER INTEGRATION")

    hasStartupLink := FileExist(A_Startup "\Potato Massah.lnk") ? 1 : 0
    startupGui.SetFont("s9 Norm cE4E4E7", "Segoe UI")
    winStartChk     := startupGui.AddCheckBox("x28 y80 w456 h22 Background15151C cE4E4E7 Checked" hasStartupLink, "Start Potato Massah automatically when Windows boots")
    autoLaunchVmChk := startupGui.AddCheckBox("x28 y104 w456 h22 Background15151C cE4E4E7 Checked" autoLaunchVM, "Auto-launch VoiceMeeter Potato if it is closed")
    hideVmChk       := startupGui.AddCheckBox("x28 y128 w456 h22 Background15151C cE4E4E7 Checked" hideVMOnLaunch, "Minimize/hide VoiceMeeter Potato window after auto-launch")

    startupGui.SetFont("s8 Bold cD4D4D8", "Segoe UI")
    showVmBtn := startupGui.AddText("x28 y154 w220 h24 Center +0x200 Background1C1C26", "Show VoiceMeeter Window")
    showVmBtn.OnEvent("Click", (*) => SetVoicemeeterVisibility(true))
    RegisterButtonHover(showVmBtn, "1C1C26", "282836", "", false)

    hideVmBtn := startupGui.AddText("x264 y154 w220 h24 Center +0x200 Background1C1C26", "Hide VoiceMeeter to Tray")
    hideVmBtn.OnEvent("Click", (*) => SetVoicemeeterVisibility(false))
    RegisterButtonHover(hideVmBtn, "1C1C26", "282836", "", false)

    startupGui.AddText("x16 y198 w480 h74 Background15151C", "")
    startupGui.SetFont("s8 Bold c38BDF8", "Segoe UI")
    startupGui.AddText("x28 y206 w310 h16 +0x200 Background15151C", "GITHUB RELEASES UPDATE CHECK (" APP_VERSION ")")

    startupGui.SetFont("s9 Norm cE4E4E7", "Segoe UI")
    chkUpdateChk := startupGui.AddCheckBox("x28 y226 w290 h20 Background15151C cE4E4E7 Checked" checkUpdatesStart, "Check for new releases on startup")

    startupGui.SetFont("s8 Bold c38BDF8", "Segoe UI")
    updNowBtn := startupGui.AddText("x334 y216 w150 h26 Center +0x200 Background152433", "Check GitHub Now")
    updNowBtn.OnEvent("Click", (*) => CheckForGithubUpdates(false))
    RegisterButtonHover(updNowBtn, "152433", "1C3247", "", false)

    startupGui.SetFont("s8 Norm cA1A1AA", "Segoe UI")
    updateStatusTxt := startupGui.AddText("x28 y248 w456 h16 +0x200 Background15151C", "Repo: github.com/" GITHUB_REPO)

    startupGui.SetFont("s9 Bold c38BDF8", "Segoe UI")
    saveStartupBtn := startupGui.AddText("x304 y282 w104 h28 Center +0x200 Background152433", "Save Settings")
    saveStartupBtn.OnEvent("Click", SaveStartupConfig)
    RegisterButtonHover(saveStartupBtn, "152433", "1C3247", "", false)

    startupGui.SetFont("s9 Bold cA1A1AA", "Segoe UI")
    closeStartupBtn := startupGui.AddText("x414 y282 w82 h28 Center +0x200 Background191922", "Close")
    closeStartupBtn.OnEvent("Click", CloseStartupGui)
    RegisterButtonHover(closeStartupBtn, "191922", "242432", "", false)

    startupGui.OnEvent("Close", CloseStartupGui)
    startupGui.OnEvent("Escape", CloseStartupGui)
    startupGui.Show("AutoSize")
}

SaveStartupConfig(*) {
    global autoLaunchVM, hideVMOnLaunch, checkUpdatesStart

    lnkPath := A_Startup "\Potato Massah.lnk"
    if (winStartChk.Value = 1) {
        try FileCreateShortcut(A_ScriptFullPath, lnkPath, A_ScriptDir, "", "Potato Massah — VoiceMeeter Wheel Controller", FileExist(customIconPath) ? customIconPath : "")
    } else {
        if FileExist(lnkPath)
            try FileDelete(lnkPath)
    }

    autoLaunchVM      := autoLaunchVmChk.Value
    hideVMOnLaunch    := hideVmChk.Value
    checkUpdatesStart := chkUpdateChk.Value

    IniWrite(autoLaunchVM, iniPath, "Startup", "AutoLaunchVM")
    IniWrite(hideVMOnLaunch, iniPath, "Startup", "HideVMOnLaunch")
    IniWrite(checkUpdatesStart, iniPath, "Startup", "CheckUpdatesOnStart")

    CloseStartupGui()
    ShowQuickTip("Startup & Update settings saved.", 1200)
}

; --- Comprehensive Features & User Manual Window ---
featGui := ""

CloseFeaturesGui(*) {
    global featGui
    ResetLastHover()
    CleanupSubGuiHovers()
    if IsObject(featGui) {
        try featGui.Destroy()
    }
    featGui := ""
}

OpenFeaturesGui() {
    global featGui

    if IsGuiAlive(featGui) {
        featGui.Show()
        return
    }

    tKey     := FormatHotkeyHuman(keybinds["toggleGui"])
    pttKey   := FormatHotkeyHuman(keybinds["pttHold"])
    chPrev   := FormatHotkeyHuman(keybinds["chanPrev"])
    chNext   := FormatHotkeyHuman(keybinds["chanNext"])
    lyPrev   := FormatHotkeyHuman(keybinds["layerPrev"])
    lyNext   := FormatHotkeyHuman(keybinds["layerNext"])
    fxPrev   := FormatHotkeyHuman(keybinds["fxPrev"])
    fxNext   := FormatHotkeyHuman(keybinds["fxNext"])
    fxUp     := FormatHotkeyHuman(keybinds["fxUp"])
    fxDown   := FormatHotkeyHuman(keybinds["fxDown"])
    fxFUp    := FormatHotkeyHuman(keybinds["fxFineUp"])
    fxFDn    := FormatHotkeyHuman(keybinds["fxFineDown"])
    fxRst    := FormatHotkeyHuman(keybinds["fxReset"])
    dkTog    := FormatHotkeyHuman(keybinds["toggleDuck"])
    lkTog    := FormatHotkeyHuman(keybinds["toggleLock"])
    sn1      := FormatHotkeyHuman(keybinds["snap1"])
    sn2      := FormatHotkeyHuman(keybinds["snap2"])
    sn3      := FormatHotkeyHuman(keybinds["snap3"])

    boundList := ""
    for ch in allChannels {
        hk := keybinds["target_" ch.param]
        if (hk != "")
            boundList .= (boundList != "" ? "  •  " : "") nameMap[ch.param] " [" FormatHotkeyHuman(hk) "]"
    }
    if (boundList = "")
        boundList := "None assigned yet (click Keybinds to add any channel shortcut)"

    guideText := (
        "1. HARDWARE VOLUME WHEEL & SMOOTH GLIDE ENGINE`r`n"
        . "Takes over your keyboard/mouse Volume Up, Volume Down, and Mute keys and routes them straight into VoiceMeeter Potato—preventing Windows master volume changes and hiding the bulky Windows volume popup.`r`n"
        . "• Precision & Speed Scaling: Slow single clicks trim by 0.2 dB for pinpoint adjustments; fast wheel spins accelerate smoothly up to 4.5 dB per notch with 20 ms fader interpolation and instant direction-reversal braking.`r`n`r`n"
        . "2. SOLO (PFL), BUS MONO CHECK & PEAK CLIP ALERTS`r`n"
        . "• Hardware Strip Solo [S] & Hero SOLO: Isolates a hardware input strip (or active target) in headphones (Strip[i].Solo) for quick mic/instrument checks.`r`n"
        . "• Output Bus Mono [M]: Toggles mono summing on any output bus (Bus[i].Mono) to check phase and mix translation.`r`n"
        . "• Peak Clip Alert: Flags sustained 0.0 dBFS clipping across consecutive meter samples without false-triggering on idle or muted strips.`r`n`r`n"
        . "3. MOUSE SHORTCUTS & INLINE MIXER CONTROLS (NO KEYBOARD NEEDED)`r`n"
        . "• Hover-Scroll Any Channel: Point your cursor over any channel pill and roll your mouse wheel (±1.0 dB per notch) to adjust that fader directly without changing your active wheel target.`r`n"
        . "• Gradual Fine Control (Shift + Scroll): Hold Shift while scrolling over any channel row for ultra-fine ±0.2 dB increments.`r`n"
        . "• Middle-Click to Mute: Middle-click any channel pill (or click MUTE in the top Hero Card) to toggle mute with your mouse.`r`n"
        . "• Rename Any Channel (✎): Click the pencil icon (or right-click) on ANY Virtual Input, Hardware Input, or Output Bus.`r`n"
        . "• Instant Unity Reset (0dB): Click 0dB on any row to snap that fader (or active submix layer) straight back to 0.0 dB.`r`n`r`n"
        . "4. PUSH-TO-TALK (AUTO-MUTE MICROPHONE)`r`n"
        . "• Click the 'PTT' pill in Automation & Protection (right-click to choose your microphone strip and bind your Push-to-Talk key [" pttKey "]). When enabled, Potato Massah keeps your mic muted and unmutes it ONLY while you hold the PTT key.`r`n`r`n"
        . "5. PLUG-AND-PLAY MIDI LEARN (FADERS, ENCODERS, LOG CURVES & PADS)`r`n"
        . "• Faders, Submix Layers & FX/EQ: Map any knob or slider with custom Min/Max dB bounds, choose Absolute (0–127) or Relative (+/-) for endless encoders, and pick Linear dB or Log Taper for smoother throw.`r`n"
        . "• Drum Pads & Buttons: Bind Note On/Off or button CCs to Toggle Mute, fire Snapshots P1–P4, or act as a MIDI Push-to-Talk button with live Floating HUD feedback.`r`n`r`n"
        . "6. PRO DRAWER: PER-BUS GAIN LAYERS, SYNC DELAY, ROUTING & SNAPSHOTS (AMBER)`r`n"
        . "• Per-Bus Submix Gain Layers: Press " lyPrev " / " lyNext " (or left/right-click the Layer pill) while an Input Strip is selected to switch between Master Gain and individual output bus submixes (A1–A5, B1–B3).`r`n"
        . "• Monitoring Synchro Delay (A1–A5): Select any hardware output bus (A1–A5) to turn the Pro Layer bar into a live Sync Delay bar (0–500 ms). Hold Shift + Scroll (±1 ms), Ctrl + Shift + Scroll (±10 ms), or Shift + Right-Click to reset to 0 ms.`r`n"
        . "• Strip Output Routing Matrix (A1–B3): Click any A1–B3 badge to toggle where the selected input strip sends audio.`r`n"
        . "• 3 Quick Mixer Snapshots (P1, P2, P3): Right-click P1–P3 to save all 16 fader levels, A1–A5 sync delays, and A1–B3 routes; left-click (or press " sn1 " / " sn2 " / " sn3 ") to recall them instantly.`r`n`r`n"
        . "7. CHANNEL CYCLING, SOLO FX & AUTOMATION SUITE`r`n"
        . "• Step Through All 16 Channels: " chPrev " / " chNext "  •  Solo FX: " fxPrev " / " fxNext " (" fxUp " / " fxDown ", fine " fxFUp " / " fxFDn ", reset " fxRst ").`r`n"
        . "• Auto-Reset on Device Reconnect  •  Windows Default Device Lock [" lkTog "]  •  Sidechain Auto-Ducking [" dkTog "].`r`n`r`n"
        . "8. FLOATING POP-UP HUD & SHORTCUTS`r`n"
        . "• Toggle Window: " tKey "  •  Currently Bound Channel Shortcuts: " boundList "."
    )

    featGui := Gui("+AlwaysOnTop -MaximizeBox", "VoiceMeeter Potato Massah — Complete User Guide (" APP_VERSION ")")
    featGui.MarginX := 16
    featGui.MarginY := 14
    featGui.BackColor := "0D0D11"
    ApplySleekWindowTheme(featGui, false)

    featGui.AddProgress("x16 y12 w540 h2 Background0D0D11 c38BDF8", 100)
    featGui.SetFont("s11 Bold cF4F4F5", "Segoe UI")
    featGui.AddText("x16 y20 w540 h22 +0x200 Background0D0D11", "Potato Massah " APP_VERSION " — Features, Controls && Shortcuts")

    featGui.SetFont("s9 Norm c38BDF8", "Segoe UI")
    featGui.AddText("x16 y42 w540 h18 +0x200 Background0D0D11", "Displays your live custom keybinds  •  All preferences auto-save to volume_settings.ini")

    featGui.SetFont("s9 Norm cE4E4E7", "Segoe UI")
    featEdit := featGui.AddEdit("x16 y68 w540 h410 ReadOnly -WantReturn +VScroll Background15151C cE4E4E7", guideText)
    try DllCall("uxtheme\SetWindowTheme", "Ptr", featEdit.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)

    featGui.SetFont("s9 Bold c38BDF8", "Segoe UI")
    openKbFromFeat := featGui.AddText("x16 y488 w150 h28 Center +0x200 Background152433", "Edit Keybinds...")
    openKbFromFeat.OnEvent("Click", (*) => (CloseFeaturesGui(), OpenKeybindGui()))
    RegisterButtonHover(openKbFromFeat, "152433", "1C3247", "", false)

    featGui.SetFont("s9 Bold cF59E0B", "Segoe UI")
    openMidiFromFeat := featGui.AddText("x174 y488 w150 h28 Center +0x200 Background261E12", "MIDI Learn...")
    openMidiFromFeat.OnEvent("Click", (*) => (CloseFeaturesGui(), OpenMidiGui()))
    RegisterButtonHover(openMidiFromFeat, "261E12", "382B19", "", false)

    featGui.SetFont("s9 Bold cF4F4F5", "Segoe UI")
    closeFeatBtn := featGui.AddText("x466 y488 w90 h28 Center +0x200 Background191922", "Close")
    closeFeatBtn.OnEvent("Click", CloseFeaturesGui)
    RegisterButtonHover(closeFeatBtn, "191922", "242432", "", false)

    featGui.OnEvent("Close", CloseFeaturesGui)
    featGui.OnEvent("Escape", CloseFeaturesGui)
    featGui.Show("AutoSize")
}

; ==============================================================================
; 6. KEYBIND MANAGER GUI & INTERACTIVE COMBO CAPTURE (2-COLUMN LAYOUT)
; ==============================================================================
kbGui           := ""
kbBtnMap        := Map()
kbLabelMap      := Map()
kbStatusLabel   := ""
activeInputHook := ""

FormatHotkeyHuman(hk) {
    if (hk = "")
        return "Unbound"

    out := ""
    rest := hk
    while (StrLen(rest) > 1) {
        prefix := SubStr(rest, 1, 1)
        if (prefix = "^") {
            out .= "Ctrl + "
            rest := SubStr(rest, 2)
        } else if (prefix = "!") {
            out .= "Alt + "
            rest := SubStr(rest, 2)
        } else if (prefix = "+") {
            out .= "Shift + "
            rest := SubStr(rest, 2)
        } else if (prefix = "#") {
            out .= "Win + "
            rest := SubStr(rest, 2)
        } else {
            break
        }
    }

    if (StrLen(rest) = 1)
        rest := StrUpper(rest)
    return out . rest
}

CleanKeyName(hk) {
    base := RegExReplace(hk, "^[\^\!\+\#\*~\$<>]+", "")
    return (base != "") ? base : hk
}

RegisterAllHotkeys() {
    global pttUpHotkey
    for oldHk in registeredHotkeys {
        try Hotkey(oldHk, "Off")
    }
    registeredHotkeys.Clear()

    if (pttUpHotkey != "") {
        try Hotkey(pttUpHotkey, "Off")
        pttUpHotkey := ""
    }

    for item in hotkeyDefs {
        hk := keybinds[item.id]
        if (hk != "") {
            try {
                Hotkey(hk, item.fn, "On")
                registeredHotkeys[hk] := item.id
            }
        }
    }

    pttHk := keybinds["pttHold"]
    if (pttHk != "") {
        baseKey := CleanKeyName(pttHk)
        upSpec := "~*" baseKey " up"
        try {
            Hotkey(upSpec, (*) => OnPttKeyUp(), "On")
            pttUpHotkey := upSpec
        }
    }

    RefreshShortcutLabels()
}

RefreshShortcutLabels() {
    global defaultFooterHint
    tKey := FormatHotkeyHuman(keybinds["toggleGui"])
    boundCount := 0
    for ch in allChannels {
        if (keybinds["target_" ch.param] != "")
            boundCount += 1
    }
    defaultFooterHint := tKey ": Panel  •  " boundCount " channel shortcut" (boundCount = 1 ? "" : "s") " active  •  Hover for tips"
    if (lastHoverKey = "")
        UpdateSmartFooterHint("")

    targetSub := Menu()
    for ch in allChannels {
        hkStr := keybinds["target_" ch.param]
        suffix := (hkStr != "") ? "  (" FormatHotkeyHuman(hkStr) ")" : ""
        targetSub.Add(nameMap[ch.param] suffix, ApplyQuickPreset.Bind(ch.param))
    }

    A_TrayMenu.Delete()
    A_TrayMenu.Add("Open Control Panel (" tKey ")", (*) => ToggleGui())
    A_TrayMenu.Add("Quick Target", targetSub)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Auto-Reset on Device Reconnect", ToggleAutoResetDevice)
    if (autoResetDevice = 1)
        A_TrayMenu.Check("Auto-Reset on Device Reconnect")
    A_TrayMenu.Add("Windows Default Device Lock", ToggleDeviceLock)
    if (deviceLockEnabled = 1)
        A_TrayMenu.Check("Windows Default Device Lock")
    A_TrayMenu.Add("Auto-Ducking", ToggleAutoDuck)
    if (duckEnabled = 1)
        A_TrayMenu.Check("Auto-Ducking")
    A_TrayMenu.Add("Push-to-Talk (Auto-Mute Mic)", TogglePushToTalk)
    if (pttEnabled = 1)
        A_TrayMenu.Check("Push-to-Talk (Auto-Mute Mic)")
    A_TrayMenu.Add()
    A_TrayMenu.Add("Configure Push-to-Talk...", (*) => OpenPttGui())
    A_TrayMenu.Add("MIDI Learn...", (*) => OpenMidiGui())
    A_TrayMenu.Add("Configure Auto-Ducking...", (*) => OpenDuckingGui())
    A_TrayMenu.Add("Configure Anti-Hijack...", (*) => OpenAntiHijackGui())
    A_TrayMenu.Add("Startup && Updates...", (*) => OpenStartupGui())
    A_TrayMenu.Add("Configure Keybinds...", (*) => OpenKeybindGui())
    A_TrayMenu.Add("Features && Guide...", (*) => OpenFeaturesGui())
    A_TrayMenu.Add("Restart Audio Engine", (*) => RestartAudioEngine())
    A_TrayMenu.Add("Reload Script", (*) => Reload())
    A_TrayMenu.Add("Exit", (*) => ExitApp())
    A_TrayMenu.Default := "Open Control Panel (" tKey ")"
    A_TrayMenu.ClickCount := 1
}

CloseKeybindGui(*) {
    global kbGui, activeInputHook
    ResetLastHover()
    CleanupSubGuiHovers()
    if (activeInputHook != "") {
        try activeInputHook.Stop()
        activeInputHook := ""
    }
    Suspend(0)
    if IsObject(kbGui) {
        try kbGui.Destroy()
    }
    kbGui := ""
}

AddKeybindRow(targetGui, item, xBase, yPos) {
    displayLabel := (item.param != "" && nameMap.Has(item.param)) ? nameMap[item.param] : item.label
    hkVal := keybinds[item.id]
    isBound := (hkVal != "")
    actionId := item.id

    targetGui.SetFont("s9 Norm cE4E4E7", "Segoe UI")
    lblCtrl := targetGui.AddText("x" xBase " y" yPos " w154 h23 +0x200 Background0D0D11", displayLabel)
    kbLabelMap[actionId] := lblCtrl

    targetGui.SetFont("s8 Bold c" (isBound ? "38BDF8" : "71717A"), "Segoe UI")
    bindBtn := targetGui.AddText("x" (xBase + 158) " y" yPos " w132 h23 Center +0x200 Background" (isBound ? "152433" : "16161E"), FormatHotkeyHuman(hkVal))
    bindBtn.OnEvent("Click", CaptureHotkeyForAction.Bind(actionId))
    kbBtnMap[actionId] := bindBtn
    hoverStyleMap[bindBtn.Hwnd] := {
        key: "kb_" actionId,
        ctrls: [bindBtn],
        isMain: false,
        getBg: (*) => (keybinds[actionId] != "") ? "152433" : "16161E",
        hoverBg: (*) => (keybinds[actionId] != "") ? "1C3247" : "20202C"
    }

    targetGui.SetFont("s8 Bold cA1A1AA", "Segoe UI")
    clrBtn := targetGui.AddText("x" (xBase + 294) " y" yPos " w26 h23 Center +0x200 Background191922", Chr(0x2715))
    clrBtn.OnEvent("Click", ClearSingleHotkey.Bind(actionId))
    RegisterButtonHover(clrBtn, "191922", "2A1A20", "Clear this shortcut", false)
}

OpenKeybindGui() {
    global kbGui, kbBtnMap, kbLabelMap, kbStatusLabel

    if IsGuiAlive(kbGui) {
        kbGui.Show()
        return
    }

    kbBtnMap   := Map()
    kbLabelMap := Map()

    kbGui := Gui("+AlwaysOnTop -MaximizeBox", "Configure Keybinds — All Controls & Channels")
    kbGui.MarginX := 16
    kbGui.MarginY := 14
    kbGui.BackColor := "0D0D11"
    kbGui.SetFont("s10 cF4F4F5", "Segoe UI")
    ApplySleekWindowTheme(kbGui, false)

    kbGui.AddProgress("x16 y12 w664 h2 Background0D0D11 c38BDF8", 100)
    kbGui.SetFont("s11 Bold cF4F4F5", "Segoe UI")
    kbGui.AddText("x16 y20 w664 h22 +0x200 Background0D0D11", "Keyboard Shortcuts (All Inputs, Outputs, Layers && FX)")
    kbGui.SetFont("s9 Norm c38BDF8", "Segoe UI")
    kbStatusLabel := kbGui.AddText("x16 y42 w664 h18 +0x200 Background0D0D11", "Click any shortcut pill, then press your desired key combination.")

    yLeft := 70
    kbGui.SetFont("s8 Bold c71717A", "Segoe UI")
    kbGui.AddText("x16 y" yLeft " w320 h16 +0x200 Background0D0D11", "GENERAL, PUSH-TO-TALK, LAYERS && FX")
    yLeft += 20

    for item in hotkeyDefs {
        if (item.group = "general") {
            AddKeybindRow(kbGui, item, 16, yLeft)
            yLeft += 25
        }
    }

    yLeft += 10
    kbGui.SetFont("s8 Bold c71717A", "Segoe UI")
    kbGui.AddText("x16 y" yLeft " w320 h16 +0x200 Background0D0D11", "VIRTUAL INPUTS")
    yLeft += 20

    for item in hotkeyDefs {
        if (item.group = "virtual") {
            AddKeybindRow(kbGui, item, 16, yLeft)
            yLeft += 25
        }
    }

    yRight := 70
    kbGui.SetFont("s8 Bold c71717A", "Segoe UI")
    kbGui.AddText("x360 y" yRight " w320 h16 +0x200 Background0D0D11", "HARDWARE INPUTS")
    yRight += 20

    for item in hotkeyDefs {
        if (item.group = "hardware") {
            AddKeybindRow(kbGui, item, 360, yRight)
            yRight += 25
        }
    }

    yRight += 10
    kbGui.SetFont("s8 Bold c71717A", "Segoe UI")
    kbGui.AddText("x360 y" yRight " w320 h16 +0x200 Background0D0D11", "OUTPUT BUSES")
    yRight += 20

    for item in hotkeyDefs {
        if (item.group = "bus") {
            AddKeybindRow(kbGui, item, 360, yRight)
            yRight += 25
        }
    }

    yBottom := Max(yLeft, yRight) + 12
    kbGui.AddText("x16 y" (yBottom - 6) " w664 h1 Background22222E", "")

    kbGui.SetFont("s8 Bold cD4D4D8", "Segoe UI")
    defBtn := kbGui.AddText("x16 y" yBottom " w130 h28 Center +0x200 Background191922", "Reset Defaults")
    defBtn.OnEvent("Click", ResetDefaultHotkeys)
    RegisterButtonHover(defBtn, "191922", "242432", "Restore all default shortcuts", false)

    clrAllChBtn := kbGui.AddText("x154 y" yBottom " w164 h28 Center +0x200 Background191922", "Unbind All Channels")
    clrAllChBtn.OnEvent("Click", ClearAllChannelHotkeys)
    RegisterButtonHover(clrAllChBtn, "191922", "242432", "Clear all per-channel jump shortcuts", false)

    pttCfgBtn := kbGui.AddText("x326 y" yBottom " w154 h28 Center +0x200 Background191922", "PTT Mic Settings...")
    pttCfgBtn.OnEvent("Click", (*) => (CloseKeybindGui(), OpenPttGui()))
    RegisterButtonHover(pttCfgBtn, "191922", "242432", "Choose Push-to-Talk microphone strip and key", false)

    kbGui.SetFont("s8 Bold c38BDF8", "Segoe UI")
    doneBtn := kbGui.AddText("x590 y" yBottom " w90 h28 Center +0x200 Background152433", "Done")
    doneBtn.OnEvent("Click", CloseKeybindGui)
    RegisterButtonHover(doneBtn, "152433", "1C3247", "", false)

    kbGui.OnEvent("Close", CloseKeybindGui)
    kbGui.OnEvent("Escape", CloseKeybindGui)
    kbGui.Show("AutoSize")
}

UpdateKeybindBtnStyle(actionId) {
    if !kbBtnMap.Has(actionId)
        return
    btn := kbBtnMap[actionId]
    hk := keybinds[actionId]
    if (hk != "") {
        btn.SetFont("s8 Bold c38BDF8")
        btn.Opt("Background152433")
        btn.Value := FormatHotkeyHuman(hk)
    } else {
        btn.SetFont("s8 Bold c71717A")
        btn.Opt("Background16161E")
        btn.Value := "Unbound"
    }
}

CaptureHotkeyForAction(actionId, btnCtrl, *) {
    global activeInputHook

    if (activeInputHook != "") {
        try activeInputHook.Stop()
    }

    Suspend(1)
    btnCtrl.SetFont("s8 Bold cFBBF24")
    btnCtrl.Opt("Background2A2212")
    btnCtrl.Value := "Press combo... (Esc)"
    kbStatusLabel.SetFont("s9 Bold cFBBF24")
    kbStatusLabel.Value := "Listening... hold modifiers (Ctrl/Alt/Shift) and press a key"

    ih := InputHook("L0")
    activeInputHook := ih
    ih.KeyOpt("{All}", "E")
    ih.KeyOpt("{LCtrl}{RCtrl}{LAlt}{RAlt}{LShift}{RShift}{LWin}{RWin}{Ctrl}{Alt}{Shift}", "-E")
    ih.Start()
    ih.Wait()

    activeInputHook := ""
    Suspend(0)

    if (ih.EndReason != "EndKey") {
        UpdateKeybindBtnStyle(actionId)
        kbStatusLabel.SetFont("s9 Norm c38BDF8")
        kbStatusLabel.Value := "Capture cancelled."
        return
    }

    endKey := ih.EndKey

    rawMods := RegExReplace(ih.EndMods, "[<>]")
    if (!InStr(rawMods, "^") && (GetKeyState("Ctrl", "P") || GetKeyState("LCtrl", "P") || GetKeyState("RCtrl", "P")))
        rawMods .= "^"
    if (!InStr(rawMods, "!") && (GetKeyState("Alt", "P") || GetKeyState("LAlt", "P") || GetKeyState("RAlt", "P")))
        rawMods .= "!"
    if (!InStr(rawMods, "+") && (GetKeyState("Shift", "P") || GetKeyState("LShift", "P") || GetKeyState("RShift", "P")))
        rawMods .= "+"
    if (!InStr(rawMods, "#") && (GetKeyState("LWin", "P") || GetKeyState("RWin", "P")))
        rawMods .= "#"

    mods := ""
    if InStr(rawMods, "^")
        mods .= "^"
    if InStr(rawMods, "!")
        mods .= "!"
    if InStr(rawMods, "+")
        mods .= "+"
    if InStr(rawMods, "#")
        mods .= "#"

    if (endKey = "Escape" && mods = "") {
        UpdateKeybindBtnStyle(actionId)
        kbStatusLabel.SetFont("s9 Norm c38BDF8")
        kbStatusLabel.Value := "Capture cancelled."
        return
    }

    newHk := mods . endKey

    replacedLabel := ""
    for item in hotkeyDefs {
        if (item.id != actionId && keybinds[item.id] = newHk) {
            keybinds[item.id] := ""
            IniWrite("", iniPath, "Hotkeys", item.id)
            UpdateKeybindBtnStyle(item.id)
            replacedLabel := (item.param != "" && nameMap.Has(item.param)) ? nameMap[item.param] : item.label
        }
    }

    keybinds[actionId] := newHk
    IniWrite(newHk, iniPath, "Hotkeys", actionId)
    RegisterAllHotkeys()

    UpdateKeybindBtnStyle(actionId)
    kbStatusLabel.SetFont("s9 Norm c38BDF8")
    if (replacedLabel != "")
        kbStatusLabel.Value := "Bound " FormatHotkeyHuman(newHk) " (unbound from " replacedLabel ")."
    else
        kbStatusLabel.Value := "Saved shortcut: " FormatHotkeyHuman(newHk)
}

ClearSingleHotkey(actionId, *) {
    keybinds[actionId] := ""
    IniWrite("", iniPath, "Hotkeys", actionId)
    RegisterAllHotkeys()
    UpdateKeybindBtnStyle(actionId)
    kbStatusLabel.SetFont("s9 Norm c38BDF8")
    kbStatusLabel.Value := "Shortcut cleared."
}

ClearAllChannelHotkeys(*) {
    for item in hotkeyDefs {
        if (item.group != "general") {
            keybinds[item.id] := ""
            IniWrite("", iniPath, "Hotkeys", item.id)
            UpdateKeybindBtnStyle(item.id)
        }
    }
    RegisterAllHotkeys()
    kbStatusLabel.SetFont("s9 Norm c38BDF8")
    kbStatusLabel.Value := "All input/output channel shortcuts unbound."
}

ResetDefaultHotkeys(*) {
    for item in hotkeyDefs {
        keybinds[item.id] := item.def
        IniWrite(item.def, iniPath, "Hotkeys", item.id)
        UpdateKeybindBtnStyle(item.id)
    }
    RegisterAllHotkeys()
    kbStatusLabel.SetFont("s9 Norm c38BDF8")
    kbStatusLabel.Value := "All shortcuts restored to defaults."
}

; ==============================================================================
; 7. VOLUME WHEEL, SOLO / MONO, CLIP METER, PTT, MIDI ENGINE & SOLO FX
; ==============================================================================
Volume_Up::QueueWheelStep(1)
Volume_Down::QueueWheelStep(-1)
Volume_Mute::ToggleVMMute()

#HotIf GetHoveredChannel() != ""
WheelUp::HoverWheelStep(1, 1.0)
WheelDown::HoverWheelStep(-1, 1.0)
+WheelUp::HoverWheelStep(1, 0.2)
+WheelDown::HoverWheelStep(-1, 0.2)
#HotIf

#HotIf IsHoveringSyncDelayPill()
WheelUp::
WheelDown::ShowQuickTip("Safety Lock: Hold Shift + Scroll to adjust Sync Delay", 1100)
+WheelUp::AdjustHoveredBusSyncDelay(1)
+WheelDown::AdjustHoveredBusSyncDelay(-1)
^+WheelUp::AdjustHoveredBusSyncDelay(10)
^+WheelDown::AdjustHoveredBusSyncDelay(-10)
#HotIf

IsStripSoloed(param) {
    if (!vm.connected || !IsInputStrip(param))
        return false
    v := 0.0
    DllCall(pGetFloat, "AStr", param ".Solo", "Float*", &v)
    return (v >= 0.5)
}

ToggleStripSolo(param, *) {
    if (!vm.connected || !IsInputStrip(param))
        return
    cur := 0.0
    DllCall(pGetFloat, "AStr", param ".Solo", "Float*", &cur)
    nxt := (cur >= 0.5) ? 0.0 : 1.0
    DllCall(pSetFloat, "AStr", param ".Solo", "Float", nxt)
    vm.lastWriteTick := A_TickCount
    SetTimer(FlushOwnDirtyFlag, -350)
    RefreshRowSoloMonoButtons()
    RefreshHeroSoloMonoPills()
    ShowQuickTip(nameMap[param] " Solo (PFL): " (nxt >= 0.5 ? "ON" : "OFF"), 1100)
}

IsActiveTargetSoloed() {
    if (!vm.connected || activeTargets.Length = 0)
        return false
    p := activeTargets[1]
    return IsInputStrip(p) && IsStripSoloed(p)
}

ToggleActiveSolo(*) {
    if (!vm.connected || activeTargets.Length = 0)
        return
    p := activeTargets[1]
    if !IsInputStrip(p) {
        ShowQuickTip("Solo (PFL) is available on Input Strips.", 1200)
        return
    }
    ToggleStripSolo(p)
}

IsBusMono(param) {
    if !vm.connected
        return false
    v := 0.0
    DllCall(pGetFloat, "AStr", param ".Mono", "Float*", &v)
    return (v >= 0.5)
}

ToggleBusMono(param, *) {
    if !vm.connected
        return
    cur := 0.0
    DllCall(pGetFloat, "AStr", param ".Mono", "Float*", &cur)
    nxt := (cur >= 0.5) ? 0.0 : 1.0
    DllCall(pSetFloat, "AStr", param ".Mono", "Float", nxt)
    vm.lastWriteTick := A_TickCount
    SetTimer(FlushOwnDirtyFlag, -350)
    RefreshRowSoloMonoButtons()
    ShowQuickTip(nameMap[param] " Mono: " (nxt >= 0.5 ? "ON" : "OFF"), 1100)
}

RefreshHeroSoloMonoPills() {
    static lastSoloSig := ""
    on := IsActiveTargetSoloed()
    sig := on ? "1" : "0"
    if (sig = lastSoloSig)
        return
    lastSoloSig := sig
    heroSoloPill.SetFont("s7 Bold c" (on ? "FBBF24" : "A1A1AA"))
    heroSoloPill.Opt("Background" (on ? "423114" : "1E1E28"))
}

RefreshRowSoloMonoButtons() {
    static lastActCache := Map()
    for param, vis in rowVisualMap {
        if (vis.actBtn = "")
            continue
        if (vis.actType = "solo") {
            on := IsStripSoloed(param)
            sig := on ? "S1" : "S0"
            if (!lastActCache.Has(param) || lastActCache[param] != sig) {
                lastActCache[param] := sig
                vis.actBtn.SetFont("s7 Bold c" (on ? "FBBF24" : "A1A1AA"))
                vis.actBtn.Opt("Background" (on ? "423114" : "1C1C26"))
            }
        } else if (vis.actType = "mono") {
            on := IsBusMono(param)
            sig := on ? "M1" : "M0"
            if (!lastActCache.Has(param) || lastActCache[param] != sig) {
                lastActCache[param] := sig
                vis.actBtn.SetFont("s7 Bold c" (on ? "38BDF8" : "A1A1AA"))
                vis.actBtn.Opt("Background" (on ? "193B4D" : "1C1C26"))
            }
        }
    }
}

PollPeakClipping() {
    if (!vm.connected || !pGetLevel)
        return

    now := A_TickCount
    changed := false

    for st in inputStrips {
        mVal := 0.0
        DllCall(pGetFloat, "AStr", st.param ".Mute", "Float*", &mVal)
        gVal := 0.0
        DllCall(pGetFloat, "AStr", st.param ".Gain", "Float*", &gVal)

        lL := 0.0, lR := 0.0
        DllCall(pGetLevel, "Int", 1, "Int", st.idx * 8, "Float*", &lL)
        DllCall(pGetLevel, "Int", 1, "Int", (st.idx * 8) + 1, "Float*", &lR)

        rawClip := (mVal < 0.5 && gVal > -59.5 && Max(lL, lR) >= 1.0)
        prevStreak := clipStreak.Has(st.param) ? clipStreak[st.param] : 0
        curStreak := rawClip ? (prevStreak + 1) : 0
        clipStreak[st.param] := curStreak

        if (curStreak >= 3)
            clipHoldUntil[st.param] := now + 900

        activeClip := clipHoldUntil.Has(st.param) && (now < clipHoldUntil[st.param])
        wasClip := clippingChannels.Has(st.param) ? clippingChannels[st.param] : false
        if (activeClip != wasClip) {
            clippingChannels[st.param] := activeClip
            changed := true
        }
    }

    for idx, b in outputBuses {
        bIdx := idx - 1
        mVal := 0.0
        DllCall(pGetFloat, "AStr", b.param ".Mute", "Float*", &mVal)
        gVal := 0.0
        DllCall(pGetFloat, "AStr", b.param ".Gain", "Float*", &gVal)

        lL := 0.0, lR := 0.0
        DllCall(pGetLevel, "Int", 2, "Int", bIdx * 8, "Float*", &lL)
        DllCall(pGetLevel, "Int", 2, "Int", (bIdx * 8) + 1, "Float*", &lR)

        rawClip := (mVal < 0.5 && gVal > -59.5 && Max(lL, lR) >= 1.0)
        prevStreak := clipStreak.Has(b.param) ? clipStreak[b.param] : 0
        curStreak := rawClip ? (prevStreak + 1) : 0
        clipStreak[b.param] := curStreak

        if (curStreak >= 3)
            clipHoldUntil[b.param] := now + 900

        activeClip := clipHoldUntil.Has(b.param) && (now < clipHoldUntil[b.param])
        wasClip := clippingChannels.Has(b.param) ? clippingChannels[b.param] : false
        if (activeClip != wasClip) {
            clippingChannels[b.param] := activeClip
            changed := true
        }
    }

    if (changed && DllCall("IsWindowVisible", "Ptr", settingsGui.Hwnd))
        RefreshChannelVisuals()
}

TogglePushToTalk(*) {
    global pttEnabled, pttHeldActive
    if (pttEnabled = 0) {
        if (keybinds["pttHold"] = "") {
            OpenPttGui()
            ShowQuickTip("Set a Push-to-Talk key first.", 1300)
            return
        }
        pttEnabled := 1
        pttHeldActive := false
    } else {
        pttEnabled := 0
        pttHeldActive := false
        SetTimer(WatchPttKey, 0)
    }

    IniWrite(pttEnabled, iniPath, "PushToTalk", "Enabled")
    ApplyPttMicState()
    RefreshAutomationPills()
    RefreshShortcutLabels()
    ShowQuickTip("Push-to-Talk (" nameMap[pttMicStrip] "): " (pttEnabled ? "ON (Muted until held)" : "OFF"), 1300)
}

ApplyPttMicState() {
    if (!vm.connected || pttMicStrip = "")
        return
    shouldMute := (pttEnabled = 1 && !pttHeldActive)
    DllCall(pSetFloat, "AStr", pttMicStrip ".Mute", "Float", shouldMute ? 1.0 : 0.0)
    vm.mutes[pttMicStrip] := shouldMute
    vm.lastWriteTick := A_TickCount
    SetTimer(FlushOwnDirtyFlag, -350)
    UpdateTrayIcon(IsAnyActiveTargetMuted())
    if DllCall("IsWindowVisible", "Ptr", settingsGui.Hwnd) {
        UpdateStatusBanner()
        RefreshAllChannelReadouts(true)
    }
}

OnPttKeyDown() {
    Critical
    global pttHeldActive
    if (pttEnabled != 1 || pttHeldActive)
        return
    pttHeldActive := true
    ApplyPttMicState()
    SetTimer(WatchPttKey, 30)
}

OnPttKeyUp() {
    Critical
    global pttHeldActive
    if !pttHeldActive
        return
    pttHeldActive := false
    SetTimer(WatchPttKey, 0)
    if (pttEnabled = 1)
        ApplyPttMicState()
}

WatchPttKey() {
    global pttHeldActive
    if (!pttHeldActive || pttEnabled != 1) {
        SetTimer(WatchPttKey, 0)
        return
    }
    pttHk := keybinds["pttHold"]
    if (pttHk = "" || !GetKeyState(CleanKeyName(pttHk), "P")) {
        OnPttKeyUp()
    }
}

EnumMidiInputDevices() {
    devs := []
    cnt := DllCall("winmm\midiInGetNumDevs", "UInt")
    caps := Buffer(84, 0)
    Loop cnt {
        idx := A_Index - 1
        if (DllCall("winmm\midiInGetDevCapsW", "UPtr", idx, "Ptr", caps.Ptr, "UInt", 84, "UInt") = 0)
            devs.Push({ idx: idx, name: StrGet(caps.Ptr + 8, 32, "UTF-16") })
    }
    return devs
}

InitMidiDevice() {
    global midiHandle, midiDeviceIdx
    CloseMidiDevice()
    if (midiDeviceIdx < 0)
        return
    hMidi := 0
    res := DllCall("winmm\midiInOpen", "Ptr*", &hMidi, "UInt", midiDeviceIdx, "UPtr", settingsGui.Hwnd, "UPtr", 0, "UInt", 0x10000, "UInt")
    if (res = 0 && hMidi) {
        midiHandle := hMidi
        DllCall("winmm\midiInStart", "Ptr", midiHandle, "UInt")
    } else {
        midiHandle := 0
    }
}

CloseMidiDevice() {
    global midiHandle
    if midiHandle {
        try DllCall("winmm\midiInStop", "Ptr", midiHandle, "UInt")
        try DllCall("winmm\midiInClose", "Ptr", midiHandle, "UInt")
        midiHandle := 0
    }
}

MapMidiRawToNorm(val, curve) {
    norm := Max(0.0, Min(1.0, val / 127.0))
    if (curve = "log")
        return norm ** 1.35
    return norm
}

GetRelativeEncoderDelta(val, unitStep) {
    if (val = 0)
        return 0.0
    if (val >= 1 && val <= 63)
        return Float(val) * unitStep
    if (val >= 65 && val <= 127)
        return -Float(128 - val) * unitStep
    return 0.0
}

WatchMidiPttHeld() {
    global midiHeldPads
    if (midiHeldPads.Count = 0) {
        SetTimer(WatchMidiPttHeld, 0)
        return
    }
    expired := []
    for k, lastTick in midiHeldPads {
        if ((A_TickCount - lastTick) >= 350)
            expired.Push(k)
    }
    for k in expired {
        midiHeldPads.Delete(k)
        OnPttKeyUp()
    }
    if (midiHeldPads.Count = 0)
        SetTimer(WatchMidiPttHeld, 0)
}

OnMidiData(wParam, lParam, msg, hwnd) {
    global midiLearnArmed, midiHeldPads
    status := lParam & 0xFF
    cmd := status & 0xF0
    if (cmd != 0x80 && cmd != 0x90 && cmd != 0xB0 && cmd != 0xE0)
        return

    ch := (status & 0x0F) + 1
    data1 := (lParam >> 8) & 0xFF
    val := (lParam >> 16) & 0xFF
    mapKey := (cmd = 0x90 || cmd = 0x80) ? ("Ch" ch " Note" data1) : ((cmd = 0xE0) ? ("Ch" ch " Pitch") : ("Ch" ch " CC" data1))

    if midiLearnArmed {
        if (cmd = 0x80 || (cmd = 0x90 && val = 0))
            return

        midiLearnArmed := false
        chIdx := IsGuiAlive(midiTargetDDL) ? midiTargetDDL.Value : 1
        tgtParam := (chIdx >= 1 && chIdx <= allChannels.Length) ? allChannels[chIdx].param : activeTargets[1]
        pIdx := IsGuiAlive(midiParamDDL) ? midiParamDDL.Value : 1
        choice := (pIdx >= 1 && pIdx <= midiParamItems.Length) ? midiParamItems[pIdx] : { type: "gain", val: "0", desc: "Main Fader", min: -60.0, max: 0.0 }

        rawMin := IsGuiAlive(midiMinEdit) ? ParseFloatOrDefault(midiMinEdit.Value, choice.min) : choice.min
        rawMax := IsGuiAlive(midiMaxEdit) ? ParseFloatOrDefault(midiMaxEdit.Value, choice.max) : choice.max

        if (choice.type = "fx") {
            fxObj := ""
            for fx in GetChannelEffects(tgtParam) {
                if (fx.key = choice.val) {
                    fxObj := fx
                    break
                }
            }
            lo := IsObject(fxObj) ? fxObj.min : -12.0
            hi := IsObject(fxObj) ? fxObj.max : 12.0
            minBound := Round(Max(lo, Min(hi, Min(rawMin, rawMax))), 2)
            maxBound := Round(Max(lo, Min(hi, Max(rawMin, rawMax))), 2)
        } else {
            minBound := Round(Max(-60.0, Min(12.0, Min(rawMin, rawMax))), 2)
            maxBound := Round(Max(-60.0, Min(12.0, Max(rawMin, rawMax))), 2)
        }

        selMode := (IsGuiAlive(midiModeDDL) && midiModeDDL.Value = 2) ? "rel" : "abs"
        selCurve := (IsGuiAlive(midiCurveDDL) && midiCurveDDL.Value = 2) ? "log" : "lin"

        midiMappings[mapKey] := {
            target: tgtParam,
            type: choice.type,
            val: choice.val,
            minDb: minBound,
            maxDb: maxBound,
            mode: selMode,
            curve: selCurve
        }
        SaveMidiMappings()
        if IsGuiAlive(midiGui) {
            midiLearnPill.SetFont("s9 Bold c38BDF8")
            midiLearnPill.Opt("Background152433")
            midiLearnPill.Value := "Learn Next Input  (Click, then twist a knob/slider or hit a drum pad)"
            RefreshMidiMappingsLV()
        }
        ShowQuickTip("Mapped " mapKey " → " nameMap[tgtParam] " (" choice.desc ")", 1600)
        return
    }

    if (midiMappings.Has(mapKey) && vm.connected) {
        m := midiMappings[mapKey]
        isPress := (cmd = 0x90 && val > 0) || (cmd = 0xB0 && val >= 64)
        isRelease := (cmd = 0x80) || (cmd = 0x90 && val = 0) || (cmd = 0xB0 && val < 64)

        if (m.type = "pad_mute") {
            if isPress {
                curM := 0.0
                DllCall(pGetFloat, "AStr", m.target ".Mute", "Float*", &curM)
                nxtM := (curM >= 0.5) ? 0.0 : 1.0
                DllCall(pSetFloat, "AStr", m.target ".Mute", "Float", nxtM)
                vm.mutes[m.target] := (nxtM >= 0.5)
                vm.lastWriteTick := A_TickCount
                SetTimer(FlushOwnDirtyFlag, -350)
                UpdateTrayIcon(IsAnyActiveTargetMuted())
                if DllCall("IsWindowVisible", "Ptr", settingsGui.Hwnd) {
                    UpdateStatusBanner()
                    RefreshAllChannelReadouts(true)
                }
                ShowHeadUnitOsd("volume", { target: m.target, type: "pad_mute", mapKey: mapKey })
            }
            return
        }

        if (m.type = "pad_snap") {
            if isPress {
                LoadMixerSnapshot(Integer(m.val))
                ShowHeadUnitOsd("volume", { target: m.target, type: "pad_snap", val: Integer(m.val), mapKey: mapKey })
            }
            return
        }

        if (m.type = "pad_ptt") {
            if isPress {
                midiHeldPads[mapKey] := A_TickCount
                OnPttKeyDown()
                SetTimer(WatchMidiPttHeld, 80)
                ShowHeadUnitOsd("volume", { target: pttMicStrip, type: "pad_ptt", held: true, mapKey: mapKey })
            } else if isRelease {
                midiHeldPads.Delete(mapKey)
                OnPttKeyUp()
                ShowHeadUnitOsd("volume", { target: pttMicStrip, type: "pad_ptt", held: false, mapKey: mapKey })
            }
            return
        }

        minB := Float(m.minDb)
        maxB := Float(m.maxDb)

        if (m.type = "fx") {
            fxObj := ""
            for fx in GetChannelEffects(m.target) {
                if (fx.key = m.val) {
                    fxObj := fx
                    break
                }
            }
            if IsObject(fxObj) {
                fullFxParam := m.target "." fxObj.key
                if (m.mode = "rel") {
                    delta := GetRelativeEncoderDelta(val, fxObj.step)
                    if (delta = 0.0)
                        return
                    curFx := vm.fxValues.Has(fullFxParam) ? vm.fxValues[fullFxParam].val : 0.0
                    newFx := Round(Max(minB, Min(maxB, curFx + delta)), 1)
                } else {
                    norm := MapMidiRawToNorm(val, m.curve)
                    if (val <= 0)
                        newFx := minB
                    else if (val >= 127)
                        newFx := maxB
                    else if (minB < 0 && maxB > 0 && Abs(minB) = Abs(maxB) && (val = 63 || val = 64))
                        newFx := 0.0
                    else
                        newFx := Round(minB + norm * (maxB - minB), 1)
                }
                if (Abs(newFx) < 0.05)
                    newFx := 0.0

                vm.fxValues[fullFxParam] := { val: newFx, tick: A_TickCount }
                DllCall(pSetFloat, "AStr", fullFxParam, "Float", newFx)
                vm.lastWriteTick := A_TickCount
                SetTimer(FlushOwnDirtyFlag, -350)

                if DllCall("IsWindowVisible", "Ptr", settingsGui.Hwnd) {
                    if IsTargetActive(m.target)
                        UpdateStatusBanner()
                }
                ShowHeadUnitOsd("fx", { target: m.target, type: "fx", fxObj: fxObj, curVal: newFx, minVal: minB, maxVal: maxB, mode: m.mode, curve: m.curve, mapKey: mapKey })
            }
            return
        }

        lIdx := (m.type = "layer") ? Integer(m.val) : 0
        fullParam := (IsInputStrip(m.target) && lIdx > 0)
            ? m.target ".GainLayer[" (lIdx - 1) "]"
            : m.target ".Gain"

        if (m.mode = "rel") {
            deltaDb := GetRelativeEncoderDelta(val, midiRelStepDb)
            if (deltaDb = 0.0)
                return
            if (IsTargetActive(m.target) && vm.gains.Has(m.target) && GetGainParamForChannel(m.target) = fullParam) {
                curBase := vm.gains[m.target].current
            } else {
                curLive := 0.0
                DllCall(pGetFloat, "AStr", fullParam, "Float*", &curLive)
                curBase := Round(curLive - GetDuckOffsetForParam(fullParam), 2)
            }
            newBase := Round(Max(minB, Min(maxB, curBase + deltaDb)), 2)
        } else {
            norm := MapMidiRawToNorm(val, m.curve)
            if (val <= 0)
                newBase := minB
            else if (val >= 127)
                newBase := maxB
            else
                newBase := Round(minB + norm * (maxB - minB), 2)
        }

        if (IsTargetActive(m.target) && vm.gains.Has(m.target) && GetGainParamForChannel(m.target) = fullParam) {
            vm.gains[m.target].current := newBase
            vm.gains[m.target].target  := newBase
        }
        ApplyChannelGainWithDuck(fullParam, newBase)
        SetTimer(FlushOwnDirtyFlag, -350)

        if DllCall("IsWindowVisible", "Ptr", settingsGui.Hwnd) {
            if IsTargetActive(m.target)
                UpdateStatusBanner()
            RefreshAllChannelReadouts(true)
        }
        ShowHeadUnitOsd("volume", { target: m.target, type: m.type, val: val, curVal: newBase, minVal: minB, maxVal: maxB, mode: m.mode, curve: m.curve, mapKey: mapKey })
    }
}

IsActiveHardwareBus() {
    soloParam := GetSoloTarget()
    if (soloParam = "" || SubStr(soloParam, 1, 4) != "Bus[")
        return false
    idx := Integer(RegExReplace(soloParam, "\D"))
    return (idx >= 0 && idx <= 4)
}

GetActiveBusSyncDelay() {
    if (!vm.connected || !IsActiveHardwareBus())
        return 0
    idx := Integer(RegExReplace(GetSoloTarget(), "\D"))
    dVal := 0.0
    DllCall(pGetFloat, "AStr", "Option.delay[" idx "]", "Float*", &dVal)
    return Round(Max(0, Min(500, dVal)))
}

IsLayerPillHighlighted() {
    if (GetActiveGainLayerIndex() > 0)
        return true
    return (IsActiveHardwareBus() && GetActiveBusSyncDelay() > 0)
}

GetLayerPillHoverHint() {
    if IsActiveHardwareBus()
        return "Safety Lock: Hold Shift + Scroll (±1 ms)  •  Ctrl+Shift (±10 ms)  •  Shift+R-Click: 0 ms"
    soloParam := GetSoloTarget()
    if (soloParam != "" && IsInputStrip(soloParam))
        return "Cycle bus submix layer (L-Click: Next, R-Click: Prev)"
    return "Select an Input Strip for submix layers or A1–A5 for Sync Delay"
}

IsHoveringSyncDelayPill() {
    if (!DllCall("IsWindowVisible", "Ptr", settingsGui.Hwnd) || showAdvancedPanel != 1 || !IsActiveHardwareBus())
        return false
    MouseGetPos(, , &hoverWin, &hoverCtrl, 2)
    return (hoverWin = settingsGui.Hwnd && hoverCtrl = layerPill.Hwnd)
}

OnLayerPillClick(*) {
    if IsActiveHardwareBus() {
        ShowQuickTip("Safety Lock: Hold Shift + Scroll over this bar to adjust Sync Delay", 1200)
        return
    }
    CycleGainLayer(1)
}

OnLayerPillContextMenu(*) {
    if IsActiveHardwareBus() {
        if GetKeyState("Shift", "P") {
            soloParam := GetSoloTarget()
            idx := Integer(RegExReplace(soloParam, "\D"))
            DllCall(pSetFloat, "AStr", "Option.delay[" idx "]", "Float", 0.0)
            vm.lastWriteTick := A_TickCount
            SetTimer(FlushOwnDirtyFlag, -350)
            UpdateStatusBanner()
            if (lastHoverKey = "layerPill")
                layerPill.Opt("Background2E2416")
            busLabel := outputBuses[idx + 1].name
            ShowQuickTip("Reset " busLabel " Sync Delay to 0 ms", 1100)
        } else {
            ShowQuickTip("Safety Lock: Hold Shift + Right-Click to reset Sync Delay to 0 ms", 1300)
        }
        return
    }
    CycleGainLayer(-1)
}

AdjustHoveredBusSyncDelay(deltaMs) {
    Critical
    if (!vm.connected || !IsActiveHardwareBus())
        return
    soloParam := GetSoloTarget()
    idx := Integer(RegExReplace(soloParam, "\D"))
    paramStr := "Option.delay[" idx "]"

    cur := 0.0
    DllCall(pGetFloat, "AStr", paramStr, "Float*", &cur)
    nextMs := Round(Max(0, Min(500, Round(cur) + deltaMs)))

    DllCall(pSetFloat, "AStr", paramStr, "Float", Float(nextMs))
    vm.lastWriteTick := A_TickCount
    SetTimer(FlushOwnDirtyFlag, -350)

    UpdateStatusBanner()
    if (lastHoverKey = "layerPill")
        layerPill.Opt("Background" (nextMs > 0 ? "42311A" : "2E2416"))
}

GetActiveGainLayerIndex() {
    soloParam := GetSoloTarget()
    if (soloParam = "" || !IsInputStrip(soloParam))
        return 0
    return vm.layerIndex.Has(soloParam) ? vm.layerIndex[soloParam] : 0
}

GetGainParamForChannel(param) {
    if (exclusiveMode = 1 && activeTargets.Length = 1 && activeTargets[1] = param && IsInputStrip(param)) {
        lIdx := vm.layerIndex.Has(param) ? vm.layerIndex[param] : 0
        if (lIdx >= 1 && lIdx <= 8)
            return param ".GainLayer[" (lIdx - 1) "]"
    }
    return param ".Gain"
}

IsDuckTargetParam(fullParam) {
    if ((!duckEnabled && A_TickCount > duckTestUntilTick) || duckTargets.Length = 0)
        return false
    for tParam in duckTargets {
        if (tParam = duckTriggerStrip)
            continue
        targetFull := (IsInputStrip(tParam) && duckBusLayer > 0)
            ? tParam ".GainLayer[" (duckBusLayer - 1) "]"
            : tParam ".Gain"
        if (targetFull = fullParam)
            return true
    }
    return false
}

GetDuckOffsetForParam(fullParam) {
    if ((!duckEnabled && A_TickCount > duckTestUntilTick) || Abs(duckCurrentOffset) < 0.01)
        return 0.0
    return IsDuckTargetParam(fullParam) ? duckCurrentOffset : 0.0
}

ApplyChannelGainWithDuck(fullParam, baseVal) {
    cleanBase := Round(Max(-60.0, Min(12.0, baseVal)), 2)
    if (duckBaseGains.Has(fullParam))
        duckBaseGains[fullParam] := cleanBase
    applied := Round(Max(-60.0, Min(12.0, cleanBase + GetDuckOffsetForParam(fullParam))), 2)
    DllCall(pSetFloat, "AStr", fullParam, "Float", applied)
    vm.lastWriteTick := A_TickCount
}

CycleGainLayer(dir) {
    Critical
    soloParam := GetSoloTarget()
    if (soloParam = "") {
        ShowQuickTip("Enable Single-Target Mode to select Bus Gain Layers", 1200)
        return
    }
    if !IsInputStrip(soloParam) {
        ShowQuickTip("Gain Layers apply to Input Strips (Virtual & Hardware)", 1200)
        return
    }

    SetTimer(GlideStep, 0)
    vm.gliding := false

    cur := vm.layerIndex.Has(soloParam) ? vm.layerIndex[soloParam] : 0
    nxt := cur + dir
    if (nxt < 0)
        nxt := outputBuses.Length
    else if (nxt > outputBuses.Length)
        nxt := 0

    vm.layerIndex[soloParam] := nxt
    vm.gains.Clear()
    SyncAllActiveTargets(true)

    if (showAdvancedPanel = 0 && DllCall("IsWindowVisible", "Ptr", settingsGui.Hwnd)) {
        global showAdvancedPanel := 1
        IniWrite(1, iniPath, "Settings", "ShowAdvanced")
        RecalculateMainLayout()
    }

    if DllCall("IsWindowVisible", "Ptr", settingsGui.Hwnd) {
        UpdateStatusBanner()
        RefreshAllChannelReadouts(true)
    }
    ShowHeadUnitOsd("layer")
}

CycleSoloChannel(dir) {
    Critical
    if (allChannels.Length = 0)
        return

    curParam := (activeTargets.Length > 0) ? activeTargets[1] : ""
    curIdx := 0
    for idx, ch in allChannels {
        if (ch.param = curParam) {
            curIdx := idx
            break
        }
    }

    if (curIdx = 0) {
        newIdx := (dir >= 0) ? 1 : allChannels.Length
    } else {
        newIdx := curIdx + dir
        if (newIdx < 1)
            newIdx := allChannels.Length
        else if (newIdx > allChannels.Length)
            newIdx := 1
    }

    ApplyQuickPreset(allChannels[newIdx].param)
}

GetSoloTarget() {
    if (!vm.connected || exclusiveMode != 1 || activeTargets.Length != 1)
        return ""
    return activeTargets[1]
}

GetSelectedEffectObj(param) {
    fxList := GetChannelEffects(param)
    idx := vm.fxIndex.Has(param) ? vm.fxIndex[param] : 1
    if (idx < 1 || idx > fxList.Length)
        idx := 1
    vm.fxIndex[param] := idx
    return fxList[idx]
}

FormatEffectValue(fxObj, val) {
    clean := Round(val, 1)
    if (Abs(clean) < 0.05)
        clean := 0.0
    if (fxObj.unit = " dB")
        return (clean > 0 ? "+" : "") Format("{:.1f} dB", clean)
    return Format("{:.1f}", clean)
}

SyncSelectedSoloEffect(forceRead := false) {
    param := GetSoloTarget()
    if (param = "")
        return

    fxObj := GetSelectedEffectObj(param)
    fullParam := param "." fxObj.key

    if (!forceRead && vm.fxValues.Has(fullParam) && (A_TickCount - vm.fxValues[fullParam].tick <= 350))
        return

    DllCall(pIsDirty)
    liveVal := 0.0
    if (DllCall(pGetFloat, "AStr", fullParam, "Float*", &liveVal, "Int") = 0)
        vm.fxValues[fullParam] := { val: liveVal, tick: A_TickCount }
    else if !vm.fxValues.Has(fullParam)
        vm.fxValues[fullParam] := { val: 0.0, tick: A_TickCount }
}

CycleSoloEffect(dir) {
    Critical
    param := GetSoloTarget()
    if (param = "") {
        ShowQuickTip("Enable Single-Target Mode to navigate channel FX", 1100)
        return
    }

    fxList := GetChannelEffects(param)
    curIdx := vm.fxIndex.Has(param) ? vm.fxIndex[param] : 1
    newIdx := curIdx + dir
    if (newIdx < 1)
        newIdx := fxList.Length
    else if (newIdx > fxList.Length)
        newIdx := 1

    vm.fxIndex[param] := newIdx
    SyncSelectedSoloEffect(true)

    if DllCall("IsWindowVisible", "Ptr", settingsGui.Hwnd)
        UpdateStatusBanner()
    ShowHeadUnitOsd("fx")
}

AdjustSoloEffect(dir, fineMode := false) {
    Critical
    param := GetSoloTarget()
    if (param = "") {
        ShowQuickTip("Enable Single-Target Mode to adjust channel FX", 1100)
        return
    }

    fxObj := GetSelectedEffectObj(param)
    fullParam := param "." fxObj.key

    if (!vm.fxValues.Has(fullParam) || (A_TickCount - vm.fxValues[fullParam].tick > 350)) {
        DllCall(pIsDirty)
        liveVal := 0.0
        DllCall(pGetFloat, "AStr", fullParam, "Float*", &liveVal, "Int")
        curVal := liveVal
    } else {
        curVal := vm.fxValues[fullParam].val
    }

    step := fineMode ? 0.1 : fxObj.step
    newVal := Round(Max(fxObj.min, Min(fxObj.max, curVal + (dir * step))), 1)
    if (Abs(newVal) < 0.05)
        newVal := 0.0

    vm.fxValues[fullParam] := { val: newVal, tick: A_TickCount }
    DllCall(pSetFloat, "AStr", fullParam, "Float", newVal)
    vm.lastWriteTick := A_TickCount
    SetTimer(FlushOwnDirtyFlag, -350)

    if DllCall("IsWindowVisible", "Ptr", settingsGui.Hwnd)
        UpdateStatusBanner()
    ShowHeadUnitOsd("fx")
}

ResetSoloEffect() {
    Critical
    param := GetSoloTarget()
    if (param = "")
        return

    fxObj := GetSelectedEffectObj(param)
    fullParam := param "." fxObj.key

    vm.fxValues[fullParam] := { val: 0.0, tick: A_TickCount }
    DllCall(pSetFloat, "AStr", fullParam, "Float", 0.0)
    vm.lastWriteTick := A_TickCount
    SetTimer(FlushOwnDirtyFlag, -350)

    if DllCall("IsWindowVisible", "Ptr", settingsGui.Hwnd)
        UpdateStatusBanner()
    ShowHeadUnitOsd("fx")
}

GetHoveredChannel() {
    if !DllCall("IsWindowVisible", "Ptr", settingsGui.Hwnd)
        return ""

    MouseGetPos(, , &hoverWin, &hoverCtrl, 2)
    if (hoverWin != settingsGui.Hwnd)
        return ""

    if (hoverCtrl && ctrlHwndToParam.Has(hoverCtrl))
        return ctrlHwndToParam[hoverCtrl]

    pt := Buffer(8, 0)
    DllCall("GetCursorPos", "Ptr", pt)
    DllCall("ScreenToClient", "Ptr", settingsGui.Hwnd, "Ptr", pt)
    cx := NumGet(pt, 0, "Int")
    cy := NumGet(pt, 4, "Int")

    for zone in hoverZones {
        if (cx >= zone.x1 && cx <= zone.x2 && cy >= (zone.relY1 + currentBodyStartY) && cy <= (zone.relY2 + currentBodyStartY))
            return zone.param
    }
    return ""
}

HoverWheelStep(dir, stepSize) {
    Critical
    param := GetHoveredChannel()
    if (param = "" || !vm.connected)
        return

    gainParam := GetGainParamForChannel(param)

    if (IsTargetActive(param) && vm.gains.Has(param)) {
        cur := vm.gains[param].target
        newGain := Round(Max(-60.0, Min(12.0, cur + (dir * stepSize))), 1)
        vm.gains[param].current := newGain
        vm.gains[param].target  := newGain
        ApplyChannelGainWithDuck(gainParam, newGain)
        UpdateStatusBanner()
    } else {
        if (!hoverCache.Has(gainParam) || (A_TickCount - hoverCache[gainParam].tick > 300)) {
            DllCall(pIsDirty)
            liveGain := 0.0
            DllCall(pGetFloat, "AStr", gainParam, "Float*", &liveGain, "Int")
            cur := Round(Max(-60.0, Min(12.0, liveGain - GetDuckOffsetForParam(gainParam))), 2)
        } else {
            cur := hoverCache[gainParam].gain
        }

        newGain := Round(Max(-60.0, Min(12.0, cur + (dir * stepSize))), 1)
        hoverCache[gainParam] := { gain: newGain, tick: A_TickCount }
        ApplyChannelGainWithDuck(gainParam, newGain)
        SetTimer(FlushOwnDirtyFlag, -350)
    }

    RefreshAllChannelReadouts(true)
    disp := (Abs(newGain) < 0.05) ? 0.0 : newGain
    ShowQuickTip(nameMap[param] ":  " (disp > 0 ? "+" : "") Format("{:.1f} dB", disp), 900)
}

; ==============================================================================
; 8. AUTOMATION SUITE: DEVICE LOCK, AUTO-DUCKING, STARTUP & GITHUB UPDATES
; ==============================================================================
EnumWindowsAudioDevices(dataFlow) {
    list := []
    try {
        enumerator := ComObject("{BCDE0395-E52F-467C-8E3D-C4579291692E}", "{A95664D2-9614-4F35-A746-DE8DB63617E6}")
        ComCall(3, enumerator, "Int", dataFlow, "UInt", 1, "Ptr*", &pCol := 0)
        if !pCol
            return list
        colObj := ComValue(13, pCol)
        ComCall(3, colObj, "UInt*", &count := 0)

        pkey := Buffer(20, 0)
        DllCall("ole32\CLSIDFromString", "WStr", "{A45C254E-DF1C-4EFD-8020-67D146A850E0}", "Ptr", pkey)
        NumPut("UInt", 14, pkey, 16)

        Loop count {
            ComCall(4, colObj, "UInt", A_Index - 1, "Ptr*", &pDev := 0)
            if !pDev
                continue
            devObj := ComValue(13, pDev)

            ComCall(5, devObj, "Ptr*", &pId := 0)
            devId := ""
            if pId {
                devId := StrGet(pId, "UTF-16")
                DllCall("ole32\CoTaskMemFree", "Ptr", pId)
            }

            friendly := devId
            ComCall(4, devObj, "UInt", 0, "Ptr*", &pStore := 0)
            if pStore {
                storeObj := ComValue(13, pStore)
                pv := Buffer(24, 0)
                if (ComCall(5, storeObj, "Ptr", pkey, "Ptr", pv) = 0) {
                    vt := NumGet(pv, 0, "UShort")
                    if (vt = 31) {
                        pStr := NumGet(pv, 8, "Ptr")
                        if pStr
                            friendly := StrGet(pStr, "UTF-16")
                    }
                    DllCall("ole32\PropVariantClear", "Ptr", pv)
                }
            }

            if (devId != "")
                list.Push({ id: devId, name: friendly })
        }
    }
    return list
}

GetDefaultWindowsEndpoint(dataFlow) {
    res := { id: "", name: "" }
    try {
        enumerator := ComObject("{BCDE0395-E52F-467C-8E3D-C4579291692E}", "{A95664D2-9614-4F35-A746-DE8DB63617E6}")
        ComCall(4, enumerator, "Int", dataFlow, "Int", 0, "Ptr*", &pDev := 0)
        if !pDev
            return res
        devObj := ComValue(13, pDev)
        ComCall(5, devObj, "Ptr*", &pId := 0)
        if pId {
            res.id := StrGet(pId, "UTF-16")
            DllCall("ole32\CoTaskMemFree", "Ptr", pId)
        }
    }
    return res
}

SetDefaultWindowsEndpoint(devId) {
    if (devId = "")
        return false
    try {
        policy := ComObject("{870AF99C-171D-4F9E-AF0D-E63DF40C2BC9}", "{F8679F50-850A-41CF-9C72-430F290290C8}")
        ComCall(13, policy, "WStr", devId, "Int", 0)
        ComCall(13, policy, "WStr", devId, "Int", 1)
        ComCall(13, policy, "WStr", devId, "Int", 2)
        return true
    } catch {
        return false
    }
}

EnforceDefaultDevices(silent := true) {
    if !deviceLockEnabled
        return

    restored := false
    if (lockedPlaybackId != "") {
        curP := GetDefaultWindowsEndpoint(0)
        if (curP.id != "" && curP.id != lockedPlaybackId) {
            if SetDefaultWindowsEndpoint(lockedPlaybackId)
                restored := true
        }
    }
    if (lockedRecordId != "") {
        curR := GetDefaultWindowsEndpoint(1)
        if (curR.id != "" && curR.id != lockedRecordId) {
            if SetDefaultWindowsEndpoint(lockedRecordId)
                restored := true
        }
    }

    if (restored && !silent)
        ShowQuickTip("Anti-Hijack: Restored locked Windows default audio devices.", 1500)
}

EnforceDefaultDevicesLoud() {
    EnforceDefaultDevices(false)
}

EnforceDefaultDevicesSilent() {
    EnforceDefaultDevices(true)
}

ToggleDeviceLock(*) {
    global deviceLockEnabled, lockedPlaybackId, lockedPlaybackName, lockedRecordId, lockedRecordName

    if (deviceLockEnabled = 0) {
        if (lockedPlaybackId = "" && lockedRecordId = "") {
            pList := EnumWindowsAudioDevices(0)
            rList := EnumWindowsAudioDevices(1)
            curP  := GetDefaultWindowsEndpoint(0)
            curR  := GetDefaultWindowsEndpoint(1)
            for d in pList {
                if (d.id = curP.id) {
                    lockedPlaybackId   := d.id
                    lockedPlaybackName := d.name
                }
            }
            for d in rList {
                if (d.id = curR.id) {
                    lockedRecordId   := d.id
                    lockedRecordName := d.name
                }
            }
            IniWrite(lockedPlaybackId, iniPath, "DeviceLock", "PlaybackId")
            IniWrite(lockedPlaybackName, iniPath, "DeviceLock", "PlaybackName")
            IniWrite(lockedRecordId, iniPath, "DeviceLock", "RecordId")
            IniWrite(lockedRecordName, iniPath, "DeviceLock", "RecordName")
        }
        deviceLockEnabled := 1
        EnforceDefaultDevices(true)
    } else {
        deviceLockEnabled := 0
    }

    IniWrite(deviceLockEnabled, iniPath, "DeviceLock", "Enabled")
    RefreshAutomationPills()
    RefreshShortcutLabels()
    ShowQuickTip("Windows Device Anti-Hijack: " (deviceLockEnabled ? "ON (" lockedPlaybackName ")" : "OFF"), 1400)
}

ToggleAutoDuck(*) {
    global duckEnabled := (duckEnabled = 1) ? 0 : 1
    IniWrite(duckEnabled, iniPath, "AutoDuck", "Enabled")

    if (duckEnabled = 1) {
        SetTimer(AutoDuckTick, 25)
    } else {
        SetTimer(AutoDuckTick, 0)
        RestoreAllDuckedChannels()
    }

    RefreshAutomationPills()
    RefreshShortcutLabels()
    ShowQuickTip("Auto-Ducking: " (duckEnabled ? "ON" : "OFF"), 1200)
}

RestoreAllDuckedChannels() {
    global duckCurrentOffset, duckTargetOffset, duckBaseGains, duckStageLabel
    duckCurrentOffset := 0.0
    duckTargetOffset  := 0.0
    duckStageLabel    := "IDLE"
    for fullParam, baseVal in duckBaseGains {
        try DllCall(pSetFloat, "AStr", fullParam, "Float", baseVal)
    }
    duckBaseGains.Clear()
    if DllCall("IsWindowVisible", "Ptr", settingsGui.Hwnd) {
        UpdateStatusBanner()
        RefreshAllChannelReadouts(true)
    }
}

AutoDuckTick() {
    Critical
    global duckCurrentOffset, duckTargetOffset, duckLastLoudTick, duckBaseGains, duckStageLabel, duckTestUntilTick

    now := A_TickCount
    isTesting := (now <= duckTestUntilTick)

    if ((!duckEnabled && !isTesting) || !vm.connected || !pGetLevel || duckTargets.Length = 0) {
        if (duckBaseGains.Count > 0)
            RestoreAllDuckedChannels()
        if !duckEnabled
            SetTimer(AutoDuckTick, 0)
        return
    }

    stripIdx := Integer(RegExReplace(duckTriggerStrip, "\D"))

    isMuted := false
    if (!isTesting && duckIgnoreMuted = 1) {
        mVal := 0.0
        DllCall(pGetFloat, "AStr", duckTriggerStrip ".Mute", "Float*", &mVal)
        isMuted := (mVal >= 0.5)
    }

    if isTesting {
        db := 0.0
    } else if isMuted {
        db := -120.0
    } else {
        lvlL := 0.0
        lvlR := 0.0
        DllCall(pGetLevel, "Int", 0, "Int", stripIdx * 8, "Float*", &lvlL)
        DllCall(pGetLevel, "Int", 0, "Int", (stripIdx * 8) + 1, "Float*", &lvlR)
        peak := Max(lvlL, lvlR)
        db := (peak > 0.000001) ? (20.0 * Log(peak)) : -120.0
    }

    if (db >= duckThresholdDb) {
        duckLastLoudTick := now
        duckTargetOffset := -Abs(duckAmountDb)
    } else if ((now - duckLastLoudTick) >= duckHoldMs) {
        duckTargetOffset := 0.0
    }

    diff := duckTargetOffset - duckCurrentOffset
    if (Abs(diff) < 0.05 && duckTargetOffset = 0.0) {
        if (duckBaseGains.Count > 0) {
            RestoreAllDuckedChannels()
            vm.lastWriteTick := now
            SetTimer(FlushOwnDirtyFlag, -350)
        }
        duckStageLabel := "IDLE"
        return
    }

    if (duckTargetOffset < duckCurrentOffset) {
        rate := Min(1.0, 1.0 - (0.05 ** (25.0 / Max(10, duckAttackMs))))
        duckStageLabel := (Abs(diff) > 0.25) ? "ATTACK" : "DUCKED"
    } else if (duckTargetOffset < 0.0) {
        rate := 1.0
        duckStageLabel := "HOLD"
    } else {
        rate := Min(1.0, 1.0 - (0.05 ** (25.0 / Max(40, duckReleaseMs))))
        duckStageLabel := "RELEASING"
    }

    prevOffset := duckCurrentOffset
    if (Abs(diff) <= 0.05)
        duckCurrentOffset := Round(duckTargetOffset, 2)
    else
        duckCurrentOffset := Round(duckCurrentOffset + (diff * rate), 2)

    for tParam in duckTargets {
        if (tParam = duckTriggerStrip)
            continue

        fullParam := (IsInputStrip(tParam) && duckBusLayer > 0)
            ? tParam ".GainLayer[" (duckBusLayer - 1) "]"
            : tParam ".Gain"

        isControlledActive := (IsTargetActive(tParam) && vm.gains.Has(tParam) && GetGainParamForChannel(tParam) = fullParam)

        if isControlledActive {
            baseVal := vm.gains[tParam].current
            duckBaseGains[fullParam] := baseVal
        } else if !duckBaseGains.Has(fullParam) {
            liveVal := 0.0
            DllCall(pGetFloat, "AStr", fullParam, "Float*", &liveVal)
            duckBaseGains[fullParam] := Round(Max(-60.0, Min(12.0, liveVal - prevOffset)), 2)
        } else if (!vm.gliding && (now - vm.lastWriteTick > 300)) {
            liveVal := 0.0
            DllCall(pGetFloat, "AStr", fullParam, "Float*", &liveVal)
            expected := Max(-60.0, Min(12.0, duckBaseGains[fullParam] + prevOffset))
            if (Abs(liveVal - expected) > 0.35) {
                duckBaseGains[fullParam] := Round(Max(-60.0, Min(12.0, liveVal - prevOffset)), 2)
                if hoverCache.Has(fullParam)
                    hoverCache.Delete(fullParam)
            }
        }

        ApplyChannelGainWithDuck(fullParam, duckBaseGains[fullParam])
    }

    if DllCall("IsWindowVisible", "Ptr", settingsGui.Hwnd) {
        UpdateStatusBanner()
        RefreshAllChannelReadouts(true)
    }
}

EnsureVoicemeeterRunning() {
    if !autoLaunchVM
        return

    vmType := 0
    if (DllCall(pGetType, "Int*", &vmType, "Int") = 0 && vmType > 0)
        return

    vmExe := "C:\Program Files (x86)\VB\Voicemeeter\voicemeeter8x64.exe"
    if !FileExist(vmExe)
        vmExe := "C:\Program Files (x86)\VB\Voicemeeter\voicemeeter8.exe"

    if FileExist(vmExe) {
        try {
            Run(vmExe)
            if hideVMOnLaunch
                SetTimer(HideVoicemeeterAfterBoot, -2500)
        }
    }
}

HideVoicemeeterAfterBoot() {
    SetVoicemeeterVisibility(false)
}

SetVoicemeeterVisibility(showWin) {
    DllCall(pSetFloat, "AStr", "Command.Show", "Float", showWin ? 1.0 : 0.0)
}

CompareSemVer(vRemote, vLocal) {
    rClean := RegExReplace(vRemote, "^[vV]")
    lClean := RegExReplace(vLocal, "^[vV]")
    rParts := StrSplit(rClean, ".")
    lParts := StrSplit(lClean, ".")
    Loop Max(rParts.Length, lParts.Length) {
        rNum := (A_Index <= rParts.Length && IsInteger(rParts[A_Index])) ? Integer(rParts[A_Index]) : 0
        lNum := (A_Index <= lParts.Length && IsInteger(lParts[A_Index])) ? Integer(lParts[A_Index]) : 0
        if (rNum > lNum)
            return 1
        if (rNum < lNum)
            return -1
    }
    return 0
}

CheckForGithubUpdates(silent := true) {
    try {
        http := ComObject("WinHttp.WinHttpRequest.5.1")
        http.SetTimeouts(3000, 3000, 4000, 4000)
        http.Open("GET", "https://api.github.com/repos/" GITHUB_REPO "/releases/latest", false)
        http.SetRequestHeader("User-Agent", "Potato-Massah-App")
        http.Send()

        if (http.Status = 200) {
            body := http.ResponseText
            if RegExMatch(body, '"tag_name"\s*:\s*"([^"]+)"', &m) {
                latestTag := m[1]
                if (CompareSemVer(latestTag, APP_VERSION) > 0) {
                    if IsGuiAlive(startupGui)
                        updateStatusTxt.Value := "Update available: " latestTag " (Current: " APP_VERSION ")"
                    ans := MsgBox(
                        "A new version of Potato Massah (" latestTag ") is available on GitHub!`nYou are currently running " APP_VERSION ".`n`nOpen the release download page now?",
                        "Potato Massah Update Available",
                        "YesNo Iconi 262144"
                    )
                    if (ans = "Yes")
                        Run("https://github.com/" GITHUB_REPO "/releases/latest")
                } else {
                    if IsGuiAlive(startupGui)
                        updateStatusTxt.Value := "Up to date (" APP_VERSION " matches latest " latestTag ")"
                    if !silent
                        ShowQuickTip("Potato Massah is up to date (" APP_VERSION ").", 1400)
                }
            }
        } else if !silent {
            if IsGuiAlive(startupGui)
                updateStatusTxt.Value := "Could not check GitHub (HTTP " http.Status ")"
        }
    } catch {
        if !silent && IsGuiAlive(startupGui)
            updateStatusTxt.Value := "Offline or GitHub unreachable."
    }
}

CheckUpdatesOnBoot() {
    CheckForGithubUpdates(true)
}

; ==============================================================================
; 9. PRO DRAWER ACTIONS, SNAPSHOTS, INLINE READOUTS & DYNAMIC LAYOUT ENGINE
; ==============================================================================
DismissWelcomeBanner(*) {
    global showWelcomeBanner := 0
    IniWrite(0, iniPath, "Settings", "ShowWelcome")
    RecalculateMainLayout()
}

ToggleAdvancedPanel(*) {
    global showAdvancedPanel := (showAdvancedPanel = 1) ? 0 : 1
    IniWrite(showAdvancedPanel, iniPath, "Settings", "ShowAdvanced")
    RecalculateMainLayout()
    if (showAdvancedPanel = 1) {
        RefreshStripRoutingPills()
        RefreshSnapshotPills()
    }
}

ToggleStripBusRoute(busName, *) {
    Critical
    soloParam := GetSoloTarget()
    if (soloParam = "" || !IsInputStrip(soloParam)) {
        ShowQuickTip("Select a single Input Strip to toggle its A1–B3 routing.", 1300)
        return
    }

    cur := 0.0
    DllCall(pGetFloat, "AStr", soloParam "." busName, "Float*", &cur)
    nxt := (cur >= 0.5) ? 0.0 : 1.0
    DllCall(pSetFloat, "AStr", soloParam "." busName, "Float", nxt)
    vm.lastWriteTick := A_TickCount
    SetTimer(FlushOwnDirtyFlag, -350)

    overrides := Map(busName, nxt >= 0.5)
    RefreshStripRoutingPills(overrides)
    ShowQuickTip(nameMap[soloParam] "  " Chr(0x2192) "  " busName ": " (nxt >= 0.5 ? "ON" : "OFF"), 1000)
}

RefreshStripRoutingPills(overrides := "") {
    global routeStateCache
    soloParam := GetSoloTarget()
    isStrip := (soloParam != "" && IsInputStrip(soloParam) && vm.connected)

    for idx, b in outputBuses {
        btn := routeBtnMap[b.name]
        if !isStrip {
            routeStateCache[b.name] := false
            btn.SetFont("s8 Bold c52525B")
            btn.Opt("Background16161E")
        } else {
            if (IsObject(overrides) && overrides.Has(b.name)) {
                isOn := overrides[b.name]
            } else {
                val := 0.0
                DllCall(pGetFloat, "AStr", soloParam "." b.name, "Float*", &val)
                isOn := (val >= 0.5)
            }
            routeStateCache[b.name] := isOn
            if isOn {
                btn.SetFont("s8 Bold cF59E0B")
                btn.Opt("Background332614")
            } else {
                btn.SetFont("s8 Bold c71717A")
                btn.Opt("Background1A1A22")
            }
        }
    }
}

ResetActiveStripLayers(*) {
    Critical
    soloParam := GetSoloTarget()
    if (soloParam = "" || !IsInputStrip(soloParam)) {
        ShowQuickTip("Select a single Input Strip to reset its submix layers.", 1300)
        return
    }

    Loop 8
        DllCall(pSetFloat, "AStr", soloParam ".GainLayer[" (A_Index - 1) "]", "Float", 0.0)

    vm.layerIndex[soloParam] := 0
    vm.gains.Clear()
    SyncAllActiveTargets(true)
    vm.lastWriteTick := A_TickCount
    SetTimer(FlushOwnDirtyFlag, -350)

    UpdateStatusBanner()
    RefreshAllChannelReadouts(true)
    ShowQuickTip("Reset all A1–B3 submix layers on " nameMap[soloParam] " to 0.0 dB.", 1400)
}

ResetActiveStripRoutes(*) {
    Critical
    soloParam := GetSoloTarget()
    if (soloParam = "" || !IsInputStrip(soloParam)) {
        ShowQuickTip("Select a single Input Strip to reset its output routes.", 1300)
        return
    }

    overrides := Map()
    for idx, b in outputBuses {
        isDefault := (b.name = "A1")
        DllCall(pSetFloat, "AStr", soloParam "." b.name, "Float", isDefault ? 1.0 : 0.0)
        overrides[b.name] := isDefault
    }

    vm.lastWriteTick := A_TickCount
    SetTimer(FlushOwnDirtyFlag, -350)
    RefreshStripRoutingPills(overrides)
    ShowQuickTip("Reset " nameMap[soloParam] " routing to default (A1 ON).", 1300)
}

ResetEntireMixerDefault(*) {
    settingsGui.Opt("-AlwaysOnTop")
    ans := MsgBox(
        "Reset all 16 channel faders to 0.0 dB, clear all per-bus submix layers, and set input routing back to A1 only?",
        "Reset Mixer to Default State",
        "YesNo Icon? 262144"
    )
    settingsGui.Opt("+AlwaysOnTop")
    if (ans != "Yes")
        return

    Critical
    SetTimer(GlideStep, 0)
    vm.gliding := false
    duckBaseGains.Clear()

    for ch in allChannels
        DllCall(pSetFloat, "AStr", ch.param ".Gain", "Float", 0.0)

    for st in inputStrips {
        Loop 8
            DllCall(pSetFloat, "AStr", st.param ".GainLayer[" (A_Index - 1) "]", "Float", 0.0)
        for b in outputBuses
            DllCall(pSetFloat, "AStr", st.param "." b.name, "Float", (b.name = "A1") ? 1.0 : 0.0)
        vm.layerIndex[st.param] := 0
    }

    vm.gains.Clear()
    SyncAllActiveTargets(true)
    vm.lastWriteTick := A_TickCount
    SetTimer(FlushOwnDirtyFlag, -350)

    overrides := Map()
    for b in outputBuses
        overrides[b.name] := (b.name = "A1")
    RefreshStripRoutingPills(overrides)
    UpdateStatusBanner()
    RefreshAllChannelReadouts(true)
    ShowQuickTip("All faders, submix layers, and A1 routes restored to default!", 1600)
}

SaveMixerSnapshot(idx, *) {
    if !vm.connected {
        ShowQuickTip("VoiceMeeter Potato must be running to save a snapshot.", 1300)
        return
    }

    sec := "Snapshot" idx
    IniWrite(1, iniPath, sec, "Saved")
    for ch in allChannels {
        gVal := 0.0
        DllCall(pGetFloat, "AStr", ch.param ".Gain", "Float*", &gVal)
        IniWrite(Format("{:.2f}", gVal), iniPath, sec, ch.param "_Gain")
    }
    for st in inputStrips {
        for b in outputBuses {
            rVal := 0.0
            DllCall(pGetFloat, "AStr", st.param "." b.name, "Float*", &rVal)
            IniWrite((rVal >= 0.5) ? 1 : 0, iniPath, sec, st.param "_" b.name)
        }
    }
    Loop 5 {
        dIdx := A_Index - 1
        dVal := 0.0
        DllCall(pGetFloat, "AStr", "Option.delay[" dIdx "]", "Float*", &dVal)
        IniWrite(Round(Max(0.0, Min(500.0, dVal))), iniPath, sec, "Delay_A" A_Index)
    }

    RefreshSnapshotPills()
    ShowQuickTip("Saved faders, routes & A1–A5 sync delays to Snapshot P" idx "!", 1400)
}

LoadMixerSnapshot(idx, *) {
    if !vm.connected {
        ShowQuickTip("VoiceMeeter Potato is offline.", 1200)
        return
    }

    sec := "Snapshot" idx
    if (IniRead(iniPath, sec, "Saved", "0") != "1") {
        ShowQuickTip("Snapshot P" idx " is empty — right-click P" idx " to save your current mixer.", 1500)
        return
    }

    Critical
    SetTimer(GlideStep, 0)
    vm.gliding := false
    duckBaseGains.Clear()

    for ch in allChannels {
        gVal := Float(IniRead(iniPath, sec, ch.param "_Gain", "0.0"))
        DllCall(pSetFloat, "AStr", ch.param ".Gain", "Float", gVal)
    }

    soloParam := GetSoloTarget()
    overrides := Map()
    for st in inputStrips {
        for b in outputBuses {
            rVal := Integer(IniRead(iniPath, sec, st.param "_" b.name, (b.name = "A1") ? "1" : "0"))
            DllCall(pSetFloat, "AStr", st.param "." b.name, "Float", rVal ? 1.0 : 0.0)
            if (st.param = soloParam)
                overrides[b.name] := (rVal = 1)
        }
    }

    Loop 5 {
        dIdx := A_Index - 1
        savedDelay := Round(Max(0.0, Min(500.0, ParseFloatOrDefault(IniRead(iniPath, sec, "Delay_A" A_Index, "0"), 0.0))))
        DllCall(pSetFloat, "AStr", "Option.delay[" dIdx "]", "Float", Float(savedDelay))
    }

    vm.gains.Clear()
    SyncAllActiveTargets(true)
    vm.lastWriteTick := A_TickCount
    SetTimer(FlushOwnDirtyFlag, -350)

    if DllCall("IsWindowVisible", "Ptr", settingsGui.Hwnd) {
        RefreshStripRoutingPills(overrides)
        UpdateStatusBanner()
        RefreshAllChannelReadouts(true)
    }
    ShowQuickTip("Loaded Mixer Snapshot P" idx " (faders, routes & sync delay)!", 1400)
}

RefreshSnapshotPills() {
    Loop 4 {
        sIdx := A_Index
        btn := snapBtnMap[sIdx]
        isSaved := (IniRead(iniPath, "Snapshot" sIdx, "Saved", "0") = "1")
        if isSaved {
            btn.SetFont("s8 Bold cF59E0B")
            btn.Opt("Background261E12")
            btn.Value := "● P" sIdx ": Saved"
        } else {
            btn.SetFont("s8 Bold c71717A")
            btn.Opt("Background1E1E28")
            btn.Value := "○ P" sIdx ": Empty"
        }
    }
}

IsAnyActiveTargetMuted() {
    for p in activeTargets {
        if (vm.mutes.Has(p) && vm.mutes[p])
            return true
    }
    return false
}

ToggleSpecificChannelMute(param) {
    Critical
    if !vm.connected
        return

    DllCall(pIsDirty)
    curMute := 0.0
    DllCall(pGetFloat, "AStr", param ".Mute", "Float*", &curMute)
    newMute := (curMute >= 0.5) ? 0.0 : 1.0
    DllCall(pSetFloat, "AStr", param ".Mute", "Float", newMute)
    vm.mutes[param] := (newMute >= 0.5)

    vm.lastWriteTick := A_TickCount
    SetTimer(FlushOwnDirtyFlag, -350)

    UpdateTrayIcon(IsAnyActiveTargetMuted())
    UpdateStatusBanner()
    RefreshAllChannelReadouts(true)
    ShowQuickTip(nameMap[param] ": " (newMute >= 0.5 ? "MUTED" : "UNMUTED"), 1000)
}

RefreshAllChannelReadouts(forceRead := false) {
    if (!vm.connected || !DllCall("IsWindowVisible", "Ptr", settingsGui.Hwnd))
        return

    dirty := DllCall(pIsDirty)
    if (!forceRead && dirty != 1 && !vm.gliding && duckBaseGains.Count = 0)
        return

    for ch in allChannels {
        param := ch.param
        if !rowVisualMap.Has(param)
            continue

        vis := rowVisualMap[param]
        isCompact := (vis.actBtn != "")

        mVal := 0.0
        DllCall(pGetFloat, "AStr", param ".Mute", "Float*", &mVal)
        isMuted := (mVal >= 0.5)
        vm.mutes[param] := isMuted

        if isMuted {
            txt := "MUTED"
            col := "F87171"
        } else {
            gainParam := GetGainParamForChannel(param)
            if (IsTargetActive(param) && vm.gains.Has(param)) {
                gVal := vm.gains[param].current
            } else {
                liveG := 0.0
                DllCall(pGetFloat, "AStr", gainParam, "Float*", &liveG)
                gVal := liveG - GetDuckOffsetForParam(gainParam)
            }
            clean := Round(gVal, 1)
            if (Abs(clean) < 0.05)
                clean := 0.0
            txt := (clean > 0 ? "+" : "") Format(isCompact ? "{:.1f}dB" : "{:.1f} dB", clean)
            col := IsTargetActive(param) ? (GetActiveGainLayerIndex() > 0 && IsInputStrip(param) ? "F59E0B" : "38BDF8") : "A1A1AA"
        }

        cacheKey := txt "|" col
        if (!rowBadgeCache.Has(param) || rowBadgeCache[param] != cacheKey) {
            rowBadgeCache[param] := cacheKey
            vis.db.SetFont("s8 Bold c" col)
            vis.db.Value := txt
        }
    }
}

GuiLiveSyncTick() {
    isVis := DllCall("IsWindowVisible", "Ptr", settingsGui.Hwnd)
    if (isVis || duckEnabled = 1)
        PollPeakClipping()
    if isVis {
        RefreshAllChannelReadouts(false)
        RefreshHeroSoloMonoPills()
        RefreshRowSoloMonoButtons()
        if (showAdvancedPanel = 1 && IsActiveHardwareBus())
            UpdateStatusBanner()
    }
}

RefreshAutomationPills() {
    autoResetPill.SetFont(autoResetDevice ? "s8 Bold c38BDF8" : "s8 Bold c71717A")
    autoResetPill.Opt(autoResetDevice ? "Background152433" : "Background16161E")
    autoResetPill.Value := autoResetDevice ? "● Auto-Reset: ON" : "○ Auto-Reset: OFF"

    devLockPill.SetFont(deviceLockEnabled ? "s8 Bold c38BDF8" : "s8 Bold c71717A")
    devLockPill.Opt(deviceLockEnabled ? "Background152433" : "Background16161E")
    devLockPill.Value := deviceLockEnabled ? "● Anti-Hijack: ON" : "○ Anti-Hijack: OFF"

    duckPill.SetFont(duckEnabled ? "s8 Bold c38BDF8" : "s8 Bold c71717A")
    duckPill.Opt(duckEnabled ? "Background152433" : "Background16161E")
    duckPill.Value := duckEnabled ? "● Auto-Duck: ON" : "○ Auto-Duck: OFF"

    pttPill.SetFont(pttEnabled ? "s8 Bold c38BDF8" : "s8 Bold c71717A")
    pttPill.Opt(pttEnabled ? "Background152433" : "Background16161E")
    pttPill.Value := pttEnabled ? "● PTT: ON" : "○ PTT: OFF"
}

RefreshModePillVisual() {
    if (exclusiveMode = 1) {
        modePill.SetFont("s7 Bold c38BDF8")
        modePill.Opt("Background1B2B3A")
        modePill.Value := "◉ Single"
    } else {
        modePill.SetFont("s7 Bold cA1A1AA")
        modePill.Opt("Background22222E")
        modePill.Value := "◎ Group"
    }
}

RefreshChannelVisuals(forceAll := false) {
    global lastHoverKey
    if (SubStr(lastHoverKey, 1, 5) = "pill_")
        lastHoverKey := ""
    rowBadgeCache.Clear()
    for param, vis in rowVisualMap {
        active   := IsTargetActive(param)
        clipping := (clippingChannels.Has(param) && clippingChannels[param])
        bgHex    := clipping ? "5C1218" : (active ? "152433" : "16161E")
        sig      := bgHex "|" (active ? "1" : "0") "|" (clipping ? "1" : "0") "|" nameMap[param]

        if (!forceAll && rowStyleCache.Has(param) && rowStyleCache[param] = sig)
            continue
        rowStyleCache[param] := sig

        vis.bg.Opt("Background" bgHex)
        vis.dot.Opt("Background" bgHex)
        vis.dot.SetFont("s9 Bold c" (clipping ? "FCA5A5" : (active ? "38BDF8" : "52525B")))
        vis.dot.Value := clipping ? "!" : (active ? "●" : "○")

        vis.lbl.Opt("Background" bgHex)
        vis.lbl.SetFont("s9 " ((clipping || active) ? "Bold cF4F4F5" : "Norm cD4D4D8"))
        vis.lbl.Value := nameMap[param]

        vis.db.Opt("Background" bgHex)

        if (vis.tag != "") {
            vis.tag.Opt("Background" bgHex)
            vis.tag.SetFont("s8 Norm c" (clipping ? "FCA5A5" : (active ? "38BDF8" : "52525B")))
            vis.tag.Value := param
        }

        try vis.bg.Redraw()
        try vis.dot.Redraw()
        try vis.lbl.Redraw()
        try vis.db.Redraw()
        if (vis.tag != "")
            try vis.tag.Redraw()
    }
    RefreshRowSoloMonoButtons()
    RefreshAllChannelReadouts(true)
}

RecalculateMainLayout(resizeWindow := true) {
    global currentBodyStartY
    isVisible := DllCall("IsWindowVisible", "Ptr", settingsGui.Hwnd)

    curY := 12

    if (showWelcomeBanner = 1) {
        welAccent.Move(16, curY, 460, 2)
        welBg.Move(16, curY + 2, 460, 52)
        welTitle.Move(26, curY + 7, 380, 16)
        welClose.Move(414, curY + 6, 54, 18)
        welBody.Move(26, curY + 25, 440, 26)
        for c in welcomeControls
            c.Visible := true
        curY += 62
    } else {
        for c in welcomeControls
            c.Visible := false
    }

    lineCount := Max(1, activeTargets.Length)
    statusH   := lineCount * 20

    heroAccent.Move(16, curY, 460, 2)
    heroTitleLbl.Move(28, curY + 8)
    heroMutePill.Move(166, curY + 6)
    heroSoloPill.Move(228, curY + 6)
    modePill.Move(290, curY + 6)
    proTogglePill.Move(406, curY + 6)
    proTogglePill.Value := (showAdvancedPanel = 1) ? "Pro " Chr(0x25B4) : "Pro " Chr(0x25BE)
    proTogglePill.Opt((showAdvancedPanel = 1) ? "Background332614" : "Background261E12")

    statusText.Move(28, curY + 30, 436, statusH)
    heroSubText.Move(28, curY + 32 + statusH, 436, 18)

    if (showAdvancedPanel = 1) {
        advY := curY + 56 + statusH
        advDivider.Move(28, advY, 436, 1)
        advWarnLbl.Move(28, advY + 6, 204, 20)
        rstLayersBtn.Move(234, advY + 6, 74, 20)
        rstRoutesBtn.Move(311, advY + 6, 74, 20)
        rstMixerBtn.Move(388, advY + 6, 76, 20)
        layerPill.Move(28, advY + 30, 436, 22)

        for idx, b in outputBuses {
            xR := 28 + ((idx - 1) * 55)
            routeBtnMap[b.name].Move(xR, advY + 56, 51, 22)
        }

        snapLbl.Move(28, advY + 80, 82, 44)
        Loop 4 {
            sIdx := A_Index
            col := Mod(sIdx - 1, 2)
            row := (sIdx - 1) // 2
            xS := 114 + (col * 176)
            yS := advY + 80 + (row * 24)
            snapBtnMap[sIdx].Move(xS, yS, 170, 21)
        }

        for c in advControls
            c.Visible := true

        heroBodyH := 188 + statusH
    } else {
        for c in advControls
            c.Visible := false
        heroBodyH := 56 + statusH
    }

    heroBg.Move(16, curY + 2, 460, heroBodyH)
    curY += heroBodyH + 12

    currentBodyStartY := curY
    for item in bodyControls
        item.ctrl.Move(, item.relY + currentBodyStartY)

    if (resizeWindow && isVisible) {
        settingsGui.Show("AutoSize NoActivate")
        DllCall("RedrawWindow", "Ptr", settingsGui.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0585)
    }
}

ToggleGui() {
    if DllCall("IsWindowVisible", "Ptr", settingsGui.Hwnd) {
        settingsGui.Hide()
    } else {
        HideHeadUnitOsd()
        SyncAllActiveTargets(true)
        SyncSelectedSoloEffect(true)
        RefreshModePillVisual()
        RefreshChannelVisuals(true)
        RefreshHeroSoloMonoPills()
        RefreshAutomationPills()
        if (showAdvancedPanel = 1) {
            RefreshStripRoutingPills()
            RefreshSnapshotPills()
        }
        UpdateStatusBanner()
        RecalculateMainLayout(false)
        settingsGui.Show("AutoSize")
    }
}

ApplyQuickPreset(targetParam, *) {
    Critical
    SetTimer(GlideStep, 0)
    vm.gliding := false

    global exclusiveMode := 1
    global activeTargets := [targetParam]

    vm.gains.Clear()
    vm.mutes.Clear()
    SyncAllActiveTargets(true)
    SyncSelectedSoloEffect(true)
    SaveSettings()
    RefreshModePillVisual()
    RefreshChannelVisuals(true)
    RefreshHeroSoloMonoPills()
    if (showAdvancedPanel = 1)
        RefreshStripRoutingPills()
    UpdateStatusBanner()
    ShowHeadUnitOsd("volume")
}

RestartAudioEngine(*) {
    DllCall(pSetFloat, "AStr", "Command.Restart", "Float", 1.0)
    ShowQuickTip("Restarting VoiceMeeter Audio Engine...", 1400)
    SetTimer(ResyncAfterEngineRestart, -650)
}

ResyncAfterEngineRestart() {
    vm.gains.Clear()
    vm.mutes.Clear()
    vm.fxValues.Clear()
    duckBaseGains.Clear()
    SyncAllActiveTargets(true)
    SyncSelectedSoloEffect(true)
    if (pttEnabled = 1)
        ApplyPttMicState()
    if DllCall("IsWindowVisible", "Ptr", settingsGui.Hwnd) {
        if (showAdvancedPanel = 1)
            RefreshStripRoutingPills()
        RefreshHeroSoloMonoPills()
        RefreshRowSoloMonoButtons()
        UpdateStatusBanner()
        RefreshAllChannelReadouts(true)
    }
}

RegisterAudioDeviceWatcher() {
    global hDevNotify
    dbi := Buffer(32, 0)
    NumPut("UInt", 32, dbi, 0)
    NumPut("UInt", 5, dbi, 4)
    hDevNotify := DllCall("RegisterDeviceNotificationW", "Ptr", settingsGui.Hwnd, "Ptr", dbi, "UInt", 0x00000004, "Ptr")
    OnMessage(0x0219, OnDeviceChange)
}

OnDeviceChange(wParam, lParam, msg, hwnd) {
    if (wParam = 0x8000 && lParam) {
        devType := NumGet(lParam, 4, "UInt")
        if (devType = 5) {
            guidBuf := Buffer(80, 0)
            DllCall("ole32\StringFromGUID2", "Ptr", lParam + 12, "Ptr", guidBuf, "Int", 40)
            classGuid := StrGet(guidBuf, "UTF-16")

            if (classGuid = "{6994AD04-93EF-11D0-A3CC-00A0C9223196}") {
                if (autoResetDevice && vm.connected)
                    SetTimer(AutoResetEngineCallback, -1800)
                if (deviceLockEnabled)
                    SetTimer(EnforceDefaultDevicesLoud, -900)
            }
        }
    } else if (wParam = 0x0007 && deviceLockEnabled) {
        SetTimer(EnforceDefaultDevicesSilent, -900)
    }
}

AutoResetEngineCallback() {
    global lastAutoReset
    if (!autoResetDevice || !vm.connected)
        return
    if (A_TickCount - lastAutoReset < 5000)
        return

    lastAutoReset := A_TickCount
    DllCall(pSetFloat, "AStr", "Command.Restart", "Float", 1.0)
    ShowQuickTip("Audio device reconnected — Restarting VoiceMeeter Engine...", 1600)
    SetTimer(ResyncAfterEngineRestart, -650)
}

ToggleAutoResetDevice(*) {
    global autoResetDevice := (autoResetDevice = 1) ? 0 : 1
    IniWrite(autoResetDevice, iniPath, "Settings", "AutoResetDevice")
    RefreshAutomationPills()
    RefreshShortcutLabels()
    ShowQuickTip("Auto-Reset on Device Reconnect: " (autoResetDevice ? "ON" : "OFF"), 1200)
}

OnModeToggle(*) {
    global exclusiveMode := (exclusiveMode = 1) ? 0 : 1
    if (exclusiveMode = 1 && activeTargets.Length > 1) {
        global activeTargets := [activeTargets[1]]
    }
    vm.gains.Clear()
    SyncAllActiveTargets(true)
    RefreshModePillVisual()
    RefreshChannelVisuals(true)
    RefreshHeroSoloMonoPills()
    if (showAdvancedPanel = 1)
        RefreshStripRoutingPills()
    SyncSelectedSoloEffect(true)
    SaveSettings()
    UpdateStatusBanner()
}

OnTargetClick(clickedParam, *) {
    Critical
    SetTimer(GlideStep, 0)
    vm.gliding := false

    if (exclusiveMode = 1) {
        global activeTargets := [clickedParam]
    } else {
        foundIdx := 0
        for idx, p in activeTargets {
            if (p = clickedParam) {
                foundIdx := idx
                break
            }
        }
        if (foundIdx > 0)
            activeTargets.RemoveAt(foundIdx)
        else
            activeTargets.Push(clickedParam)
    }

    vm.gains.Clear()
    vm.mutes.Clear()
    SyncAllActiveTargets(true)
    SyncSelectedSoloEffect(true)
    RefreshChannelVisuals(true)
    RefreshHeroSoloMonoPills()
    if (showAdvancedPanel = 1)
        RefreshStripRoutingPills()
    SaveSettings()
    UpdateStatusBanner()
}

OnRenameChannel(param, *) {
    currentName := nameMap[param]
    defaultName := defaultNameMap[param]

    Suspend(1)
    settingsGui.Opt("-AlwaysOnTop")
    try {
        ib := InputBox(
            "Enter a custom label for " param " (" defaultName "):`n(Leave blank to restore default)",
            "Rename Channel",
            "w320 h135",
            currentName
        )
    } finally {
        settingsGui.Opt("+AlwaysOnTop")
        Suspend(0)
    }

    if (ib.Result = "Cancel")
        return

    newName := Trim(ib.Value)
    if (newName = "") {
        nameMap[param] := defaultName
        IniDelete(iniPath, "Names", param)
    } else {
        nameMap[param] := newName
        IniWrite(newName, iniPath, "Names", param)
    }

    RefreshChannelVisuals(true)
    if (IsGuiAlive(kbGui) && kbLabelMap.Has("target_" param))
        kbLabelMap["target_" param].Value := nameMap[param]

    RefreshShortcutLabels()
    UpdateStatusBanner()
}

ResetChannelGain(param, *) {
    Critical
    gainParam := GetGainParamForChannel(param)
    ApplyChannelGainWithDuck(gainParam, 0.0)
    if hoverCache.Has(gainParam)
        hoverCache.Delete(gainParam)

    if vm.gains.Has(param) {
        vm.gains[param].current := 0.0
        vm.gains[param].target  := 0.0
    }

    SetTimer(FlushOwnDirtyFlag, -350)

    if DllCall("IsWindowVisible", "Ptr", settingsGui.Hwnd) {
        UpdateStatusBanner()
        RefreshAllChannelReadouts(true)
    }
}

IsTargetActive(param) {
    for item in activeTargets {
        if (item = param)
            return true
    }
    return false
}

SaveSettings() {
    joined := ""
    for idx, param in activeTargets
        joined .= (idx > 1 ? "," : "") param
    IniWrite(joined, iniPath, "Settings", "Targets")
    IniWrite(exclusiveMode, iniPath, "Settings", "ExclusiveMode")
}

UpdateStatusBanner() {
    static lastLineCount   := 1
    static lastMuteState   := -1
    static lastAccentMode  := -1
    static lastStatusLines := ""
    static lastSubLine     := ""
    static lastLayerLine   := ""
    static lastLayerState  := -1

    anyMuted := false
    layerIdx := GetActiveGainLayerIndex()

    if (!vm.connected) {
        lines     := "VoiceMeeter Potato Offline"
        subLine   := "Waiting for VoiceMeeter Potato to start..."
        layerLine := "  " Chr(0x21B3) "  Layer: Offline"
        lineCount := 1
    } else if (activeTargets.Length = 0) {
        lines     := "No Channel Selected"
        subLine   := "Click any Virtual Input, Hardware Input, or Bus below"
        layerLine := "  " Chr(0x21B3) "  Layer: None"
        lineCount := 1
    } else {
        lines := ""
        for idx, param in activeTargets {
            label := nameMap.Has(param) ? nameMap[param] : param
            if vm.gains.Has(param) {
                val := Round(vm.gains[param].current, 1)
                if (Abs(val) < 0.05)
                    val := 0.0
                dbStr := (val > 0 ? "+" : "") Format("{:.1f} dB", val)
            } else {
                dbStr := "0.0 dB"
            }

            isMuted := vm.mutes.Has(param) && vm.mutes[param]
            if isMuted
                anyMuted := true
            muteTag := isMuted ? "   [MUTED]" : ""

            dOff := GetDuckOffsetForParam(GetGainParamForChannel(param))
            duckTag := (dOff <= -0.1) ? "   [DUCK " Format("{:.1f}", dOff) " dB]" : ""

            lines .= (idx > 1 ? "`n" : "") "•  " label "   —   " dbStr muteTag duckTag
        }
        lineCount := activeTargets.Length

        soloParam := GetSoloTarget()
        if (soloParam != "") {
            fxObj := GetSelectedEffectObj(soloParam)
            fullParam := soloParam "." fxObj.key
            fxVal := vm.fxValues.Has(fullParam) ? vm.fxValues[fullParam].val : 0.0
            subLine := Chr(0x21B3) "  FX:  " fxObj.label "   [ " FormatEffectValue(fxObj, fxVal) " ]"

            if IsInputStrip(soloParam) {
                if (layerIdx = 0) {
                    layerLine := "  " Chr(0x21B3) "  Layer:  Master Gain  (All Routed Buses)"
                } else {
                    bObj := outputBuses[layerIdx]
                    bName := nameMap.Has(bObj.param) ? nameMap[bObj.param] : bObj.name
                    layerLine := "  " Chr(0x21B3) "  Layer:  " bObj.name " (" bName ") Submix Only"
                }
            } else if IsActiveHardwareBus() {
                bIdx := Integer(RegExReplace(soloParam, "\D"))
                bTag := outputBuses[bIdx + 1].name
                dMs  := GetActiveBusSyncDelay()
                layerLine := "  " Chr(0x21B3) "  Sync Delay (" bTag "):  " dMs " ms   •   Hold Shift + Scroll"
            } else {
                layerLine := "  " Chr(0x21B3) "  Output Bus Master Fader"
            }
        } else {
            subLine   := activeTargets.Length " channels linked   •   Spread-Locked (-60.0 to +12.0 dB)"
            layerLine := "  " Chr(0x21B3) "  Multi-Target Master Faders"
        }
    }

    muteFlag := anyMuted ? 1 : 0
    if (muteFlag != lastMuteState) {
        lastMuteState := muteFlag
        UpdateTrayIcon(anyMuted)
        if anyMuted {
            heroMutePill.SetFont("s7 Bold cF87171")
            heroMutePill.Opt("Background3A1A20")
            heroMutePill.Value := "MUTED"
        } else {
            heroMutePill.SetFont("s7 Bold cA1A1AA")
            heroMutePill.Opt("Background1E1E28")
            heroMutePill.Value := "MUTE"
        }
    }

    accentMode := anyMuted ? 2 : (layerIdx > 0 ? 1 : 0)
    if (accentMode != lastAccentMode) {
        lastAccentMode := accentMode
        if (accentMode = 2) {
            statusText.SetFont("s10 Bold cF87171")
            heroAccent.Opt("cF87171")
        } else if (accentMode = 1) {
            statusText.SetFont("s10 Bold cF59E0B")
            heroAccent.Opt("cF59E0B")
        } else {
            statusText.SetFont("s10 Bold c38BDF8")
            heroAccent.Opt("c38BDF8")
        }
    }

    if (lines != lastStatusLines) {
        lastStatusLines := lines
        statusText.Value := lines
    }
    if (subLine != lastSubLine) {
        lastSubLine := subLine
        heroSubText.Value := subLine
    }
    if (layerLine != lastLayerLine) {
        lastLayerLine := layerLine
        layerPill.Value := layerLine
    }

    layerState := IsLayerPillHighlighted() ? 1 : 0
    if (layerState != lastLayerState) {
        lastLayerState := layerState
        layerPill.SetFont(layerState ? "s8 Bold cF59E0B" : "s8 Bold cD4D4D8")
        if (lastHoverKey != "layerPill")
            layerPill.Opt(layerState ? "Background332614" : "Background221B11")
    }

    if (lineCount != lastLineCount) {
        lastLineCount := lineCount
        RecalculateMainLayout(true)
    }
}

UpdateTrayIcon(isMuted) {
    try {
        if isMuted {
            if FileExist(mutedIconPath)
                TraySetIcon(mutedIconPath)
            else
                TraySetIcon("shell32.dll", 28)
        } else {
            if FileExist(customIconPath)
                TraySetIcon(customIconPath)
            else if A_IsCompiled
                TraySetIcon(A_ScriptFullPath, 1)
            else
                TraySetIcon()
        }
    }
}

ShowQuickTip(msg, durationMs := 1000) {
    ToolTip(msg)
    SetTimer(ClearQuickTip, -durationMs)
}

ClearQuickTip() {
    ToolTip()
}

; ==============================================================================
; 10. WATCHDOG, SPREAD-LOCKED ACCELERATION & SMOOTH GLIDE ENGINE
; ==============================================================================
WatchdogCheck() {
    static lastMidiHealTick := 0
    if deviceLockEnabled
        EnforceDefaultDevices(true)

    if (midiDeviceIdx >= 0 && !midiHandle && !midiLearnArmed && (A_TickCount - lastMidiHealTick >= 10000)) {
        lastMidiHealTick := A_TickCount
        InitMidiDevice()
    }

    ; Trim stale entries in transient caches (>10s old) so long sessions stay lean
    now := A_TickCount
    staleHover := []
    for k, entry in hoverCache {
        if ((now - entry.tick) > 10000)
            staleHover.Push(k)
    }
    for k in staleHover
        hoverCache.Delete(k)

    staleFx := []
    for k, entry in vm.fxValues {
        if ((now - entry.tick) > 10000)
            staleFx.Push(k)
    }
    for k in staleFx
        vm.fxValues.Delete(k)

    if (pttEnabled = 1 && !pttHeldActive && vm.connected && pttMicStrip != "") {
        curM := 0.0
        DllCall(pGetFloat, "AStr", pttMicStrip ".Mute", "Float*", &curM)
        if (curM < 0.5)
            ApplyPttMicState()
    }

    vmType := 0
    isOnline := (DllCall(pGetType, "Int*", &vmType, "Int") = 0 && vmType > 0)

    if (isOnline && !vm.connected) {
        vm.connected := true
        SetTimer(GlideStep, 0)
        vm.gliding := false
        vm.gains.Clear()
        vm.mutes.Clear()
        vm.fxValues.Clear()
        duckBaseGains.Clear()
        SyncAllActiveTargets(true)
        SyncSelectedSoloEffect(true)
        if (pttEnabled = 1)
            ApplyPttMicState()
        if DllCall("IsWindowVisible", "Ptr", settingsGui.Hwnd) {
            if (showAdvancedPanel = 1)
                RefreshStripRoutingPills()
            RefreshHeroSoloMonoPills()
            RefreshRowSoloMonoButtons()
            UpdateStatusBanner()
            RefreshAllChannelReadouts(true)
        }
    } else if (!isOnline && vm.connected) {
        vm.connected := false
        SetTimer(GlideStep, 0)
        vm.gliding := false
        if DllCall("IsWindowVisible", "Ptr", settingsGui.Hwnd)
            UpdateStatusBanner()
    }
}

SyncAllActiveTargets(forceRead := false) {
    if !vm.connected
        return

    dirty := DllCall(pIsDirty)
    if (!forceRead && dirty != 1)
        return

    for param in activeTargets {
        gainParam := GetGainParamForChannel(param)
        liveGain := 0.0
        if (DllCall(pGetFloat, "AStr", gainParam, "Float*", &liveGain, "Int") = 0) {
            baseGain := Round(Max(-60.0, Min(12.0, liveGain - GetDuckOffsetForParam(gainParam))), 2)
            vm.gains[param] := { current: baseGain, target: baseGain }
        } else if !vm.gains.Has(param) {
            vm.gains[param] := { current: 0.0, target: 0.0 }
        }

        liveMute := 0.0
        if (DllCall(pGetFloat, "AStr", param ".Mute", "Float*", &liveMute, "Int") = 0)
            vm.mutes[param] := (liveMute >= 0.5)
        else if !vm.mutes.Has(param)
            vm.mutes[param] := false
    }
}

QueueWheelStep(dir) {
    Critical
    if (!vm.connected || activeTargets.Length = 0)
        return

    now := A_TickCount
    dt  := now - vm.lastTick

    if (!vm.gliding && (now - vm.lastWriteTick > 350))
        SyncAllActiveTargets(false)

    if (dir != vm.lastDir)
        dt := slowMs

    t    := Max(0.0, Min(1.0, (slowMs - dt) / (slowMs - fastMs)))
    step := minStep * ((maxStep / minStep) ** t)

    for param in activeTargets {
        if !vm.gains.Has(param) {
            gainParam := GetGainParamForChannel(param)
            liveGain := 0.0
            DllCall(pGetFloat, "AStr", gainParam, "Float*", &liveGain, "Int")
            baseGain := Round(Max(-60.0, Min(12.0, liveGain - GetDuckOffsetForParam(gainParam))), 2)
            vm.gains[param] := { current: baseGain, target: baseGain }
        }
        if (dir != vm.lastDir)
            vm.gains[param].target := vm.gains[param].current
    }

    rawDelta := dir * step
    clampedDelta := rawDelta

    if (activeTargets.Length > 1) {
        minTarget := 12.0
        maxTarget := -60.0
        for param in activeTargets {
            tVal := vm.gains[param].target
            if (tVal < minTarget)
                minTarget := tVal
            if (tVal > maxTarget)
                maxTarget := tVal
        }
        if (rawDelta > 0)
            clampedDelta := Max(0.0, Min(rawDelta, 12.0 - maxTarget))
        else if (rawDelta < 0)
            clampedDelta := Min(0.0, Max(rawDelta, -60.0 - minTarget))
    }

    for param in activeTargets {
        entry := vm.gains[param]
        entry.target := Max(-60.0, Min(12.0, entry.target + clampedDelta))
    }

    vm.lastTick := now
    vm.lastDir  := dir

    if !vm.gliding {
        vm.gliding := true
        SetTimer(GlideStep, 20)
    }
}

GlideStep() {
    Critical
    stillMoving := false

    for param in activeTargets {
        if !vm.gains.Has(param)
            continue

        entry := vm.gains[param]
        diff  := entry.target - entry.current

        if (Abs(diff) <= 0.05) {
            entry.current := Round(entry.target, 2)
        } else {
            entry.current := Round(entry.current + (diff * glideFactor), 2)
            stillMoving := true
        }

        ApplyChannelGainWithDuck(GetGainParamForChannel(param), entry.current)
    }

    if DllCall("IsWindowVisible", "Ptr", settingsGui.Hwnd) {
        UpdateStatusBanner()
        RefreshAllChannelReadouts(true)
    }
    ShowHeadUnitOsd("volume")

    if !stillMoving {
        vm.gliding := false
        SetTimer(GlideStep, 0)
        SetTimer(FlushOwnDirtyFlag, -350)
    }
}

FlushOwnDirtyFlag() {
    if !vm.gliding
        DllCall(pIsDirty)
}

ToggleVMMute() {
    Critical
    if (!vm.connected || activeTargets.Length = 0)
        return

    DllCall(pIsDirty)

    anyUnmuted := false
    for param in activeTargets {
        isMuted := 0.0
        DllCall(pGetFloat, "AStr", param ".Mute", "Float*", &isMuted)
        if (isMuted < 0.5)
            anyUnmuted := true
    }

    newMute := anyUnmuted ? 1.0 : 0.0
    for param in activeTargets {
        DllCall(pSetFloat, "AStr", param ".Mute", "Float", newMute)
        vm.mutes[param] := anyUnmuted
    }

    vm.lastWriteTick := A_TickCount
    SetTimer(FlushOwnDirtyFlag, -350)

    UpdateTrayIcon(anyUnmuted)
    if DllCall("IsWindowVisible", "Ptr", settingsGui.Hwnd) {
        UpdateStatusBanner()
        RefreshAllChannelReadouts(true)
    }
    ShowHeadUnitOsd("volume")
}

; ==============================================================================
; 11. STARTUP INITIALIZATION
; ==============================================================================
EnsureVoicemeeterRunning()
Sleep(50)
vmType := 0
vm.connected := (DllCall(pGetType, "Int*", &vmType, "Int") = 0 && vmType > 0)

if (isFirstRun && vm.connected && pGetLevel) {
    for st in inputStrips {
        lL := 0.0
        lR := 0.0
        DllCall(pGetLevel, "Int", 0, "Int", st.idx * 8, "Float*", &lL)
        DllCall(pGetLevel, "Int", 0, "Int", (st.idx * 8) + 1, "Float*", &lR)
        if (Max(lL, lR) > 0.002) {
            activeTargets := [st.param]
            SaveSettings()
            break
        }
    }
}

if vm.connected {
    SyncAllActiveTargets(true)
    SyncSelectedSoloEffect(true)
    if (pttEnabled = 1)
        ApplyPttMicState()
}

OnMessage(0x03C3, OnMidiData)
InitMidiDevice()

RegisterAllHotkeys()
RefreshModePillVisual()
RefreshChannelVisuals(true)
RefreshHeroSoloMonoPills()
RefreshRowSoloMonoButtons()
RefreshAutomationPills()
RefreshStripRoutingPills()
RefreshSnapshotPills()
SetTimer(WatchdogCheck, 2000)
SetTimer(GuiLiveSyncTick, 180)
if (duckEnabled = 1)
    SetTimer(AutoDuckTick, 25)
if (deviceLockEnabled = 1)
    EnforceDefaultDevices(true)

UpdateStatusBanner()
RecalculateMainLayout(false)
RegisterAudioDeviceWatcher()
settingsGui.Show("AutoSize")

if (checkUpdatesStart = 1)
    SetTimer(CheckUpdatesOnBoot, -2500)