#pragma once

#include <windows.h>

// Local, no-focus command channel for deterministic shader testing.
//
// An external controller signals one per-process request event. The input
// dispatcher exposes that virtual key as down for one complete dispatch frame,
// then forces a release dispatch frame. This preserves the existing listener
// and key-section behavior instead of calling individual callbacks directly.
namespace UE4FXRemoteInput
{
    static const size_t status_message_characters = 512;

    struct RemoteInputSlot
    {
        int virtual_key;
        const wchar_t *token;
        HANDLE request_event;
        HANDLE acknowledgement_event;
    };

    static RemoteInputSlot slots[] = {
        { VK_F2,    L"F2",       NULL, NULL },
        { VK_F8,    L"F8",       NULL, NULL },
        { VK_F10,   L"F10",      NULL, NULL },
        { VK_SNAPSHOT, L"SCREENSHOT", NULL, NULL },
        { VK_PRIOR, L"PAGEUP",   NULL, NULL },
        { VK_NEXT,  L"PAGEDOWN", NULL, NULL },
        { VK_ADD,   L"CLEARHUNT", NULL, NULL },
    };

    static DWORD active_mask = 0;
    static bool release_pending = false;
    static bool initialized = false;
    static bool available = false;
    static bool status_available = false;
    static HANDLE status_request_event = NULL;
    static HANDLE status_acknowledgement_event = NULL;
    static HANDLE status_mapping = NULL;
    static wchar_t *status_message = NULL;

    inline bool EnsureInitialized()
    {
        if (initialized)
            return available;

        initialized = true;
        available = true;
        DWORD process_id = GetCurrentProcessId();

        for (size_t i = 0; i < ARRAYSIZE(slots); ++i) {
            wchar_t request_name[160] = {};
            wchar_t acknowledgement_name[160] = {};
            _snwprintf_s(request_name, ARRAYSIZE(request_name), _TRUNCATE,
                L"Local\\3DMigotoRemoteInput_%lu_%s", process_id, slots[i].token);
            _snwprintf_s(acknowledgement_name, ARRAYSIZE(acknowledgement_name), _TRUNCATE,
                L"Local\\3DMigotoRemoteInputAck_%lu_%s", process_id, slots[i].token);

            // Auto-reset events make each external request a one-shot action.
            slots[i].request_event = CreateEventW(NULL, FALSE, FALSE, request_name);
            slots[i].acknowledgement_event = CreateEventW(NULL, FALSE, FALSE, acknowledgement_name);
            if (!slots[i].request_event || !slots[i].acknowledgement_event)
                available = false;
        }

        wchar_t status_request_name[160] = {};
        wchar_t status_acknowledgement_name[160] = {};
        wchar_t status_mapping_name[160] = {};
        _snwprintf_s(status_request_name, ARRAYSIZE(status_request_name), _TRUNCATE,
            L"Local\\3DMigotoRemoteStatus_%lu", process_id);
        _snwprintf_s(status_acknowledgement_name, ARRAYSIZE(status_acknowledgement_name), _TRUNCATE,
            L"Local\\3DMigotoRemoteStatusAck_%lu", process_id);
        _snwprintf_s(status_mapping_name, ARRAYSIZE(status_mapping_name), _TRUNCATE,
            L"Local\\3DMigotoRemoteStatusBuffer_%lu", process_id);

        status_request_event = CreateEventW(NULL, FALSE, FALSE, status_request_name);
        status_acknowledgement_event = CreateEventW(NULL, FALSE, FALSE, status_acknowledgement_name);
        status_mapping = CreateFileMappingW(INVALID_HANDLE_VALUE, NULL, PAGE_READWRITE, 0,
            (DWORD)(status_message_characters * sizeof(wchar_t)), status_mapping_name);
        if (status_mapping) {
            status_message = static_cast<wchar_t *>(MapViewOfFile(status_mapping,
                FILE_MAP_ALL_ACCESS, 0, 0, status_message_characters * sizeof(wchar_t)));
        }
        status_available = status_request_event && status_acknowledgement_event && status_message;

        return available;
    }

    inline bool TryConsumeStatusMessage(wchar_t *destination, size_t destination_characters)
    {
        EnsureInitialized();
        if (!status_available || !destination || destination_characters < 2)
            return false;
        if (WaitForSingleObject(status_request_event, 0) != WAIT_OBJECT_0)
            return false;

        size_t i = 0;
        for (; i + 1 < destination_characters && i + 1 < status_message_characters; ++i) {
            destination[i] = status_message[i];
            if (!destination[i])
                break;
        }
        destination[destination_characters - 1] = L'\0';
        status_message[0] = L'\0';
        SetEvent(status_acknowledgement_event);
        return destination[0] != L'\0';
    }

    inline bool BeginDispatchFrame()
    {
        if (!EnsureInitialized())
            return false;

        // A release frame is mandatory even while the game is in the
        // background. New requests remain signaled until the following frame.
        if (release_pending) {
            active_mask = 0;
            release_pending = false;
            return true;
        }

        active_mask = 0;
        for (size_t i = 0; i < ARRAYSIZE(slots); ++i) {
            if (WaitForSingleObject(slots[i].request_event, 0) == WAIT_OBJECT_0)
                active_mask |= (1u << i);
        }

        if (active_mask) {
            release_pending = true;
            return true;
        }
        return false;
    }

    inline bool IsModifier(int virtual_key)
    {
        switch (virtual_key) {
        case VK_CONTROL:
        case VK_LCONTROL:
        case VK_RCONTROL:
        case VK_MENU:
        case VK_LMENU:
        case VK_RMENU:
        case VK_SHIFT:
        case VK_LSHIFT:
        case VK_RSHIFT:
        case VK_LWIN:
        case VK_RWIN:
            return true;
        default:
            return false;
        }
    }

    inline SHORT CheckVirtualKeyState(int virtual_key)
    {
        if (active_mask) {
            // Remote actions represent an unmodified key press regardless of
            // what the user is doing in the foreground application.
            if (IsModifier(virtual_key))
                return 0;

            for (size_t i = 0; i < ARRAYSIZE(slots); ++i) {
                if ((active_mask & (1u << i)) && slots[i].virtual_key == virtual_key)
                    return (SHORT)0x8000;
            }
        }

        return ::GetAsyncKeyState(virtual_key);
    }

    inline void EndDispatchFrame()
    {
        if (!active_mask)
            return;

        for (size_t i = 0; i < ARRAYSIZE(slots); ++i) {
            if (active_mask & (1u << i))
                SetEvent(slots[i].acknowledgement_event);
        }
        active_mask = 0;
    }
}


