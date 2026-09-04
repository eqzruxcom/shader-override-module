#Requires AutoHotkey v2.0
#SingleInstance Off

; External FF7 Remake shader-test input controller.
; Sends exactly one whitelisted command to exactly one ff7remake_.exe process,
; records a machine-readable receipt, and exits.

SetTitleMatchMode(2)

global AllowedCommands := Map(
    "focus",    Map("label", "Focus FF7 window only",      "vk", 0,    "token", "", "focusOnly", true),
    "screenshot", Map("label", "ShadowPlay screenshot",     "vk", 0,    "token", "SCREENSHOT", "sendSequence", "!{F1}", "preSendDelay", 2000),
    "f2",       Map("label", "F2 test toggle",            "vk", 0x71, "token", "F2"),
    "reload",   Map("label", "F10 native shader reload",  "vk", 0x79, "token", "F10"),
    "frameanalysis", Map("label", "F8 log-only frame analysis", "vk", 0x77, "token", "F8"),
    "enter",    Map("label", "Enter menu navigation",      "vk", 0x0D, "token", "ENTER"),
    "pageup",   Map("label", "Page Up active experiment", "vk", 0x21, "token", "PAGEUP"),
    "pagedown", Map("label", "Page Down accepted master", "vk", 0x22, "token", "PAGEDOWN"),
    "clearhunt", Map("label", "Clear all shader-hunting selections", "vk", 0x6B, "token", "CLEARHUNT")
)

JsonEscape(value) {
    slash := Chr(92)
    quote := Chr(34)
    value := StrReplace(value, slash, slash slash)
    value := StrReplace(value, quote, slash quote)
    value := StrReplace(value, "`r", slash "r")
    value := StrReplace(value, "`n", slash "n")
    return value
}

WriteReceipt(path, status, command, label, message, method := "none", acknowledged := false, hwnd := 0, pid := 0, processPath := "", warningDelayMilliseconds := 5000) {
    stamp := FormatTime(A_NowUTC, "yyyy-MM-dd'T'HH:mm:ss'Z'")
    json := '{'
        . '"timestampUtc":"' JsonEscape(stamp) '",'
        . '"status":"' JsonEscape(status) '",'
        . '"command":"' JsonEscape(command) '",'
        . '"label":"' JsonEscape(label) '",'
        . '"message":"' JsonEscape(message) '",'
        . '"method":"' JsonEscape(method) '",'
        . '"warningDelayMilliseconds":' warningDelayMilliseconds ','
        . '"acknowledged":' (acknowledged ? "true" : "false") ','
        . '"windowHandle":' hwnd ','
        . '"processId":' pid ','
        . '"processPath":"' JsonEscape(processPath) '"'
        . '}'

    if (path != "") {
        SplitPath(path, , &directory)
        if (directory != "" && !DirExist(directory))
            DirCreate(directory)
        if FileExist(path)
            FileDelete(path)
        FileAppend(json "`n", path, "UTF-8")
    }
    FileAppend(json "`n", "*")
}

Fail(exitCode, receiptPath, command, label, message, method := "none", hwnd := 0, pid := 0, processPath := "") {
    WriteReceipt(receiptPath, "error", command, label, message, method, false, hwnd, pid, processPath)
    ExitApp(exitCode)
}

SendPolledVirtualKey(vk, holdMilliseconds := 250) {
    scanCode := DllCall("MapVirtualKey", "UInt", vk, "UInt", 0, "UInt")
    DllCall("keybd_event", "UChar", vk, "UChar", scanCode, "UInt", 0, "UPtr", 0)
    Sleep(holdMilliseconds)
    DllCall("keybd_event", "UChar", vk, "UChar", scanCode, "UInt", 0x0002, "UPtr", 0)
}

OpenRemoteEvents(pid, token, &requestEvent, &acknowledgementEvent) {
    requestName := "Local\3DMigotoRemoteInput_" pid "_" token
    acknowledgementName := "Local\3DMigotoRemoteInputAck_" pid "_" token
    requestEvent := DllCall("OpenEventW", "UInt", 0x0002, "Int", false, "Str", requestName, "Ptr")
    acknowledgementEvent := DllCall("OpenEventW", "UInt", 0x00100002, "Int", false, "Str", acknowledgementName, "Ptr")
    if (!requestEvent || !acknowledgementEvent) {
        if requestEvent
            DllCall("CloseHandle", "Ptr", requestEvent)
        if acknowledgementEvent
            DllCall("CloseHandle", "Ptr", acknowledgementEvent)
        requestEvent := 0
        acknowledgementEvent := 0
        return false
    }
    return true
}

command := ""
receiptPath := ""
dryRun := false
requireIpc := false
skipWarning := false
expectedExe := "ff7remake_.exe"
activateTimeoutSeconds := 2
warningDelayMilliseconds := 5000

i := 1
while (i <= A_Args.Length) {
    arg := StrLower(A_Args[i])
    switch arg {
        case "--dry-run":
            dryRun := true
        case "--require-ipc":
            requireIpc := true
        case "--skip-warning":
            skipWarning := true
        case "--receipt":
            i += 1
            if (i > A_Args.Length)
                Fail(2, receiptPath, command, "", "--receipt requires a path")
            receiptPath := A_Args[i]
        case "--expected-exe":
            i += 1
            if (i > A_Args.Length)
                Fail(2, receiptPath, command, "", "--expected-exe requires a filename")
            expectedExe := A_Args[i]
        case "--self-test":
            WriteReceipt(receiptPath, "self-test-pass", "self-test", "No input sent", "Parser and whitelist loaded", "none", false, 0, 0, "", 0)
            ExitApp(0)
        default:
            if (command != "")
                Fail(2, receiptPath, command, "", "Only one command is allowed per invocation")
            command := arg
    }
    i += 1
}

