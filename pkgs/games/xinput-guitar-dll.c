/* XInput 1.3 shim presenting one DirectInput guitar as an XInput guitar.
 *
 * The button and axis layout is not hardcoded: GUITAR_SHIM_CONFIG carries one
 * line per guitar, generated from modules/software/guitars profiles. Wine's
 * hidraw backend passes a device's own HID report descriptor through to dinput,
 * so DirectInput numbers buttons by HID declaration order -- which is why these
 * indices differ per guitar and cannot be derived from an SDL mapping.
 *
 * Every enumerated device is logged to C:\gh-xinput-guitar.log with its IDs and
 * capabilities, so an unrecognised guitar can be identified from one launch.
 * Set GUITAR_SHIM_TRACE=1 to also log each input change.
 */
#define COBJMACROS
#include <windows.h>
#include <dinput.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    WORD wButtons;
    BYTE bLeftTrigger;
    BYTE bRightTrigger;
    SHORT sThumbLX;
    SHORT sThumbLY;
    SHORT sThumbRX;
    SHORT sThumbRY;
} XINPUT_GAMEPAD_LOCAL;

typedef struct {
    DWORD dwPacketNumber;
    XINPUT_GAMEPAD_LOCAL Gamepad;
} XINPUT_STATE_LOCAL;

typedef struct {
    BYTE Type;
    BYTE SubType;
    WORD Flags;
    XINPUT_GAMEPAD_LOCAL Gamepad;
    struct {
        WORD wLeftMotorSpeed;
        WORD wRightMotorSpeed;
    } Vibration;
} XINPUT_CAPABILITIES_LOCAL;

typedef struct {
    WORD wLeftMotorSpeed;
    WORD wRightMotorSpeed;
} XINPUT_VIBRATION_LOCAL;

#define MAX_BINDINGS 32
#define MAX_INDICES 4
#define NAME_MAX 24

enum binding_kind { BIND_BUTTON, BIND_POV, BIND_AXIS };

typedef struct {
    char control[NAME_MAX];
    int kind;
    int indices[MAX_INDICES];
    int count;
    int axis_offset;
    LONG axis_min;
    LONG axis_max;
} binding;

/* Applied when GUITAR_SHIM_CONFIG is absent, so a launch outside the Nix
 * launchers still behaves as this DLL did before it read profiles. */
static const char DEFAULT_CONFIG[] =
    "*:* a=b0 b=b1 x=b2 y=b3 leftshoulder=b4 back=b6 start=b7,b11 "
    "dpup=p0 dpdown=p0 rightx=lX:0:65535\n";

static const struct { const char *name; WORD mask; } BUTTON_TARGETS[] = {
    { "a", 0x1000 }, { "b", 0x2000 }, { "x", 0x4000 }, { "y", 0x8000 },
    { "leftshoulder", 0x0100 }, { "rightshoulder", 0x0200 },
    { "back", 0x0020 }, { "start", 0x0010 },
    { "leftstick", 0x0040 }, { "rightstick", 0x0080 }, { "guide", 0x0400 },
    { "dpup", 0x0001 }, { "dpdown", 0x0002 }, { "dpleft", 0x0004 }, { "dpright", 0x0008 },
};

static const struct { const char *name; int offset; } AXIS_SOURCES[] = {
    { "lX", FIELD_OFFSET(DIJOYSTATE2, lX) },
    { "lY", FIELD_OFFSET(DIJOYSTATE2, lY) },
    { "lZ", FIELD_OFFSET(DIJOYSTATE2, lZ) },
    { "lRx", FIELD_OFFSET(DIJOYSTATE2, lRx) },
    { "lRy", FIELD_OFFSET(DIJOYSTATE2, lRy) },
    { "lRz", FIELD_OFFSET(DIJOYSTATE2, lRz) },
    { "rglSlider[0]", FIELD_OFFSET(DIJOYSTATE2, rglSlider[0]) },
    { "rglSlider[1]", FIELD_OFFSET(DIJOYSTATE2, rglSlider[1]) },
};

