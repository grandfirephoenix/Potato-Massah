#Requires AutoHotkey v2.0
#SingleInstance Force
InstallKeybdHook()
;@Ahk2Exe-SetMainIcon icon.ico

; ==============================================================================
; 1. VOICEMEETER REMOTE API, DARK THEME & ICON INITIALIZATION
; ==============================================================================
customIconPath := A_ScriptDir "\icon.ico"
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
    SetTimer(ClearQuickTip, 0)
    SetTimer(HideHeadUnitOsd, 0)
    SetTimer(HoverLeaveWatch, 0)
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
                DllCall(pSetPreferredAppMode, "Int", 2)  ; ForceDark
            if pFlushMenuThemes
                DllCall(pFlushMenuThemes)
        }
    }
}

ApplySleekWindowTheme(guiObj, isOsd := false) {
    try {
        ; Immersive Dark Mode (Win11 22H2+ attr 20, Win10 fallback attr 19)
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", guiObj.Hwnd, "UInt", 20, "Int*", 1, "UInt", 4)
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", guiObj.Hwnd, "UInt", 19, "Int*", 1, "UInt", 4)
        ; Rounded Window Corners (DWMWCP_ROUND = 2)
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", guiObj.Hwnd, "UInt", 33, "Int*", 2, "UInt", 4)
        if !isOsd {
            ; Seamless #0D0D11 Titlebar Caption (BGR: 0x00110D0D) & Subtle #262632 Border
            DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", guiObj.Hwnd, "UInt", 35, "UInt*", 0x00110D0D, "UInt", 4)
            DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", guiObj.Hwnd, "UInt", 34, "UInt*", 0x00322626, "UInt", 4)
        } else {
            ; Crisp Cyan-Tinted Border on Floating Head-Unit HUD
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

EnableDarkSystemMenus()

; ==============================================================================
; 2. CONFIGURATION, EFFECT DEFINITIONS & PERSISTENT STATE
; ==============================================================================
iniPath     := A_ScriptDir "\volume_settings.ini"
minStep     := 0.2    ; Starting dB step for slow, single-click adjustments
maxStep     := 4.5    ; Maximum dB step per notch during a fast spin
slowMs      := 250.0  ; Tick interval (ms) at or above which step stays at minStep
fastMs      := 15.0   ; Tick interval (ms) at or below which step reaches maxStep
glideFactor := 0.35   ; Smoothing factor per 20 ms frame

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

outputBuses := [
    { param: "Bus[0]", name: "A1" },
    { param: "Bus[1]", name: "A2" },
    { param: "Bus[2]", name: "A3" },
    { param: "Bus[3]", name: "A4" },
    { param: "Bus[4]", name: "A5" },
    { param: "Bus[5]", name: "B1" },
    { param: "Bus[6]", name: "B2" },
    { param: "Bus[7]", name: "B3" }
]

allChannels := []
for item in virtualInputs
    allChannels.Push(item)
for item in hardwareInputs
    allChannels.Push(item)
for item in outputBuses
    allChannels.Push(item)

; Per-channel-type effect definitions matching VoiceMeeter Potato
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

; Populate default and custom channel names from INI
defaultNameMap := Map()
nameMap        := Map()

for item in virtualInputs {
    defaultNameMap[item.param] := item.name
    nameMap[item.param]        := item.name
}
for item in hardwareInputs {
    defaultNameMap[item.param] := item.name
    savedName := IniRead(iniPath, "Names", item.param, "")
    nameMap[item.param] := (savedName != "") ? savedName : item.name
}
for item in outputBuses {
    defaultNameMap[item.param] := item.name
    savedName := IniRead(iniPath, "Names", item.param, "")
    nameMap[item.param] := (savedName != "") ? savedName : item.name
}

; Build full list of customizable hotkeys (General/Channel/FX + all 16 I/O channels)
hotkeyDefs := [
    { id: "toggleGui",  group: "general", param: "", label: "Toggle Control Panel",     def: "^!v",     fn: (*) => ToggleGui() },
    { id: "chanPrev",   group: "general", param: "", label: "Target: Previous Channel", def: "^+Left",  fn: (*) => CycleSoloChannel(-1) },
    { id: "chanNext",   group: "general", param: "", label: "Target: Next Channel",     def: "^+Right", fn: (*) => CycleSoloChannel(1) },
    { id: "fxPrev",     group: "general", param: "", label: "Solo FX: Previous Effect", def: "^!Left",  fn: (*) => CycleSoloEffect(-1) },
    { id: "fxNext",     group: "general", param: "", label: "Solo FX: Next Effect",     def: "^!Right", fn: (*) => CycleSoloEffect(1) },
    { id: "fxUp",       group: "general", param: "", label: "Solo FX: Increase",        def: "^!Up",    fn: (*) => AdjustSoloEffect(1, false) },
    { id: "fxDown",     group: "general", param: "", label: "Solo FX: Decrease",        def: "^!Down",  fn: (*) => AdjustSoloEffect(-1, false) },
    { id: "fxFineUp",   group: "general", param: "", label: "Solo FX: Fine Increase",   def: "^!+Up",   fn: (*) => AdjustSoloEffect(1, true) },
    { id: "fxFineDown", group: "general", param: "", label: "Solo FX: Fine Decrease",   def: "^!+Down", fn: (*) => AdjustSoloEffect(-1, true) },
    { id: "fxReset",    group: "general", param: "", label: "Solo FX: Reset to 0",      def: "^!0",     fn: (*) => ResetSoloEffect() }
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

; Load saved target selections (defaults to Strip[7] / VAIO3 in Single-Target mode)
savedTargets  := IniRead(iniPath, "Settings", "Targets", "Strip[7]")
exclusiveMode := Integer(IniRead(iniPath, "Settings", "ExclusiveMode", "1"))

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
    fxIndex:       Map(),
    fxValues:      Map(),
    gliding:       false,
    lastTick:      0,
    lastWriteTick: 0,
    lastDir:       0
}

; ==============================================================================
; 3. SLEEK DARK-MODE CONTROL PANEL GUI & TRAY MENU
; ==============================================================================
UpdateTrayIcon(false)

rowVisualMap    := Map()
ctrlHwndToParam := Map()
hoverZones      := []
hoverCache      := Map()
movableControls := []
currentDeltaY   := 0

; Interactive hover registry for flat custom buttons & channel pills
hoverStyleMap   := Map()
lastHoverKey    := ""

AddBodyControl(ctrl, baseY) {
    movableControls.Push({ ctrl: ctrl, baseY: baseY })
    return ctrl
}

RegisterHoverRow(param, x1, baseY1, x2, baseY2, ctrls*) {
    hoverZones.Push({ param: param, x1: x1, baseY1: baseY1, x2: x2, baseY2: baseY2 })
    for c in ctrls
        ctrlHwndToParam[c.Hwnd] := param
}

RegisterButtonHover(ctrl, baseBg, hoverBg) {
    hoverStyleMap[ctrl.Hwnd] := {
        key: "btn_" ctrl.Hwnd,
        ctrls: [ctrl],
        getBg: (*) => baseBg,
        hoverBg: hoverBg
    }
}

RegisterPillHover(param, ctrls*) {
    entry := {
        key: "pill_" param,
        ctrls: ctrls,
        getBg: (*) => IsTargetActive(param) ? "152433" : "16161E",
        hoverBg: IsTargetActive(param) ? "1B3146" : "20202C"
    }
    for c in ctrls
        hoverStyleMap[c.Hwnd] := entry
}

OnGuiMouseMove(wParam, lParam, msg, hwnd) {
    global lastHoverKey
    MouseGetPos(, , &hoverWin, &hoverCtrl, 2)

    newKey := ""
    if (hoverCtrl && hoverStyleMap.Has(hoverCtrl)) {
        item := hoverStyleMap[hoverCtrl]
        newKey := item.key
        if (newKey != lastHoverKey) {
            ResetLastHover()
            lastHoverKey := newKey
            hv := IsObject(item.hoverBg) ? item.hoverBg.Call() : item.hoverBg
            for c in item.ctrls {
                try c.Opt("Background" hv)
                try c.Redraw()
            }
            SetTimer(HoverLeaveWatch, 80)
        }
    } else if (lastHoverKey != "") {
        ResetLastHover()
    }
}

ResetLastHover() {
    global lastHoverKey
    if (lastHoverKey = "")
        return
    for _, item in hoverStyleMap {
        if (item.key = lastHoverKey) {
            bg := item.getBg.Call()
            for c in item.ctrls {
                try c.Opt("Background" bg)
                try c.Redraw()
            }
            break
        }
    }
    lastHoverKey := ""
}

HoverLeaveWatch() {
    MouseGetPos(, , &hoverWin, &hoverCtrl, 2)
    if (!hoverCtrl || !hoverStyleMap.Has(hoverCtrl)) {
        ResetLastHover()
        SetTimer(HoverLeaveWatch, 0)
    }
}

OnMessage(0x0200, OnGuiMouseMove)

settingsGui := Gui("+AlwaysOnTop -MaximizeBox", "VoiceMeeter Potato Massah")
settingsGui.MarginX := 16
settingsGui.MarginY := 14
settingsGui.BackColor := "0D0D11"
settingsGui.SetFont("s9 cF4F4F5", "Segoe UI")
ApplySleekWindowTheme(settingsGui, false)

; --- Hero Telemetry Card ---
heroAccent := settingsGui.AddProgress("x16 y12 w436 h2 Background0D0D11 c38BDF8", 100)
heroBg     := settingsGui.AddText("x16 y14 w436 h74 Background15151C", "")

settingsGui.SetFont("s8 Bold c71717A", "Segoe UI")
settingsGui.AddText("x28 y20 w210 h16 Background15151C", "ACTIVE WHEEL TARGET")

; Mode Pill Toggle (Top-Right of Hero Card)
settingsGui.SetFont("s8 Bold c38BDF8", "Segoe UI")
modePill := settingsGui.AddText("x292 y18 w148 h20 Center +0x200 Background1B2B3A", "◉  Single-Target Mode")
modePill.OnEvent("Click", OnModeToggle)
hoverStyleMap[modePill.Hwnd] := {
    key: "modePill",
    ctrls: [modePill],
    getBg: (*) => (exclusiveMode = 1) ? "1B2B3A" : "22222E",
    hoverBg: (*) => (exclusiveMode = 1) ? "23384C" : "2C2C3B"
}

settingsGui.SetFont("s10 Bold c38BDF8", "Segoe UI")
statusText := settingsGui.AddText("x28 y40 w412 h20 Background15151C", "")

settingsGui.SetFont("s8 Norm cA1A1AA", "Segoe UI")
heroSubText := settingsGui.AddText("x28 y62 w412 h18 Background15151C", "")

; --- Section 1: Virtual Inputs ---
settingsGui.SetFont("s8 Bold c71717A", "Segoe UI")
AddBodyControl(settingsGui.AddText("x16 y100 w436 h16 Background0D0D11", "VIRTUAL INPUTS"), 100)

yPos := 120
for item in virtualInputs {
    active := IsTargetActive(item.param)
    bgHex  := active ? "152433" : "16161E"

    pillBg := AddBodyControl(settingsGui.AddText("x16 y" yPos " w386 h26 Background" bgHex, ""), yPos)

    settingsGui.SetFont("s9 Bold c" (active ? "38BDF8" : "52525B"), "Segoe UI")
    dotCtrl := AddBodyControl(settingsGui.AddText("x26 y" yPos " w16 h26 +0x200 Background" bgHex, active ? "●" : "○"), yPos)

    settingsGui.SetFont("s9 " (active ? "Bold cF4F4F5" : "Norm cD4D4D8"), "Segoe UI")
    lblCtrl := AddBodyControl(settingsGui.AddText("x44 y" yPos " w264 h26 +0x200 Background" bgHex, nameMap[item.param]), yPos)

    settingsGui.SetFont("s8 Norm c52525B", "Segoe UI")
    tagCtrl := AddBodyControl(settingsGui.AddText("x312 y" yPos " w80 h26 Right +0x200 Background" bgHex, item.param), yPos)

    settingsGui.SetFont("s8 Bold cA1A1AA", "Segoe UI")
    rstBtn := AddBodyControl(settingsGui.AddText("x406 y" yPos " w46 h26 Center +0x200 Background1C1C26", "0dB"), yPos)

    for c in [pillBg, dotCtrl, lblCtrl, tagCtrl]
        c.OnEvent("Click", OnTargetClick.Bind(item.param))
    rstBtn.OnEvent("Click", ResetChannelGain.Bind(item.param))

    rowVisualMap[item.param] := { bg: pillBg, dot: dotCtrl, lbl: lblCtrl, tag: tagCtrl }
    RegisterPillHover(item.param, pillBg, dotCtrl, lblCtrl, tagCtrl)
    RegisterButtonHover(rstBtn, "1C1C26", "282836")
    RegisterHoverRow(item.param, 16, yPos - 1, 452, yPos + 27, pillBg, dotCtrl, lblCtrl, tagCtrl, rstBtn)
    yPos += 30
}

; --- Section 2: Hardware Inputs (Renameable + 0dB Reset) ---
settingsGui.SetFont("s8 Bold c71717A", "Segoe UI")
AddBodyControl(settingsGui.AddText("x16 y" (yPos + 8) " w436 h16 Background0D0D11", "HARDWARE INPUTS"), yPos + 8)
yPos += 28
for idx, item in hardwareInputs {
    active := IsTargetActive(item.param)
    bgHex  := active ? "152433" : "16161E"
    isLeft := (Mod(idx, 2) = 1)
    xCol   := isLeft ? 16 : 238

    pillBg := AddBodyControl(settingsGui.AddText("x" xCol " y" yPos " w152 h26 Background" bgHex, ""), yPos)

    settingsGui.SetFont("s9 Bold c" (active ? "38BDF8" : "52525B"), "Segoe UI")
    dotCtrl := AddBodyControl(settingsGui.AddText("x" (xCol + 8) " y" yPos " w14 h26 +0x200 Background" bgHex, active ? "●" : "○"), yPos)

    settingsGui.SetFont("s9 " (active ? "Bold cF4F4F5" : "Norm cD4D4D8"), "Segoe UI")
    lblCtrl := AddBodyControl(settingsGui.AddText("x" (xCol + 24) " y" yPos " w120 h26 +0x200 Background" bgHex, nameMap[item.param]), yPos)

    settingsGui.SetFont("s8 Norm cA1A1AA", "Segoe UI")
    renBtn := AddBodyControl(settingsGui.AddText("x" (xCol + 155) " y" yPos " w24 h26 Center +0x200 Background1C1C26", Chr(0x270E)), yPos)

    settingsGui.SetFont("s8 Bold cA1A1AA", "Segoe UI")
    rstBtn := AddBodyControl(settingsGui.AddText("x" (xCol + 182) " y" yPos " w32 h26 Center +0x200 Background1C1C26", "0dB"), yPos)

    for c in [pillBg, dotCtrl, lblCtrl] {
        c.OnEvent("Click", OnTargetClick.Bind(item.param))
        c.OnEvent("ContextMenu", OnRenameChannel.Bind(item.param))
    }
    renBtn.OnEvent("Click", OnRenameChannel.Bind(item.param))
    rstBtn.OnEvent("Click", ResetChannelGain.Bind(item.param))

    rowVisualMap[item.param] := { bg: pillBg, dot: dotCtrl, lbl: lblCtrl, tag: "" }
    RegisterPillHover(item.param, pillBg, dotCtrl, lblCtrl)
    RegisterButtonHover(renBtn, "1C1C26", "282836")
    RegisterButtonHover(rstBtn, "1C1C26", "282836")
    RegisterHoverRow(item.param, xCol, yPos - 1, xCol + 214, yPos + 27, pillBg, dotCtrl, lblCtrl, renBtn, rstBtn)

    if (!isLeft || idx = hardwareInputs.Length)
        yPos += 30
}

; --- Section 3: Output Buses (Renameable + 0dB Reset) ---
settingsGui.SetFont("s8 Bold c71717A", "Segoe UI")
AddBodyControl(settingsGui.AddText("x16 y" (yPos + 8) " w436 h16 Background0D0D11", "OUTPUT BUSES"), yPos + 8)
yPos += 28
for idx, item in outputBuses {
    active := IsTargetActive(item.param)
    bgHex  := active ? "152433" : "16161E"
    isLeft := (Mod(idx, 2) = 1)
    xCol   := isLeft ? 16 : 238

    pillBg := AddBodyControl(settingsGui.AddText("x" xCol " y" yPos " w152 h26 Background" bgHex, ""), yPos)

    settingsGui.SetFont("s9 Bold c" (active ? "38BDF8" : "52525B"), "Segoe UI")
    dotCtrl := AddBodyControl(settingsGui.AddText("x" (xCol + 8) " y" yPos " w14 h26 +0x200 Background" bgHex, active ? "●" : "○"), yPos)

    settingsGui.SetFont("s9 " (active ? "Bold cF4F4F5" : "Norm cD4D4D8"), "Segoe UI")
    lblCtrl := AddBodyControl(settingsGui.AddText("x" (xCol + 24) " y" yPos " w120 h26 +0x200 Background" bgHex, nameMap[item.param]), yPos)

    settingsGui.SetFont("s8 Norm cA1A1AA", "Segoe UI")
    renBtn := AddBodyControl(settingsGui.AddText("x" (xCol + 155) " y" yPos " w24 h26 Center +0x200 Background1C1C26", Chr(0x270E)), yPos)

    settingsGui.SetFont("s8 Bold cA1A1AA", "Segoe UI")
    rstBtn := AddBodyControl(settingsGui.AddText("x" (xCol + 182) " y" yPos " w32 h26 Center +0x200 Background1C1C26", "0dB"), yPos)

    for c in [pillBg, dotCtrl, lblCtrl] {
        c.OnEvent("Click", OnTargetClick.Bind(item.param))
        c.OnEvent("ContextMenu", OnRenameChannel.Bind(item.param))
    }
    renBtn.OnEvent("Click", OnRenameChannel.Bind(item.param))
    rstBtn.OnEvent("Click", ResetChannelGain.Bind(item.param))

    rowVisualMap[item.param] := { bg: pillBg, dot: dotCtrl, lbl: lblCtrl, tag: "" }
    RegisterPillHover(item.param, pillBg, dotCtrl, lblCtrl)
    RegisterButtonHover(renBtn, "1C1C26", "282836")
    RegisterButtonHover(rstBtn, "1C1C26", "282836")
    RegisterHoverRow(item.param, xCol, yPos - 1, xCol + 214, yPos + 27, pillBg, dotCtrl, lblCtrl, renBtn, rstBtn)

    if (!isLeft || idx = outputBuses.Length)
        yPos += 30
}

; --- Footer Divider & Sleek Action Pills ---
AddBodyControl(settingsGui.AddText("x16 y" (yPos + 4) " w436 h1 Background22222E", ""), yPos + 4)

settingsGui.SetFont("s8 c71717A", "Segoe UI")
footerHintText := AddBodyControl(settingsGui.AddText("x16 y" (yPos + 12) " w146 h28 Background0D0D11", ""), yPos + 12)

settingsGui.SetFont("s8 Bold cD4D4D8", "Segoe UI")
featuresBtn := AddBodyControl(settingsGui.AddText("x166 y" (yPos + 12) " w62 h28 Center +0x200 Background191922", "Features"), yPos + 12)
featuresBtn.OnEvent("Click", (*) => OpenFeaturesGui())
RegisterButtonHover(featuresBtn, "191922", "242432")

settingsGui.SetFont("s8 Bold c38BDF8", "Segoe UI")
keybindBtn := AddBodyControl(settingsGui.AddText("x232 y" (yPos + 12) " w68 h28 Center +0x200 Background152433", "Keybinds"), yPos + 12)
keybindBtn.OnEvent("Click", (*) => OpenKeybindGui())
RegisterButtonHover(keybindBtn, "152433", "1C3247")

settingsGui.SetFont("s8 Bold cD4D4D8", "Segoe UI")
restartBtn := AddBodyControl(settingsGui.AddText("x304 y" (yPos + 12) " w84 h28 Center +0x200 Background191922", "Restart Engine"), yPos + 12)
restartBtn.OnEvent("Click", RestartAudioEngine)
RegisterButtonHover(restartBtn, "191922", "242432")

settingsGui.SetFont("s8 Bold cA1A1AA", "Segoe UI")
hideBtn := AddBodyControl(settingsGui.AddText("x392 y" (yPos + 12) " w60 h28 Center +0x200 Background191922", "Hide"), yPos + 12)
hideBtn.OnEvent("Click", (*) => settingsGui.Hide())
RegisterButtonHover(hideBtn, "191922", "242432")

settingsGui.OnEvent("Close", (*) => (settingsGui.Hide(), 1))
settingsGui.OnEvent("Escape", (*) => settingsGui.Hide())

; ==============================================================================
; 4. CAR HEAD-UNIT OPAQUE POP-UP HUD (SHOWN WHEN MAIN GUI IS NOT ACTIVE)
; ==============================================================================
osdVisible := false
osdGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 +E0x08000000", "VMHeadUnitOSD")
osdGui.BackColor := "0D0D11"
osdGui.MarginX := 0
osdGui.MarginY := 0
ApplySleekWindowTheme(osdGui, true)

osdAccent := osdGui.AddProgress("x0 y0 w390 h3 Background0D0D11 c38BDF8", 100)

osdGui.SetFont("s11 Bold cF4F4F5", "Segoe UI")
osdChannelText := osdGui.AddText("x16 y11 w256 h22 Background0D0D11", "")
osdGui.SetFont("s11 Bold c38BDF8", "Segoe UI")
osdGainText := osdGui.AddText("x274 y11 w100 h22 Right Background0D0D11", "")

osdGui.SetFont("s9 Bold cA1A1AA", "Segoe UI")
osdFxLabelText := osdGui.AddText("x16 y37 w268 h18 Background0D0D11", "")
osdGui.SetFont("s9 Bold cF4F4F5", "Segoe UI")
osdFxValText := osdGui.AddText("x286 y37 w88 h18 Right Background0D0D11", "")

osdMeter := osdGui.AddProgress("x16 y62 w358 h7 Range0-100 Background1E1E28 c38BDF8", 50)

ShowHeadUnitOsd(mode := "volume") {
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
    } else if (activeTargets.Length = 0) {
        osdChannelText.Value := "No Target Selected"
        osdGainText.Value    := "--"
        osdFxLabelText.Value := "Open Control Panel to pick a strip"
        osdFxValText.Value   := ""
        osdMeter.Value       := 0
    } else {
        primary := activeTargets[1]
        chanTitle := nameMap.Has(primary) ? nameMap[primary] : primary
        if (activeTargets.Length > 1)
            chanTitle .= "  +" (activeTargets.Length - 1) " linked"

        val := vm.gains.Has(primary) ? Round(vm.gains[primary].current, 1) : 0.0
        if (Abs(val) < 0.05)
            val := 0.0

        anyMuted := false
        for p in activeTargets {
            if (vm.mutes.Has(p) && vm.mutes[p])
                anyMuted := true
        }

        osdChannelText.Value := chanTitle
        if anyMuted {
            osdGainText.SetFont("s11 Bold cF87171")
            osdGainText.Value := "MUTED"
            osdAccent.Opt("cF87171")
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

            osdFxLabelText.SetFont(mode = "fx" ? "s9 Bold c38BDF8" : "s9 Bold cA1A1AA")
            osdFxLabelText.Value := "FX  " Chr(0x25C2) "  " fxObj.label "  " Chr(0x25B8)
            osdFxValText.Value   := fxValStr

            if (mode = "fx") {
                pct := Round(((fxVal - fxObj.min) / (fxObj.max - fxObj.min)) * 100)
                osdMeter.Opt("c38BDF8")
                osdMeter.Value := Max(0, Min(100, pct))
            } else {
                pct := Round(((val + 60.0) / 72.0) * 100)
                osdMeter.Opt(anyMuted ? "cF87171" : "c38BDF8")
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
        osdGui.Show("x" xPos " y" yPos " w" osdW " h" osdH " NoActivate")
        osdVisible := true
    }

    SetTimer(HideHeadUnitOsd, -1500)
}

HideHeadUnitOsd() {
    global osdVisible
    osdGui.Hide()
    osdVisible := false
}

; ==============================================================================
; 5. FEATURES GUIDE GUI
; ==============================================================================
featGui := ""

CloseFeaturesGui(*) {
    global featGui
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
    chPrev   := FormatHotkeyHuman(keybinds["chanPrev"])
    chNext   := FormatHotkeyHuman(keybinds["chanNext"])
    fxPrev   := FormatHotkeyHuman(keybinds["fxPrev"])
    fxNext   := FormatHotkeyHuman(keybinds["fxNext"])
    fxUp     := FormatHotkeyHuman(keybinds["fxUp"])
    fxDown   := FormatHotkeyHuman(keybinds["fxDown"])
    fxFUp    := FormatHotkeyHuman(keybinds["fxFineUp"])
    fxFDn    := FormatHotkeyHuman(keybinds["fxFineDown"])
    fxRst    := FormatHotkeyHuman(keybinds["fxReset"])

    boundSummary := ""
    for ch in allChannels {
        hk := keybinds["target_" ch.param]
        if (hk != "")
            boundSummary .= (boundSummary != "" ? ", " : "") nameMap[ch.param] " (" FormatHotkeyHuman(hk) ")"
    }
    if (boundSummary = "")
        boundSummary := "None bound yet"

    guideText := (
        "1. HARDWARE VOLUME WHEEL & SMOOTH GLIDE ENGINE`r`n"
        . "• Intercepts your keyboard/mouse Volume Up, Volume Down, and Volume Mute keys before Windows sees them (preventing Windows master volume changes and the OS volume popup).`r`n"
        . "• Exponential Scroll Acceleration: Slow, single-notch clicks trim by 0.2 dB; fast spins accelerate smoothly up to 4.5 dB per notch.`r`n"
        . "• 20 ms Smooth Glide Interpolation: Eases fader travel cleanly with instant direction-reversal braking and anti-bounce tracking.`r`n`r`n"
        . "2. TARGET MODES, CHANNEL CYCLING & GROUP LINKING`r`n"
        . "• Cycle Solo Target Channels: " chPrev " / " chNext " steps through all 16 inputs and outputs in Single-Target Mode.`r`n"
        . "• Single-Target Mode: Click any Virtual Input (VAIO, AUX, VAIO3), Hardware Input (1–5), or Output Bus (A1–A5, B1–B3) to focus your volume wheel exclusively on that channel.`r`n"
        . "• Multi-Target Group Mode: Click the top-right mode pill to toggle Multi-Group Mode and link multiple channels together with Spread-Locked Clamping (-60.0 to +12.0 dB).`r`n`r`n"
        . "3. SOLO FX NAVIGATION (SINGLE-TARGET MODE)`r`n"
        . "• Cycle Effects: " fxPrev " / " fxNext "`r`n"
        . "• Adjust Value: " fxUp " / " fxDown "  (Fine Step: " fxFUp " / " fxFDn ")`r`n"
        . "• Reset Selected Effect to 0.0: " fxRst "`r`n"
        . "• Hardware Inputs (1–5): Comp. → Gate → Denoiser → Reverb → Delay → FX1 Send → FX2 Send.`r`n"
        . "• Virtual Inputs (VAIO / AUX / VAIO3): EQ Treble → EQ Mid → EQ Bass (-12.0 dB to +12.0 dB).`r`n"
        . "• Output Buses (A1–B3): Reverb Return → Delay Return → FX1 Return → FX2 Return.`r`n`r`n"
        . "4. CAR HEAD-UNIT POP-UP HUD`r`n"
        . "• Automatically pops up an opaque, click-through dark HUD at the bottom-center of your screen whenever the Control Panel isn't the active foreground window.`r`n"
        . "• Displays the active channel name, live dB / MUTED badge, selected Solo FX carousel, and a real-time level bar (auto-hides 1.5s after stopping).`r`n`r`n"
        . "5. GUI CONTROLS, HOVER-SCROLLING & RENAMING`r`n"
        . "• Hover-Scroll Any Row: Point your cursor over any channel pill inside the Control Panel and roll your mouse wheel (±1.0 dB, or Shift + Wheel for ±0.2 dB) to adjust that fader without changing your hardware wheel target.`r`n"
        . "• Custom Channel Labels: Click " Chr(0x270E) " (or right-click) on any Hardware Input or Output Bus to give it a custom name saved to volume_settings.ini.`r`n"
        . "• Per-Channel 0dB Pills: Click 0dB next to any strip or bus for an instant unity gain reset.`r`n`r`n"
        . "6. CUSTOM CHANNEL KEYBINDS, TRAY MENU & RELIABILITY`r`n"
        . "• Full 16-Channel Keybinds (Keybinds): Bind any Virtual Input, Hardware Input, or Output Bus—plus channel cycling and Solo FX controls—to any multi-key combination.`r`n"
        . "• Currently Bound Channels: " boundSummary ".`r`n"
        . "• Toggle Control Panel: " tKey " (or left-click the tray icon; right-click for the Quick Target submenu).`r`n"
        . "• Visual Mute Alert: Muting turns the top telemetry accent bar coral-red and switches the tray icon to a red mute badge.`r`n"
        . "• Restart Engine & Auto-Watchdog: One-click ASIO/driver engine restart plus automatic reconnection if VoiceMeeter Potato closes and reopens."
    )

    featGui := Gui("+AlwaysOnTop -MaximizeBox", "VoiceMeeter Potato Massah — Features & Guide")
    featGui.MarginX := 16
    featGui.MarginY := 14
    featGui.BackColor := "0D0D11"
    ApplySleekWindowTheme(featGui, false)

    featGui.AddProgress("x16 y12 w470 h2 Background0D0D11 c38BDF8", 100)
    featGui.SetFont("s11 Bold cF4F4F5", "Segoe UI")
    featGui.AddText("x16 y20 w470 h22 Background0D0D11", "Complete Feature & Shortcut Reference")

    featGui.SetFont("s9 Norm c38BDF8", "Segoe UI")
    featGui.AddText("x16 y42 w470 h18 Background0D0D11", "All settings, labels, and custom keybinds save automatically to volume_settings.ini")

    featGui.SetFont("s9 Norm cE4E4E7", "Segoe UI")
    featEdit := featGui.AddEdit("x16 y68 w470 h340 ReadOnly -WantReturn +VScroll Background15151C cE4E4E7", guideText)
    try DllCall("uxtheme\SetWindowTheme", "Ptr", featEdit.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)

    featGui.SetFont("s9 Bold cF4F4F5", "Segoe UI")
    closeFeatBtn := featGui.AddText("x396 y418 w90 h28 Center +0x200 Background191922", "Close")
    closeFeatBtn.OnEvent("Click", CloseFeaturesGui)
    RegisterButtonHover(closeFeatBtn, "191922", "242432")

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

RegisterAllHotkeys() {
    for oldHk in registeredHotkeys {
        try Hotkey(oldHk, "Off")
    }
    registeredHotkeys.Clear()

    for item in hotkeyDefs {
        hk := keybinds[item.id]
        if (hk != "") {
            try {
                Hotkey(hk, item.fn, "On")
                registeredHotkeys[hk] := item.id
            }
        }
    }
    RefreshShortcutLabels()
}

RefreshShortcutLabels() {
    tKey := FormatHotkeyHuman(keybinds["toggleGui"])
    boundCount := 0
    for ch in allChannels {
        if (keybinds["target_" ch.param] != "")
            boundCount += 1
    }
    footerHintText.Value := tKey ": Panel`n" boundCount " channel shortcut" (boundCount = 1 ? "" : "s") " active"

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
    A_TrayMenu.Add("Features & Guide...", (*) => OpenFeaturesGui())
    A_TrayMenu.Add("Configure Keybinds...", (*) => OpenKeybindGui())
    A_TrayMenu.Add("Restart Audio Engine", (*) => RestartAudioEngine())
    A_TrayMenu.Add("Reload Script", (*) => Reload())
    A_TrayMenu.Add("Exit", (*) => ExitApp())
    A_TrayMenu.Default := "Open Control Panel (" tKey ")"
    A_TrayMenu.ClickCount := 1
}

CloseKeybindGui(*) {
    global kbGui, activeInputHook
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

    targetGui.SetFont("s9 Norm cE4E4E7", "Segoe UI")
    lblCtrl := targetGui.AddText("x" xBase " y" yPos " w154 h25 +0x200 Background0D0D11", displayLabel)
    kbLabelMap[item.id] := lblCtrl

    targetGui.SetFont("s8 Bold c" (isBound ? "38BDF8" : "71717A"), "Segoe UI")
    bindBtn := targetGui.AddText("x" (xBase + 158) " y" yPos " w132 h25 Center +0x200 Background" (isBound ? "152433" : "16161E"), FormatHotkeyHuman(hkVal))
    bindBtn.OnEvent("Click", CaptureHotkeyForAction.Bind(item.id))
    kbBtnMap[item.id] := bindBtn
    hoverStyleMap[bindBtn.Hwnd] := {
        key: "kb_" item.id,
        ctrls: [bindBtn],
        getBg: (*) => (keybinds[item.id] != "") ? "152433" : "16161E",
        hoverBg: (*) => (keybinds[item.id] != "") ? "1C3247" : "20202C"
    }

    targetGui.SetFont("s8 Bold cA1A1AA", "Segoe UI")
    clrBtn := targetGui.AddText("x" (xBase + 294) " y" yPos " w26 h25 Center +0x200 Background191922", Chr(0x2715))
    clrBtn.OnEvent("Click", ClearSingleHotkey.Bind(item.id))
    RegisterButtonHover(clrBtn, "191922", "2A1A20")
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
    kbGui.AddText("x16 y20 w664 h22 Background0D0D11", "Keyboard Shortcuts (All Inputs, Outputs & FX)")
    kbGui.SetFont("s9 Norm c38BDF8", "Segoe UI")
    kbStatusLabel := kbGui.AddText("x16 y42 w664 h18 Background0D0D11", "Click any shortcut pill, then press your desired key combination.")

    ; Left Column: General & Solo FX + Virtual Inputs
    yLeft := 70
    kbGui.SetFont("s8 Bold c71717A", "Segoe UI")
    kbGui.AddText("x16 y" yLeft " w320 h16 Background0D0D11", "GENERAL, NAVIGATION & SOLO FX")
    yLeft += 20

    for item in hotkeyDefs {
        if (item.group = "general") {
            AddKeybindRow(kbGui, item, 16, yLeft)
            yLeft += 29
        }
    }

    yLeft += 10
    kbGui.SetFont("s8 Bold c71717A", "Segoe UI")
    kbGui.AddText("x16 y" yLeft " w320 h16 Background0D0D11", "VIRTUAL INPUTS")
    yLeft += 20

    for item in hotkeyDefs {
        if (item.group = "virtual") {
            AddKeybindRow(kbGui, item, 16, yLeft)
            yLeft += 29
        }
    }

    ; Right Column: Hardware Inputs + Output Buses
    yRight := 70
    kbGui.SetFont("s8 Bold c71717A", "Segoe UI")
    kbGui.AddText("x360 y" yRight " w320 h16 Background0D0D11", "HARDWARE INPUTS")
    yRight += 20

    for item in hotkeyDefs {
        if (item.group = "hardware") {
            AddKeybindRow(kbGui, item, 360, yRight)
            yRight += 29
        }
    }

    yRight += 10
    kbGui.SetFont("s8 Bold c71717A", "Segoe UI")
    kbGui.AddText("x360 y" yRight " w320 h16 Background0D0D11", "OUTPUT BUSES")
    yRight += 20

    for item in hotkeyDefs {
        if (item.group = "bus") {
            AddKeybindRow(kbGui, item, 360, yRight)
            yRight += 29
        }
    }

    yBottom := Max(yLeft, yRight) + 12
    kbGui.AddText("x16 y" (yBottom - 6) " w664 h1 Background22222E", "")

    kbGui.SetFont("s8 Bold cD4D4D8", "Segoe UI")
    defBtn := kbGui.AddText("x16 y" yBottom " w130 h28 Center +0x200 Background191922", "Reset Defaults")
    defBtn.OnEvent("Click", ResetDefaultHotkeys)
    RegisterButtonHover(defBtn, "191922", "242432")

    clrAllChBtn := kbGui.AddText("x154 y" yBottom " w164 h28 Center +0x200 Background191922", "Unbind All Channels")
    clrAllChBtn.OnEvent("Click", ClearAllChannelHotkeys)
    RegisterButtonHover(clrAllChBtn, "191922", "242432")

    kbGui.SetFont("s8 Bold c38BDF8", "Segoe UI")
    doneBtn := kbGui.AddText("x590 y" yBottom " w90 h28 Center +0x200 Background152433", "Done")
    doneBtn.OnEvent("Click", CloseKeybindGui)
    RegisterButtonHover(doneBtn, "152433", "1C3247")

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
; 7. HARDWARE VOLUME WHEEL, SOLO CHANNEL & FX NAVIGATION, HOVER-SCROLLING
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
        if (cx >= zone.x1 && cx <= zone.x2 && cy >= (zone.baseY1 + currentDeltaY) && cy <= (zone.baseY2 + currentDeltaY))
            return zone.param
    }
    return ""
}

HoverWheelStep(dir, stepSize) {
    Critical
    param := GetHoveredChannel()
    if (param = "" || !vm.connected)
        return

    if (IsTargetActive(param) && vm.gains.Has(param)) {
        cur := vm.gains[param].target
        newGain := Round(Max(-60.0, Min(12.0, cur + (dir * stepSize))), 1)
        vm.gains[param].current := newGain
        vm.gains[param].target  := newGain
        DllCall(pSetFloat, "AStr", param ".Gain", "Float", newGain)
        vm.lastWriteTick := A_TickCount
        UpdateStatusBanner()
    } else {
        if (!hoverCache.Has(param) || (A_TickCount - hoverCache[param].tick > 300)) {
            DllCall(pIsDirty)
            liveGain := 0.0
            DllCall(pGetFloat, "AStr", param ".Gain", "Float*", &liveGain, "Int")
            cur := liveGain
        } else {
            cur := hoverCache[param].gain
        }

        newGain := Round(Max(-60.0, Min(12.0, cur + (dir * stepSize))), 1)
        hoverCache[param] := { gain: newGain, tick: A_TickCount }
        DllCall(pSetFloat, "AStr", param ".Gain", "Float", newGain)
        vm.lastWriteTick := A_TickCount
        SetTimer(FlushOwnDirtyFlag, -350)
    }

    disp := (Abs(newGain) < 0.05) ? 0.0 : newGain
    ShowQuickTip(nameMap[param] ":  " (disp > 0 ? "+" : "") Format("{:.1f} dB", disp), 900)
}

; ==============================================================================
; 8. GUI, PRESETS & ENGINE ACTIONS
; ==============================================================================
RefreshModePillVisual() {
    if (exclusiveMode = 1) {
        modePill.SetFont("s8 Bold c38BDF8")
        modePill.Opt("Background1B2B3A")
        modePill.Value := "◉  Single-Target Mode"
    } else {
        modePill.SetFont("s8 Bold cA1A1AA")
        modePill.Opt("Background22222E")
        modePill.Value := "◎  Multi-Group Mode"
    }
}

RefreshChannelVisuals() {
    global lastHoverKey := ""
    for param, vis in rowVisualMap {
        active := IsTargetActive(param)
        bgHex  := active ? "152433" : "16161E"

        vis.bg.Opt("Background" bgHex)
        vis.dot.Opt("Background" bgHex)
        vis.dot.SetFont("s9 Bold c" (active ? "38BDF8" : "52525B"))
        vis.dot.Value := active ? "●" : "○"

        vis.lbl.Opt("Background" bgHex)
        vis.lbl.SetFont("s9 " (active ? "Bold cF4F4F5" : "Norm cD4D4D8"))
        vis.lbl.Value := nameMap[param]

        if (vis.tag != "") {
            vis.tag.Opt("Background" bgHex)
            vis.tag.SetFont("s8 Norm c" (active ? "38BDF8" : "52525B"))
        }
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
        RefreshChannelVisuals()
        UpdateStatusBanner()
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
    RefreshChannelVisuals()
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
    SyncAllActiveTargets(true)
    SyncSelectedSoloEffect(true)
    if DllCall("IsWindowVisible", "Ptr", settingsGui.Hwnd)
        UpdateStatusBanner()
}

OnModeToggle(*) {
    global exclusiveMode := (exclusiveMode = 1) ? 0 : 1
    if (exclusiveMode = 1 && activeTargets.Length > 1) {
        global activeTargets := [activeTargets[1]]
    }
    RefreshModePillVisual()
    RefreshChannelVisuals()
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
    RefreshChannelVisuals()
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

    RefreshChannelVisuals()
    if (IsGuiAlive(kbGui) && kbLabelMap.Has("target_" param))
        kbLabelMap["target_" param].Value := nameMap[param]

    RefreshShortcutLabels()
    UpdateStatusBanner()
}

ResetChannelGain(param, *) {
    Critical
    DllCall(pSetFloat, "AStr", param ".Gain", "Float", 0.0)
    vm.lastWriteTick := A_TickCount
    if hoverCache.Has(param)
        hoverCache.Delete(param)

    if vm.gains.Has(param) {
        vm.gains[param].current := 0.0
        vm.gains[param].target  := 0.0
    }

    SetTimer(FlushOwnDirtyFlag, -350)

    if DllCall("IsWindowVisible", "Ptr", settingsGui.Hwnd)
        UpdateStatusBanner()
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
    static lastLineCount := 1
    static lastMuteState := -1

    anyMuted := false

    if (!vm.connected) {
        lines     := "VoiceMeeter Potato Offline"
        subLine   := "Waiting for VoiceMeeter Potato to start..."
        lineCount := 1
    } else if (activeTargets.Length = 0) {
        lines     := "No Channel Selected"
        subLine   := "Click any Virtual Input, Hardware Input, or Bus below"
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

            lines .= (idx > 1 ? "`n" : "") "•  " label "   —   " dbStr muteTag
        }
        lineCount := activeTargets.Length

        soloParam := GetSoloTarget()
        if (soloParam != "") {
            fxObj := GetSelectedEffectObj(soloParam)
            fullParam := soloParam "." fxObj.key
            fxVal := vm.fxValues.Has(fullParam) ? vm.fxValues[fullParam].val : 0.0
            subLine := Chr(0x21B3) "  FX:  " fxObj.label "   [ " FormatEffectValue(fxObj, fxVal) " ]"
        } else {
            subLine := activeTargets.Length " channels linked   •   Spread-Locked (-60.0 to +12.0 dB)"
        }
    }

    muteFlag := anyMuted ? 1 : 0
    if (muteFlag != lastMuteState) {
        lastMuteState := muteFlag
        statusText.SetFont(anyMuted ? "s10 Bold cF87171" : "s10 Bold c38BDF8")
        heroAccent.Opt(anyMuted ? "cF87171" : "c38BDF8")
        UpdateTrayIcon(anyMuted)
    }

    statusText.Value  := lines
    heroSubText.Value := subLine

    if (lineCount != lastLineCount) {
        lastLineCount := lineCount
        newStatusH := lineCount * 20
        global currentDeltaY := newStatusH - 20
        isVisible := DllCall("IsWindowVisible", "Ptr", settingsGui.Hwnd)

        if isVisible
            SendMessage(0x000B, 0, 0, settingsGui.Hwnd)  ; WM_SETREDRAW = false

        heroBg.Move(, , 436, 74 + currentDeltaY)
        statusText.Move(, , 412, newStatusH)
        heroSubText.Move(, 62 + currentDeltaY)

        for item in movableControls
            item.ctrl.Move(, item.baseY + currentDeltaY)

        if isVisible {
            settingsGui.Show("AutoSize NoActivate")
            SendMessage(0x000B, 1, 0, settingsGui.Hwnd)  ; WM_SETREDRAW = true
            DllCall("RedrawWindow", "Ptr", settingsGui.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0585)
        }
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
; 9. WATCHDOG, SPREAD-LOCKED ACCELERATION & SMOOTH GLIDE ENGINE
; ==============================================================================
WatchdogCheck() {
    vmType := 0
    isOnline := (DllCall(pGetType, "Int*", &vmType, "Int") = 0 && vmType > 0)

    if (isOnline && !vm.connected) {
        vm.connected := true
        SetTimer(GlideStep, 0)
        vm.gliding := false
        vm.gains.Clear()
        vm.mutes.Clear()
        vm.fxValues.Clear()
        SyncAllActiveTargets(true)
        SyncSelectedSoloEffect(true)
        if DllCall("IsWindowVisible", "Ptr", settingsGui.Hwnd)
            UpdateStatusBanner()
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
        liveGain := 0.0
        if (DllCall(pGetFloat, "AStr", param ".Gain", "Float*", &liveGain, "Int") = 0)
            vm.gains[param] := { current: liveGain, target: liveGain }
        else if !vm.gains.Has(param)
            vm.gains[param] := { current: 0.0, target: 0.0 }

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
            liveGain := 0.0
            DllCall(pGetFloat, "AStr", param ".Gain", "Float*", &liveGain, "Int")
            vm.gains[param] := { current: liveGain, target: liveGain }
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

        DllCall(pSetFloat, "AStr", param ".Gain", "Float", entry.current)
        vm.lastWriteTick := A_TickCount
    }

    if DllCall("IsWindowVisible", "Ptr", settingsGui.Hwnd)
        UpdateStatusBanner()
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
    if DllCall("IsWindowVisible", "Ptr", settingsGui.Hwnd)
        UpdateStatusBanner()
    ShowHeadUnitOsd("volume")
}

; ==============================================================================
; 10. STARTUP INITIALIZATION
; ==============================================================================
Sleep(50)
vmType := 0
vm.connected := (DllCall(pGetType, "Int*", &vmType, "Int") = 0 && vmType > 0)
if vm.connected {
    SyncAllActiveTargets(true)
    SyncSelectedSoloEffect(true)
}

RegisterAllHotkeys()
RefreshModePillVisual()
RefreshChannelVisuals()
SetTimer(WatchdogCheck, 2000)
UpdateStatusBanner()
settingsGui.Show("AutoSize")