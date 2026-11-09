import winim/lean
import winim/inc/shellapi
{.link: "icon.res".}

#since this is my first proejct, im just gonna type out what im gonna do first

const
    appname = "let there be light!"
    windowwidth = 360
    windowheight = 180
    sliderid = 1001
    labelid = 1002
    tbmGetPos = WM_USER
    tbmSetPos = WM_USER + 5
    tbmSetRange = WM_USER + 6
    wmtray = WM_USER + 1
    trayid = 1
    exitid = 2001
    aboutid = 2002
    edgegap = 10
    bgcolor = 0X202020

type
    PhysicalMonitorData {.packed.} = object
        handle: HANDLE
        description: array[128, WCHAR]

proc InitCommonControls() {.stdcall, dynlib: "comctl32.dll", importc.}
proc GetNumberOfPhysicalMonitorsFromHMONITOR(monitor: HMONITOR, count: ptr DWORD): BOOL {.stdcall, dynlib: "dxva2.dll", importc.}
proc GetPhysicalMonitorsFromHMONITOR(monitor: HMONITOR, count: DWORD, monitors: ptr PhysicalMonitorData): BOOL {.stdcall, dynlib: "dxva2.dll", importc.}
proc GetMonitorBrightness(monitor: HANDLE, minimum: ptr DWORD, current: ptr DWORD, maximum: ptr DWORD): BOOL {.stdcall, dynlib: "dxva2.dll", importc.}
proc SetMonitorBrightness(monitor: HANDLE, brightness: DWORD): BOOL {.stdcall, dynlib: "dxva2.dll", importc.}
proc DestroyPhysicalMonitor(monitor: HANDLE): BOOL {.stdcall, dynlib: "dxva2.dll", importc.}

var
    physhandle: HANDLE
    brightmin: DWORD
    brightmax: DWORD
    brightnessnow: DWORD
    slider: HWND
    valueLabel: HWND
    nid: NOTIFYICONDATA
    bgbrush: HBRUSH

proc findMonitor(monitor: HMONITOR, dc: HDC, rect: ptr RECT, data: LPARAM): BOOL {.stdcall.} =
    var count: DWORD = 0
    if GetNumberOfPhysicalMonitorsFromHMONITOR(monitor, addr count) == 0: return 1
    if count == 0: return 1

    var monitors = newSeq[PhysicalMonitorData](int(count))
    if GetPhysicalMonitorsFromHMONITOR(monitor, count, addr monitors[0]) == 0: return 1

    var found = false
    for item in monitors:
        var low, current, high: DWORD
        if not found and GetMonitorBrightness(item.handle, addr low, addr current, addr high) != 0:
            physhandle = item.handle
            brightmin = low
            brightnessnow = current
            brightmax = high
            found = true
        else:
            discard DestroyPhysicalMonitor(item.handle)

    return if found: 0 else: 1

# puts the window in the bottom right corner, above the taskbar
proc placewindow(hwnd: HWND) =
    var area: RECT
    discard SystemParametersInfo(SPI_GETWORKAREA, 0, addr area, 0)
    let x = int32(area.right - windowwidth - edgegap)
    let y = int32(area.bottom - windowheight - edgegap)
    discard SetWindowPos(hwnd, 0, x, y, 0, 0, SWP_NOSIZE or SWP_NOZORDER)