static IDirectInput8A *di;
static IDirectInputDevice8A *device;
static DWORD packet;
static BOOL init_done;
static BOOL tracing;
static HANDLE trace_file = INVALID_HANDLE_VALUE;
static binding bindings[MAX_BINDINGS];
static int binding_count;
static DIJOYSTATE2 previous;
static BOOL have_previous;

static void trace_line(const char *line)
{
    DWORD written;

    /* Held open: trace mode writes on every input change. */
    if (trace_file == INVALID_HANDLE_VALUE)
    {
        trace_file = CreateFileA("C:\\gh-xinput-guitar.log", FILE_APPEND_DATA,
                                 FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_ALWAYS,
                                 FILE_ATTRIBUTE_NORMAL, NULL);
        if (trace_file == INVALID_HANDLE_VALUE) return;
    }
    WriteFile(trace_file, line, lstrlenA(line), &written, NULL);
}

static void trace_format(const char *format, ...)
{
    /* wvsprintfA takes no destination size and caps its output at 1024. */
    char line[1024];
    va_list args;

    va_start(args, format);
    wvsprintfA(line, format, args);
    va_end(args);
    trace_line(line);
}

static WORD button_mask(const char *control)
{
    size_t i;

    for (i = 0; i < sizeof(BUTTON_TARGETS) / sizeof(BUTTON_TARGETS[0]); i++)
        if (!lstrcmpA(control, BUTTON_TARGETS[i].name)) return BUTTON_TARGETS[i].mask;
    return 0;
}

static int axis_offset(const char *name)
{
    size_t i;

    for (i = 0; i < sizeof(AXIS_SOURCES) / sizeof(AXIS_SOURCES[0]); i++)
        if (!lstrcmpA(name, AXIS_SOURCES[i].name)) return AXIS_SOURCES[i].offset;
    return -1;
}

static const char *next_token(const char *cursor, const char *end, char *out, size_t size)
{
    size_t length = 0;

    while (cursor < end && (*cursor == ' ' || *cursor == '\t' || *cursor == '\r')) cursor++;
    while (cursor < end && *cursor != ' ' && *cursor != '\t' && *cursor != '\r')
    {
        if (length + 1 < size) out[length++] = *cursor;
        cursor++;
    }
    out[length] = 0;
    return length ? cursor : NULL;
}

static BOOL device_matches(const char *token, WORD vendor, WORD product)
{
    char wanted[16];

    if (!lstrcmpA(token, "*:*")) return TRUE;
    wsprintfA(wanted, "%04x:%04x", vendor, product);
    return !lstrcmpiA(token, wanted);
}

static BOOL parse_value(binding *entry, const char *value)
{
    char axis[NAME_MAX];
    const char *colon;
    char *end;

    if (*value == 'b' || *value == 'p')
    {
        char marker = *value;

        entry->kind = (marker == 'b') ? BIND_BUTTON : BIND_POV;
        while (*value && entry->count < MAX_INDICES)
        {
            if (*value != marker) return FALSE;
            entry->indices[entry->count++] = (int)strtol(value + 1, &end, 10);
            if (end == value + 1) return FALSE;
            value = (*end == ',') ? end + 1 : end;
        }
        return entry->count > 0;
    }

    colon = strchr(value, ':');
    if (!colon || (size_t)(colon - value) >= sizeof(axis)) return FALSE;
    lstrcpynA(axis, value, (int)(colon - value) + 1);
    entry->axis_offset = axis_offset(axis);
    if (entry->axis_offset < 0) return FALSE;
    entry->kind = BIND_AXIS;
    entry->axis_min = strtol(colon + 1, &end, 10);
    if (*end != ':') return FALSE;
    entry->axis_max = strtol(end + 1, NULL, 10);
    return entry->axis_max != entry->axis_min;
}

static void add_binding(const char *token)
{
    const char *equals = strchr(token, '=');
    binding *entry;

    if (!equals || binding_count >= MAX_BINDINGS) return;
    if ((size_t)(equals - token) >= NAME_MAX) return;
    entry = &bindings[binding_count];
    ZeroMemory(entry, sizeof(*entry));
    lstrcpynA(entry->control, token, (int)(equals - token) + 1);
    if (parse_value(entry, equals + 1)) binding_count++;
    else trace_format("  ignored unparsable binding %s\n", token);
}