if (command = "")
    Fail(2, receiptPath, command, "", "Missing command: focus, screenshot, f2, reload, frameanalysis, enter, pageup, pagedown, or clearhunt")
if !AllowedCommands.Has(command)
    Fail(2, receiptPath, command, "", "Command is not whitelisted")

entry := AllowedCommands[command]
selector := "ahk_exe " expectedExe
windows := WinGetList(selector)
if (windows.Length != 1)
    Fail(3, receiptPath, command, entry["label"], "Expected exactly one FF7 window; found " windows.Length)

hwnd := windows[1]
pid := WinGetPID("ahk_id " hwnd)
processPath := ProcessGetPath(pid)
processName := ""
SplitPath(processPath, &processName)
if (StrLower(processName) != StrLower(expectedExe))
    Fail(3, receiptPath, command, entry["label"], "Resolved process filename did not match expected executable", "none", hwnd, pid, processPath)

focusOnly := entry.Has("focusOnly") && entry["focusOnly"]
if focusOnly {
    if requireIpc
        Fail(5, receiptPath, command, entry["label"], "Focus-only control does not use engine IPC", "foreground-focus-only", hwnd, pid, processPath)

    if dryRun {
        WriteReceipt(receiptPath, "dry-run-pass", command, entry["label"], "Exact target verified; no focus or input sent", "foreground-focus-only", false, hwnd, pid, processPath, 0)
        ExitApp(0)
    }

    actualWarningDelayMilliseconds := skipWarning ? 0 : warningDelayMilliseconds
    if (actualWarningDelayMilliseconds > 0) {
        TrayTip("Focusing FF7 in 5 seconds; no key will be sent", "FF7 Shader Test", 1)
        Sleep(actualWarningDelayMilliseconds)
    }

    WinActivate("ahk_id " hwnd)
    if !WinWaitActive("ahk_id " hwnd, , activateTimeoutSeconds)
        Fail(4, receiptPath, command, entry["label"], "FF7 window did not become active", "foreground-focus-only", hwnd, pid, processPath)

    WriteReceipt(receiptPath, "sent", command, entry["label"], "FF7 window activated; no key input sent", "foreground-focus-only", false, hwnd, pid, processPath, actualWarningDelayMilliseconds)
    ExitApp(0)
}

requestEvent := 0
acknowledgementEvent := 0
ipcAvailable := OpenRemoteEvents(pid, entry["token"], &requestEvent, &acknowledgementEvent)
method := ipcAvailable ? "engine-ipc" : "foreground-virtual-key"

if (requireIpc && !ipcAvailable)
    Fail(5, receiptPath, command, entry["label"], "Modified 3Dmigoto remote-input events are not available", method, hwnd, pid, processPath)

if dryRun {
    if requestEvent
        DllCall("CloseHandle", "Ptr", requestEvent)
    if acknowledgementEvent
        DllCall("CloseHandle", "Ptr", acknowledgementEvent)
    WriteReceipt(receiptPath, "dry-run-pass", command, entry["label"], "Target and delivery method verified; no input sent", method, false, hwnd, pid, processPath, 0)
    ExitApp(0)
}

actualWarningDelayMilliseconds := skipWarning ? 0 : warningDelayMilliseconds
if (actualWarningDelayMilliseconds > 0) {
    TrayTip("Sending " entry["label"] " in 5 seconds", "FF7 Shader Test", 1)
    Sleep(actualWarningDelayMilliseconds)
}

if ipcAvailable {
    DllCall("ResetEvent", "Ptr", acknowledgementEvent)
    if !DllCall("SetEvent", "Ptr", requestEvent)
        Fail(6, receiptPath, command, entry["label"], "Could not signal the 3Dmigoto request event", method, hwnd, pid, processPath)

    waitResult := DllCall("WaitForSingleObject", "Ptr", acknowledgementEvent, "UInt", 3000, "UInt")
    DllCall("CloseHandle", "Ptr", requestEvent)
    DllCall("CloseHandle", "Ptr", acknowledgementEvent)
    if (waitResult != 0)
        Fail(7, receiptPath, command, entry["label"], "3Dmigoto did not acknowledge the command within 3 seconds", method, hwnd, pid, processPath)

    WriteReceipt(receiptPath, "sent", command, entry["label"], "3Dmigoto consumed one background command", method, true, hwnd, pid, processPath, actualWarningDelayMilliseconds)
    ExitApp(0)
}

WinActivate("ahk_id " hwnd)
if !WinWaitActive("ahk_id " hwnd, , activateTimeoutSeconds)
    Fail(4, receiptPath, command, entry["label"], "FF7 window did not become active", method, hwnd, pid, processPath)

if entry.Has("preSendDelay")
    Sleep(entry["preSendDelay"])

if entry.Has("sendSequence")
    Send(entry["sendSequence"])
else
    SendPolledVirtualKey(entry["vk"])

Sleep(100)
WriteReceipt(receiptPath, "sent", command, entry["label"], "One foreground command sent", method, false, hwnd, pid, processPath, actualWarningDelayMilliseconds)
ExitApp(0)