proc windowproc(hwnd: HWND, msg: UINT, wparam: WPARAM, lparam: LPARAM): LRESULT {.stdcall.} =
    case msg
    of WM_HSCROLL:
        if physhandle != 0 and slider != 0:
            let pos = int(SendMessage(slider, tbmGetPos, 0, 0))
            let raange = int(brightmax - brightmin)
            let bright = brightmin + DWORD((raange * pos + 50) div 100)

            if SetMonitorBrightness(physhandle, bright) != 0:
                brightnessnow = bright
                discard SetWindowText(valueLabel, $pos & "% :P")
            return 0

    of WM_NCLBUTTONDOWN:
        # block dragging by the title bar so it stays in the corner
        if wparam == WPARAM(HTCAPTION): return 0
        return DefWindowProc(hwnd, msg, wparam, lparam)

    of WM_CLOSE:
        # the X button hides to the tray instead of quitting
        discard ShowWindow(hwnd, SW_HIDE)
        return 0

    of WM_SIZE:
        # minimizing also hides to the tray
        if int(wparam) == SIZE_MINIMIZED: discard ShowWindow(hwnd, SW_HIDE)
        return DefWindowProc(hwnd, msg, wparam, lparam)


    of WM_CTLCOLORSTATIC:
        discard SetTextColor(HDC(wparam), 0xFFFFFF)
        discard SetBkColor(HDC(wparam), bgcolor)
        return LRESULT(bgbrush)

    of wmtray:
        if lparam == WM_LBUTTONUP:
            discard ShowWindow(hwnd, SW_RESTORE)
            placewindow(hwnd)
            discard SetForegroundWindow(hwnd)
        elif lparam == WM_RBUTTONUP:                                                                              ##if youre reading this, my apps probably messed up and youre trying to fix it. dont even bother, do yourself a favour and installs something like monitorian lol
            var pt: POINT
            discard GetCursorPos(addr pt)
            let menu = CreatePopupMenu()
            discard AppendMenu(menu, MF_STRING, aboutid, "about :)")
            discard AppendMenu(menu, MF_SEPARATOR, 0, nil)
            discard AppendMenu(menu, MF_STRING, exitid, "close :(")
            discard SetForegroundWindow(hwnd)
            discard TrackPopupMenu(menu, TPM_RIGHTBUTTON, pt.x, pt.y, 0, hwnd, nil)
            discard DestroyMenu(menu)
        return 0

    of WM_COMMAND:
        let id = int(wparam) and 0xffff
        if id == aboutid:
            let abouttext = "let....there...be...light!... or ehh, brightness!!\n\nmade by kashyap (theodd1isoutman56 on all platforms) :P\n\nchange your monitor's brightness using the slider, cuz somebody (cough cough microsoft) doesnt wanna include brightness sliders for external monitors in their base operating system, thanks a bunch.\n\n made with nim, super cool language, thx a bunch ^^, "
            var mb: MSGBOXPARAMS
            mb.cbSize = UINT(sizeof(MSGBOXPARAMS))
            mb.hwndOwner = 0
            mb.hInstance = GetModuleHandle(nil)
            mb.lpszText = abouttext
            mb.lpszCaption = "about"
            mb.dwStyle = MB_OK or MB_USERICON
            mb.lpszIcon = MAKEINTRESOURCE(1)
            discard MessageBoxIndirect(addr mb)
        elif id == exitid:
            discard DestroyWindow(hwnd)
        return 0

    of WM_DESTROY:
        discard Shell_NotifyIcon(NIM_DELETE, addr nid)
        if physhandle != 0:
            discard DestroyPhysicalMonitor(physhandle)
            physhandle = 0
        PostQuitMessage(0)
        return 0                                                                                   

    else:
        return DefWindowProc(hwnd, msg, wparam, lparam)

proc main() =
    InitCommonControls()
    discard EnumDisplayMonitors(0, nil, findMonitor, 0)

    let instance = GetModuleHandle(nil)
    let icon = LoadIcon(instance, MAKEINTRESOURCE(1))
    let cname = "runrun"
    bgbrush = CreateSolidBrush(bgcolor)
    var wc: WNDCLASSEX
    wc.cbSize = UINT(sizeof(WNDCLASSEX))
    wc.lpfnWndProc = windowproc
    wc.hInstance = instance
    wc.lpszClassName = cname
    wc.hCursor = LoadCursor(0, IDC_ARROW)
    wc.hbrBackground = bgbrush
    wc.hIcon = icon
    wc.hIconSm = icon

    if RegisterClassEx(addr wc) == 0:
        discard MessageBox(0, "window reg failed", appname, MB_OK or MB_ICONERROR)
        return

    let hwnd = CreateWindowEx(0, cname, appname, WS_OVERLAPPED or WS_CAPTION or WS_SYSMENU or WS_MINIMIZEBOX, CW_USEDEFAULT, CW_USEDEFAULT, windowwidth, windowheight, 0, 0, instance, nil)
    if hwnd == 0:
        discard MessageBox(0, "window creation fail", appname, MB_OK or MB_ICONERROR)
        if physhandle != 0: discard DestroyPhysicalMonitor(physhandle)
        return

    placewindow(hwnd)

    # tray icon
    nid.cbSize = UINT(sizeof(NOTIFYICONDATA))
    nid.hWnd = hwnd
    nid.uID = trayid
    nid.uFlags = NIF_ICON or NIF_MESSAGE or NIF_TIP
    nid.uCallbackMessage = wmtray
    nid.hIcon = icon
    let tip = "let there be light!"
    for i in 0 ..< tip.len:
        nid.szTip[i] = WCHAR(tip[i])
    discard Shell_NotifyIcon(NIM_ADD, addr nid)

    valueLabel = CreateWindowEx(0, "Static", "brightness", WS_CHILD or WS_VISIBLE, 20, 25, 300, 25, hwnd, HMENU(labelid), instance, nil)
    slider = CreateWindowEx(0, "msctls_trackbar32", "", WS_CHILD or WS_VISIBLE, 20, 65, 300, 30, hwnd, HMENU(sliderid), instance, nil)
    discard SendMessage(slider, tbmSetRange, 1, LPARAM(100 shl 16))
    discard SendMessage(slider, tbmSetPos, 1, LPARAM(50))

    if physhandle != 0 and brightmax > brightmin:
        let position = (int(brightnessnow - brightmin) * 100) div int(brightmax - brightmin)
        discard SendMessage(slider, tbmSetPos, 1, LPARAM(position))
        discard SetWindowText(valueLabel, $position & "% :P")
    else:
        discard SetWindowText(valueLabel, "monitor brightness unavailable")
        discard EnableWindow(slider, 0)

    discard ShowWindow(hwnd, SW_SHOW)
    discard UpdateWindow(hwnd)

    var msg: MSG
    while GetMessage(addr msg, 0, 0, 0) > 0:
        discard TranslateMessage(addr msg)
        discard DispatchMessage(addr msg)

main()