/* Loads the first config line whose device id matches; TRUE when one did. */
static BOOL load_config(const char *text, WORD vendor, WORD product)
{
    const char *line = text;

    while (*line)
    {
        char token[64];
        const char *end = line;
        const char *cursor;

        while (*end && *end != '\n') end++;
        cursor = next_token(line, end, token, sizeof(token));
        if (cursor && device_matches(token, vendor, product))
        {
            binding_count = 0;
            while ((cursor = next_token(cursor, end, token, sizeof(token))) != NULL)
                add_binding(token);
            return binding_count > 0;
        }
        line = *end ? end + 1 : end;
    }
    return FALSE;
}

static BOOL CALLBACK enum_device_cb(const DIDEVICEINSTANCEA *instance, void *ctx)
{
    const char *config = (const char *)ctx;
    IDirectInputDevice8A *candidate = NULL;
    WORD vendor = (WORD)(instance->guidProduct.Data1 & 0xFFFF);
    WORD product = (WORD)(instance->guidProduct.Data1 >> 16);
    DIDEVCAPS caps;
    HRESULT hr;

    hr = IDirectInput8_CreateDevice(di, &instance->guidInstance, &candidate, NULL);
    if (FAILED(hr))
    {
        trace_format("device \"%s\" vid=%04x pid=%04x: CreateDevice failed\n",
                     instance->tszProductName, vendor, product);
        return DIENUM_CONTINUE;
    }

    caps.dwSize = sizeof(caps);
    if (FAILED(IDirectInputDevice8_GetCapabilities(candidate, &caps))) ZeroMemory(&caps, sizeof(caps));
    trace_format("device \"%s\" vid=%04x pid=%04x buttons=%u axes=%u povs=%u\n",
                 instance->tszProductName, vendor, product,
                 (unsigned)caps.dwButtons, (unsigned)caps.dwAxes, (unsigned)caps.dwPOVs);

    if (!load_config(config, vendor, product))
    {
        trace_line("  no profile for this device; skipped\n");
        IDirectInputDevice8_Release(candidate);
        return DIENUM_CONTINUE;
    }

    if (FAILED(IDirectInputDevice8_SetDataFormat(candidate, &c_dfDIJoystick2)))
    {
        trace_line("  SetDataFormat failed; skipped\n");
        binding_count = 0;
        IDirectInputDevice8_Release(candidate);
        return DIENUM_CONTINUE;
    }

    IDirectInputDevice8_SetCooperativeLevel(candidate, NULL, DISCL_BACKGROUND | DISCL_NONEXCLUSIVE);
    IDirectInputDevice8_Acquire(candidate);
    device = candidate;
    trace_format("  selected, %d bindings\n", binding_count);
    return DIENUM_STOP;
}

static void init_directinput(void)
{
    const char *config;
    HMODULE module;

    if (init_done) return;
    init_done = TRUE;

    config = getenv("GUITAR_SHIM_CONFIG");
    tracing = getenv("GUITAR_SHIM_TRACE") != NULL;
    if (!config || !*config)
    {
        config = DEFAULT_CONFIG;
        trace_line("GUITAR_SHIM_CONFIG unset; using the built-in fallback layout\n");
    }

    module = GetModuleHandleA(NULL);
    if (FAILED(DirectInput8Create(module, DIRECTINPUT_VERSION, &IID_IDirectInput8A, (void **)&di, NULL)))
    {
        trace_line("DirectInput8Create failed\n");
        return;
    }

    IDirectInput8_EnumDevices(di, DI8DEVCLASS_GAMECTRL, enum_device_cb, (void *)config,
                              DIEDFL_ATTACHEDONLY);
    if (!device) trace_line("no guitar matched a profile; the game will see no controller\n");
}

