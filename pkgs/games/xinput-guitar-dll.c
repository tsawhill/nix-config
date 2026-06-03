#define COBJMACROS
#include <windows.h>
#include <dinput.h>

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

static IDirectInput8A *di;
static IDirectInputDevice8A *device;
static DWORD packet;
static BOOL init_done;
static BOOL logged_caps;

static void trace_line(const char *line)
{
    HANDLE file;
    DWORD written;

    file = CreateFileA("C:\\gh-xinput-guitar.log", FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
                       NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE) return;

    WriteFile(file, line, lstrlenA(line), &written, NULL);
    CloseHandle(file);
}

static BOOL CALLBACK enum_device_cb(const DIDEVICEINSTANCEA *instance, void *ctx)
{
    HRESULT hr;

    (void)ctx;
    if (device) return DIENUM_STOP;

    hr = IDirectInput8_CreateDevice(di, &instance->guidInstance, &device, NULL);
    if (FAILED(hr)) return DIENUM_CONTINUE;

    hr = IDirectInputDevice8_SetDataFormat(device, &c_dfDIJoystick2);
    if (FAILED(hr))
    {
        IDirectInputDevice8_Release(device);
        device = NULL;
        return DIENUM_CONTINUE;
    }

    IDirectInputDevice8_SetCooperativeLevel(device, NULL, DISCL_BACKGROUND | DISCL_NONEXCLUSIVE);
    IDirectInputDevice8_Acquire(device);
    return DIENUM_STOP;
}

static void init_directinput(void)
{
    HMODULE module;

    if (init_done) return;
    init_done = TRUE;

    module = GetModuleHandleA(NULL);
    if (FAILED(DirectInput8Create(module, DIRECTINPUT_VERSION, &IID_IDirectInput8A, (void **)&di, NULL))) return;

    IDirectInput8_EnumDevices(di, DI8DEVCLASS_GAMECTRL, enum_device_cb, NULL, DIEDFL_ATTACHEDONLY);
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

    return FAILED(hr) ? ERROR_DEVICE_NOT_CONNECTED : ERROR_SUCCESS;
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

    if (js.rgbButtons[0] & 0x80) state->Gamepad.wButtons |= 0x1000;  /* A green */
    if (js.rgbButtons[1] & 0x80) state->Gamepad.wButtons |= 0x2000;  /* B red */
    if (js.rgbButtons[3] & 0x80) state->Gamepad.wButtons |= 0x8000;  /* Y yellow */
    if (js.rgbButtons[2] & 0x80) state->Gamepad.wButtons |= 0x4000;  /* X blue */
    if (js.rgbButtons[4] & 0x80) state->Gamepad.wButtons |= 0x0100;  /* LB orange */
    if (js.rgbButtons[6] & 0x80) state->Gamepad.wButtons |= 0x0020;  /* back/select */
    if (js.rgbButtons[7] & 0x80) state->Gamepad.wButtons |= 0x0010;  /* start */
    if (js.rgbButtons[11] & 0x80) state->Gamepad.wButtons |= 0x0010; /* start */

    if (js.rgdwPOV[0] == 0) state->Gamepad.wButtons |= 0x0001;      /* dpad up */
    if (js.rgdwPOV[0] == 18000) state->Gamepad.wButtons |= 0x0002;  /* dpad down */
    if (js.rgdwPOV[0] == 27000) state->Gamepad.wButtons |= 0x0004;  /* dpad left */
    if (js.rgdwPOV[0] == 9000) state->Gamepad.wButtons |= 0x0008;   /* dpad right */

    state->Gamepad.sThumbLX = (SHORT)((js.lX > 65534 ? 65534 : js.lX) - 32768);
    state->Gamepad.sThumbLY = 0;
    state->Gamepad.sThumbRX = 0;
    state->Gamepad.sThumbRY = 0;

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
    caps->Gamepad.sThumbLX = 32767;
    if (!logged_caps)
    {
        logged_caps = TRUE;
        trace_line("XInputGetCapabilities index=0 type=1 subtype=7 buttons=0xf13f lt=0 rt=0\n");
    }
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