static void trace_changes(const DIJOYSTATE2 *js)
{
    int i;

    if (!have_previous)
    {
        have_previous = TRUE;
    }
    else
    {
        for (i = 0; i < 128; i++)
            if ((js->rgbButtons[i] & 0x80) != (previous.rgbButtons[i] & 0x80))
                trace_format("  rgbButtons[%d] %s\n", i, (js->rgbButtons[i] & 0x80) ? "down" : "up");
        for (i = 0; i < 4; i++)
            if (js->rgdwPOV[i] != previous.rgdwPOV[i])
                trace_format("  rgdwPOV[%d] %d\n", i, (int)js->rgdwPOV[i]);
        for (i = 0; i < (int)(sizeof(AXIS_SOURCES) / sizeof(AXIS_SOURCES[0])); i++)
        {
            LONG now = *(const LONG *)((const BYTE *)js + AXIS_SOURCES[i].offset);
            LONG was = *(const LONG *)((const BYTE *)&previous + AXIS_SOURCES[i].offset);

            if (now != was) trace_format("  %s %d\n", AXIS_SOURCES[i].name, (int)now);
        }
    }
    previous = *js;
}

static DWORD poll_state(DIJOYSTATE2 *js)
{
    HRESULT hr;

    init_directinput();
    if (!device) return ERROR_DEVICE_NOT_CONNECTED;

    hr = IDirectInputDevice8_Poll(device);
    if (FAILED(hr))
    {
        IDirectInputDevice8_Acquire(device);
        hr = IDirectInputDevice8_Poll(device);
    }

    hr = IDirectInputDevice8_GetDeviceState(device, sizeof(*js), js);
    if (FAILED(hr))
    {
        IDirectInputDevice8_Acquire(device);
        hr = IDirectInputDevice8_GetDeviceState(device, sizeof(*js), js);
    }

    if (FAILED(hr)) return ERROR_DEVICE_NOT_CONNECTED;
    if (tracing) trace_changes(js);
    return ERROR_SUCCESS;
}

/* Full-range map: a whammy resting at its minimum reads -32768, as guitar
 * modes expect, rather than centring at zero. */
static SHORT scale_thumb(LONG value, LONG min, LONG max)
{
    LONGLONG span = (LONGLONG)max - min;

    if (span <= 0) return 0;
    if (value <= min) return -32768;
    if (value >= max) return 32767;
    return (SHORT)(((LONGLONG)(value - min) * 65535) / span - 32768);
}

static BYTE scale_trigger(LONG value, LONG min, LONG max)
{
    LONGLONG span = (LONGLONG)max - min;

    if (span <= 0) return 0;
    if (value <= min) return 0;
    if (value >= max) return 255;
    return (BYTE)(((LONGLONG)(value - min) * 255) / span);
}

static BOOL pov_active(DWORD angle, const char *control)
{
    if (LOWORD(angle) == 0xFFFF || angle > 36000) return FALSE;
    if (!lstrcmpA(control, "dpup")) return angle >= 31500 || angle <= 4500;
    if (!lstrcmpA(control, "dpright")) return angle >= 4500 && angle <= 13500;
    if (!lstrcmpA(control, "dpdown")) return angle >= 13500 && angle <= 22500;
    if (!lstrcmpA(control, "dpleft")) return angle >= 22500 && angle <= 31500;
    return FALSE;
}

static void apply_axis(XINPUT_GAMEPAD_LOCAL *pad, const binding *entry, LONG raw)
{
    if (!lstrcmpA(entry->control, "rightx"))
        pad->sThumbRX = scale_thumb(raw, entry->axis_min, entry->axis_max);
    else if (!lstrcmpA(entry->control, "righty"))
        pad->sThumbRY = scale_thumb(raw, entry->axis_min, entry->axis_max);
    else if (!lstrcmpA(entry->control, "leftx"))
        pad->sThumbLX = scale_thumb(raw, entry->axis_min, entry->axis_max);
    else if (!lstrcmpA(entry->control, "lefty"))
        pad->sThumbLY = scale_thumb(raw, entry->axis_min, entry->axis_max);
    else if (!lstrcmpA(entry->control, "lefttrigger"))
        pad->bLeftTrigger = scale_trigger(raw, entry->axis_min, entry->axis_max);
    else if (!lstrcmpA(entry->control, "righttrigger"))
        pad->bRightTrigger = scale_trigger(raw, entry->axis_min, entry->axis_max);
}

static void apply_bindings(const DIJOYSTATE2 *js, XINPUT_GAMEPAD_LOCAL *pad)
{
    int i, n;

    for (i = 0; i < binding_count; i++)
    {
        const binding *entry = &bindings[i];

        if (entry->kind == BIND_BUTTON)
        {
            for (n = 0; n < entry->count; n++)
                if (entry->indices[n] < 128 && (js->rgbButtons[entry->indices[n]] & 0x80))
                    pad->wButtons |= button_mask(entry->control);
        }
        else if (entry->kind == BIND_POV)
        {
            if (entry->indices[0] < 4 && pov_active(js->rgdwPOV[entry->indices[0]], entry->control))
                pad->wButtons |= button_mask(entry->control);
        }
        else
        {
            apply_axis(pad, entry, *(const LONG *)((const BYTE *)js + entry->axis_offset));
        }
    }
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID reserved)
{
    (void)inst;
    (void)reserved;
    if (reason == DLL_PROCESS_DETACH)
    {
        if (device)
        {
            IDirectInputDevice8_Unacquire(device);
            IDirectInputDevice8_Release(device);
            device = NULL;
        }
        if (di)
        {
            IDirectInput8_Release(di);
            di = NULL;
        }
        if (trace_file != INVALID_HANDLE_VALUE)
        {
            CloseHandle(trace_file);
            trace_file = INVALID_HANDLE_VALUE;
        }
    }
    return TRUE;
}

__declspec(dllexport) DWORD WINAPI XInputGetState(DWORD index, XINPUT_STATE_LOCAL *state)
{
    DIJOYSTATE2 js;
    DWORD ret;

    if (index) return ERROR_DEVICE_NOT_CONNECTED;
    if (!state) return ERROR_INVALID_PARAMETER;

    ZeroMemory(&js, sizeof(js));
    ret = poll_state(&js);
    if (ret) return ret;

    ZeroMemory(state, sizeof(*state));
    state->dwPacketNumber = ++packet;
    apply_bindings(&js, &state->Gamepad);
    return ERROR_SUCCESS;
}

__declspec(dllexport) DWORD WINAPI XInputSetState(DWORD index, XINPUT_VIBRATION_LOCAL *vibration)
{
    (void)vibration;
    return index ? ERROR_DEVICE_NOT_CONNECTED : ERROR_SUCCESS;
}

__declspec(dllexport) DWORD WINAPI XInputGetCapabilities(DWORD index, DWORD flags, XINPUT_CAPABILITIES_LOCAL *caps)
{
    (void)flags;
    if (index) return ERROR_DEVICE_NOT_CONNECTED;
    if (!caps) return ERROR_INVALID_PARAMETER;

    ZeroMemory(caps, sizeof(*caps));
    caps->Type = 0x01;    /* XINPUT_DEVTYPE_GAMEPAD */
    caps->SubType = 0x07; /* XINPUT_DEVSUBTYPE_GUITAR_ALTERNATE */
    caps->Flags = 0x0001;
    caps->Gamepad.wButtons = 0xf13f;
    caps->Gamepad.bLeftTrigger = 0;
    caps->Gamepad.bRightTrigger = 0;
    caps->Gamepad.sThumbRX = 32767;
    return ERROR_SUCCESS;
}

__declspec(dllexport) void WINAPI XInputEnable(BOOL enable)
{
    (void)enable;
}

__declspec(dllexport) DWORD WINAPI XInputGetStateEx(DWORD index, XINPUT_STATE_LOCAL *state)
{
    return XInputGetState(index, state);
}

__declspec(dllexport) DWORD WINAPI XInputGetDSoundAudioDeviceGuids(DWORD index, GUID *render, GUID *capture)
{
    (void)render;
    (void)capture;
    return index ? ERROR_DEVICE_NOT_CONNECTED : ERROR_SUCCESS;
}

__declspec(dllexport) DWORD WINAPI XInputGetBatteryInformation(DWORD index, BYTE dev_type, void *battery)
{
    (void)dev_type;
    if (index) return ERROR_DEVICE_NOT_CONNECTED;
    if (battery) ZeroMemory(battery, 2);
    return ERROR_SUCCESS;
}

__declspec(dllexport) DWORD WINAPI XInputGetKeystroke(DWORD index, DWORD reserved, void *keystroke)
{
    (void)reserved;
    (void)keystroke;
    return index ? ERROR_DEVICE_NOT_CONNECTED : ERROR_EMPTY;
}
