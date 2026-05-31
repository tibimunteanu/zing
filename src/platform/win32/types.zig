const std = @import("std");

pub const BOOL = c_int;
pub const BYTE = u8;
pub const WORD = u16;
pub const DWORD = u32;
pub const UINT = c_uint;
pub const LONG = c_long;
pub const ULONG = c_ulong;
pub const INT = c_int;
pub const WCHAR = u16;
pub const LPCWSTR = [*:0]align(1) const WCHAR;
pub const LPWSTR = [*:0]align(1) WCHAR;
pub const LPCSTR = [*:0]const u8;
pub const LPSTR = [*:0]u8;
pub const ATOM = WORD;
pub const HANDLE = ?*anyopaque;
pub const HWND = ?*opaque {};
pub const HINSTANCE = ?*opaque {};
pub const HMODULE = ?*opaque {};
pub const HICON = HANDLE;
pub const HCURSOR = HANDLE;
pub const HBRUSH = HANDLE;
pub const HMONITOR = ?*opaque {};
pub const HDC = ?*opaque {};
pub const HGDIOBJ = HANDLE;
pub const HBITMAP = HANDLE;
pub const HMENU = ?*opaque {};
pub const HGLOBAL = HANDLE;
pub const HDROP = HANDLE;
pub const FARPROC = ?*const anyopaque;
pub const LPARAM = isize;
pub const WPARAM = usize;
pub const LRESULT = isize;
pub const HRESULT = c_long;
pub const COLORREF = DWORD;
pub const ULONG_PTR = usize;
pub const LONG_PTR = isize;
pub const DWORD_PTR = usize;
pub const SIZE_T = usize;
pub const VkInstance = enum(u64) { null_handle = 0, _ };
pub const VkPhysicalDevice = enum(u64) { null_handle = 0, _ };
pub const VkSurfaceKHR = enum(u64) { null_handle = 0, _ };

pub const Window = extern struct {
    handle: HWND,
    should_close: bool = false,
    callback_id: usize = 0,
    user_pointer: ?*anyopaque = null,
    cursor: HCURSOR = null,
    cursor_tracked: bool = false,
    cursor_mode: c_int = 0,
    width: u32 = 0,
    height: u32 = 0,
    min_width: u32 = 0,
    min_height: u32 = 0,
    max_width: u32 = 0,
    max_height: u32 = 0,
    numer: u32 = 0,
    denom: u32 = 0,
    high_surrogate: WCHAR = 0,
};

pub var instance: HINSTANCE = null;

pub const POINT = extern struct {
    x: LONG,
    y: LONG,
};

pub const SIZE = extern struct {
    cx: LONG,
    cy: LONG,
};

pub const RECT = extern struct {
    left: LONG,
    top: LONG,
    right: LONG,
    bottom: LONG,
};

pub const MSG = extern struct {
    hwnd: HWND,
    message: UINT,
    wParam: WPARAM,
    lParam: LPARAM,
    time: DWORD,
    pt: POINT,
};

pub const WNDCLASSEXW = extern struct {
    cbSize: UINT = @sizeOf(WNDCLASSEXW),
    style: UINT = 0,
    lpfnWndProc: WNDPROC,
    cbClsExtra: INT = 0,
    cbWndExtra: INT = 0,
    hInstance: HINSTANCE,
    hIcon: HICON = null,
    hCursor: HCURSOR = null,
    hbrBackground: HBRUSH = null,
    lpszMenuName: ?LPCWSTR = null,
    lpszClassName: LPCWSTR,
    hIconSm: HICON = null,
};

pub const WNDPROC = *const fn (HWND, UINT, WPARAM, LPARAM) callconv(.winapi) LRESULT;

pub const WINDOWPLACEMENT = extern struct {
    length: UINT = @sizeOf(WINDOWPLACEMENT),
    flags: UINT = 0,
    showCmd: UINT = 0,
    ptMinPosition: POINT = .{ .x = 0, .y = 0 },
    ptMaxPosition: POINT = .{ .x = 0, .y = 0 },
    rcNormalPosition: RECT = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
};

pub const MINMAXINFO = extern struct {
    ptReserved: POINT,
    ptMaxSize: POINT,
    ptMaxPosition: POINT,
    ptMinTrackSize: POINT,
    ptMaxTrackSize: POINT,
};

pub const MONITORINFO = extern struct {
    cbSize: DWORD = @sizeOf(MONITORINFO),
    rcMonitor: RECT = undefined,
    rcWork: RECT = undefined,
    dwFlags: DWORD = 0,
};

pub const MONITORINFOEXW = extern struct {
    cbSize: DWORD = @sizeOf(MONITORINFOEXW),
    rcMonitor: RECT = undefined,
    rcWork: RECT = undefined,
    dwFlags: DWORD = 0,
    szDevice: [32:0]WCHAR = @splat(0),
};

pub const DISPLAY_DEVICEW = extern struct {
    cb: DWORD = @sizeOf(DISPLAY_DEVICEW),
    DeviceName: [32:0]WCHAR = @splat(0),
    DeviceString: [128:0]WCHAR = @splat(0),
    StateFlags: DWORD = 0,
    DeviceID: [128:0]WCHAR = @splat(0),
    DeviceKey: [128:0]WCHAR = @splat(0),
};

pub const DEVMODEW = extern struct {
    dmDeviceName: [32]WCHAR = @splat(0),
    dmSpecVersion: WORD = 0,
    dmDriverVersion: WORD = 0,
    dmSize: WORD = @sizeOf(DEVMODEW),
    dmDriverExtra: WORD = 0,
    dmFields: DWORD = 0,
    u1: extern union {
        s1: extern struct {
            dmOrientation: i16,
            dmPaperSize: i16,
            dmPaperLength: i16,
            dmPaperWidth: i16,
            dmScale: i16,
            dmCopies: i16,
            dmDefaultSource: i16,
            dmPrintQuality: i16,
        },
        s2: extern struct {
            dmPosition: POINT,
            dmDisplayOrientation: DWORD,
            dmDisplayFixedOutput: DWORD,
        },
    } = .{ .s2 = .{ .dmPosition = .{ .x = 0, .y = 0 }, .dmDisplayOrientation = 0, .dmDisplayFixedOutput = 0 } },
    dmColor: i16 = 0,
    dmDuplex: i16 = 0,
    dmYResolution: i16 = 0,
    dmTTOption: i16 = 0,
    dmCollate: i16 = 0,
    dmFormName: [32]WCHAR = @splat(0),
    dmLogPixels: WORD = 0,
    dmBitsPerPel: DWORD = 0,
    dmPelsWidth: DWORD = 0,
    dmPelsHeight: DWORD = 0,
    u2: extern union {
        dmDisplayFlags: DWORD,
        dmNup: DWORD,
    } = .{ .dmDisplayFlags = 0 },
    dmDisplayFrequency: DWORD = 0,
    dmICMMethod: DWORD = 0,
    dmICMIntent: DWORD = 0,
    dmMediaType: DWORD = 0,
    dmDitherType: DWORD = 0,
    dmReserved1: DWORD = 0,
    dmReserved2: DWORD = 0,
    dmPanningWidth: DWORD = 0,
    dmPanningHeight: DWORD = 0,
};

pub const BITMAPV5HEADER = extern struct {
    bV5Size: DWORD = @sizeOf(BITMAPV5HEADER),
    bV5Width: LONG = 0,
    bV5Height: LONG = 0,
    bV5Planes: WORD = 1,
    bV5BitCount: WORD = 32,
    bV5Compression: DWORD = BI_BITFIELDS,
    bV5SizeImage: DWORD = 0,
    bV5XPelsPerMeter: LONG = 0,
    bV5YPelsPerMeter: LONG = 0,
    bV5ClrUsed: DWORD = 0,
    bV5ClrImportant: DWORD = 0,
    bV5RedMask: DWORD = 0x00ff0000,
    bV5GreenMask: DWORD = 0x0000ff00,
    bV5BlueMask: DWORD = 0x000000ff,
    bV5AlphaMask: DWORD = 0xff000000,
    bV5CSType: DWORD = 0x73524742,
    bV5Endpoints: [36]BYTE = @splat(0),
    bV5GammaRed: DWORD = 0,
    bV5GammaGreen: DWORD = 0,
    bV5GammaBlue: DWORD = 0,
    bV5Intent: DWORD = 0,
    bV5ProfileData: DWORD = 0,
    bV5ProfileSize: DWORD = 0,
    bV5Reserved: DWORD = 0,
};

pub const ICONINFO = extern struct {
    fIcon: BOOL,
    xHotspot: DWORD,
    yHotspot: DWORD,
    hbmMask: HBITMAP,
    hbmColor: HBITMAP,
};

pub const PAINTSTRUCT = extern struct {
    hdc: HDC,
    fErase: BOOL,
    rcPaint: RECT,
    fRestore: BOOL,
    fIncUpdate: BOOL,
    rgbReserved: [32]BYTE,
};

pub const TRACKMOUSEEVENT = extern struct {
    cbSize: DWORD = @sizeOf(TRACKMOUSEEVENT),
    dwFlags: DWORD,
    hwndTrack: HWND,
    dwHoverTime: DWORD = 0,
};

pub const RAWINPUTDEVICE = extern struct {
    usUsagePage: WORD,
    usUsage: WORD,
    dwFlags: DWORD,
    hwndTarget: HWND,
};

pub const RAWINPUT = opaque {};

pub const VULKAN_WIN32_SURFACE_CREATE_INFO_KHR = extern struct {
    s_type: c_int,
    p_next: ?*const anyopaque = null,
    flags: DWORD = 0,
    hinstance: HINSTANCE,
    hwnd: HWND,
};

pub const ENUM_CURRENT_SETTINGS: DWORD = 0xffffffff;
pub const DISPLAY_DEVICE_ACTIVE: DWORD = 0x00000001;
pub const DISPLAY_DEVICE_PRIMARY_DEVICE: DWORD = 0x00000004;
pub const MONITOR_DEFAULTTONEAREST: DWORD = 2;
pub const USER_DEFAULT_SCREEN_DPI: UINT = 96;
pub const BI_BITFIELDS: DWORD = 3;
pub const DIB_RGB_COLORS: UINT = 0;
pub const IMAGE_CURSOR: UINT = 2;
pub const LR_DEFAULTSIZE: UINT = 0x00000040;
pub const LR_SHARED: UINT = 0x00008000;
pub const OCR_NORMAL: usize = 32512;
pub const OCR_IBEAM: usize = 32513;
pub const OCR_CROSS: usize = 32515;
pub const OCR_HAND: usize = 32649;
pub const OCR_SIZEWE: usize = 32644;
pub const OCR_SIZENS: usize = 32645;
pub const OCR_SIZENWSE: usize = 32642;
pub const OCR_SIZENESW: usize = 32643;
pub const OCR_SIZEALL: usize = 32646;
pub const OCR_NO: usize = 32648;
pub const IDC_ARROW: LPCWSTR = @ptrFromInt(OCR_NORMAL);
pub const IDC_IBEAM: LPCWSTR = @ptrFromInt(OCR_IBEAM);
pub const IDC_CROSS: LPCWSTR = @ptrFromInt(OCR_CROSS);
pub const IDC_HAND: LPCWSTR = @ptrFromInt(OCR_HAND);
pub const IDC_SIZEWE: LPCWSTR = @ptrFromInt(OCR_SIZEWE);
pub const IDC_SIZENS: LPCWSTR = @ptrFromInt(OCR_SIZENS);
pub const IDC_SIZENWSE: LPCWSTR = @ptrFromInt(OCR_SIZENWSE);
pub const IDC_SIZENESW: LPCWSTR = @ptrFromInt(OCR_SIZENESW);
pub const IDC_SIZEALL: LPCWSTR = @ptrFromInt(OCR_SIZEALL);
pub const IDC_NO: LPCWSTR = @ptrFromInt(OCR_NO);

pub const WS_OVERLAPPED: DWORD = 0x00000000;
pub const WS_POPUP: DWORD = 0x80000000;
pub const WS_CAPTION: DWORD = 0x00c00000;
pub const WS_SYSMENU: DWORD = 0x00080000;
pub const WS_THICKFRAME: DWORD = 0x00040000;
pub const WS_MINIMIZEBOX: DWORD = 0x00020000;
pub const WS_MAXIMIZEBOX: DWORD = 0x00010000;
pub const WS_VISIBLE: DWORD = 0x10000000;
pub const WS_OVERLAPPEDWINDOW: DWORD = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX;
pub const WS_EX_APPWINDOW: DWORD = 0x00040000;
pub const WS_EX_TOPMOST: DWORD = 0x00000008;
pub const WS_EX_LAYERED: DWORD = 0x00080000;
pub const WS_EX_TRANSPARENT: DWORD = 0x00000020;
pub const WS_EX_ACCEPTFILES: DWORD = 0x00000010;
pub const GWL_STYLE: INT = -16;
pub const GWL_EXSTYLE: INT = -20;
pub const GWLP_USERDATA: INT = -21;
pub const SW_HIDE: INT = 0;
pub const SW_SHOWNORMAL: INT = 1;
pub const SW_SHOWMINIMIZED: INT = 2;
pub const SW_SHOWMAXIMIZED: INT = 3;
pub const SW_SHOW: INT = 5;
pub const SW_RESTORE: INT = 9;
pub const SWP_NOSIZE: UINT = 0x0001;
pub const SWP_NOMOVE: UINT = 0x0002;
pub const SWP_NOZORDER: UINT = 0x0004;
pub const SWP_NOACTIVATE: UINT = 0x0010;
pub const SWP_FRAMECHANGED: UINT = 0x0020;
pub const SWP_SHOWWINDOW: UINT = 0x0040;
pub const CW_USEDEFAULT: INT = @bitCast(@as(u32, 0x80000000));
pub const HWND_TOPMOST: HWND = @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));
pub const HWND_NOTOPMOST: HWND = @ptrFromInt(@as(usize, @bitCast(@as(isize, -2))));

pub const WM_NULL: UINT = 0x0000;
pub const WM_CREATE: UINT = 0x0001;
pub const WM_DESTROY: UINT = 0x0002;
pub const WM_MOVE: UINT = 0x0003;
pub const WM_SIZE: UINT = 0x0005;
pub const WM_CLOSE: UINT = 0x0010;
pub const WM_SETFOCUS: UINT = 0x0007;
pub const WM_KILLFOCUS: UINT = 0x0008;
pub const WM_PAINT: UINT = 0x000f;
pub const WM_SETCURSOR: UINT = 0x0020;
pub const WM_GETMINMAXINFO: UINT = 0x0024;
pub const WM_ACTIVATE: UINT = 0x0006;
pub const WM_DROPFILES: UINT = 0x0233;
pub const WM_KEYDOWN: UINT = 0x0100;
pub const WM_KEYUP: UINT = 0x0101;
pub const WM_CHAR: UINT = 0x0102;
pub const WM_SYSKEYDOWN: UINT = 0x0104;
pub const WM_SYSKEYUP: UINT = 0x0105;
pub const WM_UNICHAR: UINT = 0x0109;
pub const WM_MOUSEMOVE: UINT = 0x0200;
pub const WM_LBUTTONDOWN: UINT = 0x0201;
pub const WM_LBUTTONUP: UINT = 0x0202;
pub const WM_RBUTTONDOWN: UINT = 0x0204;
pub const WM_RBUTTONUP: UINT = 0x0205;
pub const WM_MBUTTONDOWN: UINT = 0x0207;
pub const WM_MBUTTONUP: UINT = 0x0208;
pub const WM_MOUSEWHEEL: UINT = 0x020a;
pub const WM_XBUTTONDOWN: UINT = 0x020b;
pub const WM_XBUTTONUP: UINT = 0x020c;
pub const WM_MOUSEHWHEEL: UINT = 0x020e;
pub const WM_MOUSELEAVE: UINT = 0x02a3;
pub const WM_DPICHANGED: UINT = 0x02e0;
pub const SIZE_MINIMIZED: WPARAM = 1;
pub const SIZE_MAXIMIZED: WPARAM = 2;
pub const SIZE_RESTORED: WPARAM = 0;
pub const PM_REMOVE: UINT = 0x0001;
pub const QS_ALLINPUT: DWORD = 0x04ff;
pub const WAIT_OBJECT_0: DWORD = 0;
pub const INFINITE: DWORD = 0xffffffff;
pub const TME_LEAVE: DWORD = 0x00000002;
pub const RIDEV_REMOVE: DWORD = 0x00000001;
pub const RIDEV_INPUTSINK: DWORD = 0x00000100;
pub const RIDEV_NOLEGACY: DWORD = 0x00000030;
pub const SPI_GETMOUSETRAILS: UINT = 0x005e;
pub const WM_APP_EMPTY: UINT = 0x8000 + 1;
pub const MAPVK_VK_TO_VSC: UINT = 0;
pub const MAPVK_VSC_TO_VK: UINT = 1;
pub const MAPVK_VK_TO_CHAR: UINT = 2;
pub const MAPVK_VSC_TO_VK_EX: UINT = 3;
pub const SM_CXSCREEN: INT = 0;
pub const SM_CYSCREEN: INT = 1;
pub const SM_CXICON: INT = 11;
pub const SM_CYICON: INT = 12;
pub const SM_CXSMICON: INT = 49;
pub const SM_CYSMICON: INT = 50;
pub const LOGPIXELSX: INT = 88;
pub const LOGPIXELSY: INT = 90;
pub const HORZSIZE: INT = 4;
pub const VERTSIZE: INT = 6;
pub const HORZRES: INT = 8;
pub const VERTRES: INT = 10;
pub const CF_UNICODETEXT: UINT = 13;
pub const GMEM_MOVEABLE: UINT = 0x0002;
pub const LWA_ALPHA: DWORD = 0x00000002;
pub const VK_SHIFT: UINT = 0x10;
pub const VK_CONTROL: UINT = 0x11;
pub const VK_MENU: UINT = 0x12;
pub const VK_LWIN: UINT = 0x5b;
pub const VK_RWIN: UINT = 0x5c;
pub const VK_CAPITAL: UINT = 0x14;
pub const VK_NUMLOCK: UINT = 0x90;
pub const UNICODE_NOCHAR: WPARAM = 0xffff;

pub fn loword(value: usize) u16 {
    return @truncate(value);
}

pub fn hiword(value: usize) u16 {
    return @truncate(value >> 16);
}

pub fn getX(lparam: LPARAM) i32 {
    return @as(i16, @bitCast(loword(@bitCast(lparam))));
}

pub fn getY(lparam: LPARAM) i32 {
    return @as(i16, @bitCast(hiword(@bitCast(lparam))));
}

pub fn utf8ToWideZ(allocator: std.mem.Allocator, value: [*:0]const u8) ![:0]WCHAR {
    return try std.unicode.wtf8ToWtf16LeAllocZ(allocator, std.mem.span(value));
}

pub fn wideToUtf8Z(allocator: std.mem.Allocator, value: [*:0]const WCHAR) ![:0]u8 {
    return try std.unicode.wtf16LeToWtf8AllocZ(allocator, std.mem.span(value));
}

pub extern "kernel32" fn GetModuleHandleW(lpModuleName: ?LPCWSTR) callconv(.winapi) HMODULE;
pub extern "kernel32" fn LoadLibraryA(lpLibFileName: LPCSTR) callconv(.winapi) HMODULE;
pub extern "kernel32" fn FreeLibrary(hLibModule: HMODULE) callconv(.winapi) BOOL;
pub extern "kernel32" fn GetProcAddress(hModule: HMODULE, lpProcName: LPCSTR) callconv(.winapi) FARPROC;
pub extern "kernel32" fn QueryPerformanceCounter(lpPerformanceCount: *i64) callconv(.winapi) BOOL;
pub extern "kernel32" fn QueryPerformanceFrequency(lpFrequency: *i64) callconv(.winapi) BOOL;
pub extern "kernel32" fn GlobalAlloc(uFlags: UINT, dwBytes: SIZE_T) callconv(.winapi) HGLOBAL;
pub extern "kernel32" fn GlobalLock(hMem: HGLOBAL) callconv(.winapi) ?*anyopaque;
pub extern "kernel32" fn GlobalUnlock(hMem: HGLOBAL) callconv(.winapi) BOOL;
pub extern "kernel32" fn GlobalFree(hMem: HGLOBAL) callconv(.winapi) HGLOBAL;
pub extern "kernel32" fn GetLastError() callconv(.winapi) DWORD;

pub extern "user32" fn RegisterClassExW(param0: *const WNDCLASSEXW) callconv(.winapi) ATOM;
pub extern "user32" fn UnregisterClassW(lpClassName: LPCWSTR, hInstance: HINSTANCE) callconv(.winapi) BOOL;
pub extern "user32" fn CreateWindowExW(dwExStyle: DWORD, lpClassName: LPCWSTR, lpWindowName: LPCWSTR, dwStyle: DWORD, x: INT, y: INT, nWidth: INT, nHeight: INT, hWndParent: HWND, hMenu: HMENU, hInstance: HINSTANCE, lpParam: ?*anyopaque) callconv(.winapi) HWND;
pub extern "user32" fn DestroyWindow(hWnd: HWND) callconv(.winapi) BOOL;
pub extern "user32" fn DefWindowProcW(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) LRESULT;
pub extern "user32" fn ShowWindow(hWnd: HWND, nCmdShow: INT) callconv(.winapi) BOOL;
pub extern "user32" fn SetForegroundWindow(hWnd: HWND) callconv(.winapi) BOOL;
pub extern "user32" fn BringWindowToTop(hWnd: HWND) callconv(.winapi) BOOL;
pub extern "user32" fn SetFocus(hWnd: HWND) callconv(.winapi) HWND;
pub extern "user32" fn FlashWindow(hWnd: HWND, bInvert: BOOL) callconv(.winapi) BOOL;
pub extern "user32" fn SetWindowTextW(hWnd: HWND, lpString: LPCWSTR) callconv(.winapi) BOOL;
pub extern "user32" fn GetWindowRect(hWnd: HWND, lpRect: *RECT) callconv(.winapi) BOOL;
pub extern "user32" fn GetClientRect(hWnd: HWND, lpRect: *RECT) callconv(.winapi) BOOL;
pub extern "user32" fn AdjustWindowRectEx(lpRect: *RECT, dwStyle: DWORD, bMenu: BOOL, dwExStyle: DWORD) callconv(.winapi) BOOL;
pub extern "user32" fn SetWindowPos(hWnd: HWND, hWndInsertAfter: HWND, X: INT, Y: INT, cx: INT, cy: INT, uFlags: UINT) callconv(.winapi) BOOL;
pub extern "user32" fn MoveWindow(hWnd: HWND, X: INT, Y: INT, nWidth: INT, nHeight: INT, bRepaint: BOOL) callconv(.winapi) BOOL;
pub extern "user32" fn IsWindowVisible(hWnd: HWND) callconv(.winapi) BOOL;
pub extern "user32" fn IsIconic(hWnd: HWND) callconv(.winapi) BOOL;
pub extern "user32" fn IsZoomed(hWnd: HWND) callconv(.winapi) BOOL;
pub extern "user32" fn GetActiveWindow() callconv(.winapi) HWND;
pub extern "user32" fn GetFocus() callconv(.winapi) HWND;
pub extern "user32" fn SetWindowLongPtrW(hWnd: HWND, nIndex: INT, dwNewLong: LONG_PTR) callconv(.winapi) LONG_PTR;
pub extern "user32" fn GetWindowLongPtrW(hWnd: HWND, nIndex: INT) callconv(.winapi) LONG_PTR;
pub extern "user32" fn SetProcessDPIAware() callconv(.winapi) BOOL;
pub extern "user32" fn SetLayeredWindowAttributes(hwnd: HWND, crKey: COLORREF, bAlpha: BYTE, dwFlags: DWORD) callconv(.winapi) BOOL;
pub extern "user32" fn GetCursorPos(lpPoint: *POINT) callconv(.winapi) BOOL;
pub extern "user32" fn SetCursorPos(X: INT, Y: INT) callconv(.winapi) BOOL;
pub extern "user32" fn ScreenToClient(hWnd: HWND, lpPoint: *POINT) callconv(.winapi) BOOL;
pub extern "user32" fn ClientToScreen(hWnd: HWND, lpPoint: *POINT) callconv(.winapi) BOOL;
pub extern "user32" fn SetCursor(hCursor: HCURSOR) callconv(.winapi) HCURSOR;
pub extern "user32" fn LoadCursorW(hInstance: HINSTANCE, lpCursorName: LPCWSTR) callconv(.winapi) HCURSOR;
pub extern "user32" fn LoadImageW(hInst: HINSTANCE, name: LPCWSTR, type: UINT, cx: INT, cy: INT, fuLoad: UINT) callconv(.winapi) HANDLE;
pub extern "user32" fn DestroyIcon(hIcon: HICON) callconv(.winapi) BOOL;
pub extern "user32" fn CreateIconIndirect(piconinfo: *ICONINFO) callconv(.winapi) HICON;
pub extern "user32" fn PeekMessageW(lpMsg: *MSG, hWnd: HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT, wRemoveMsg: UINT) callconv(.winapi) BOOL;
pub extern "user32" fn GetMessageW(lpMsg: *MSG, hWnd: HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT) callconv(.winapi) BOOL;
pub extern "user32" fn TranslateMessage(lpMsg: *const MSG) callconv(.winapi) BOOL;
pub extern "user32" fn DispatchMessageW(lpMsg: *const MSG) callconv(.winapi) LRESULT;
pub extern "user32" fn PostMessageW(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) BOOL;
pub extern "user32" fn MsgWaitForMultipleObjects(nCount: DWORD, pHandles: ?*const HANDLE, bWaitAll: BOOL, dwMilliseconds: DWORD, dwWakeMask: DWORD) callconv(.winapi) DWORD;
pub extern "user32" fn TrackMouseEvent(lpEventTrack: *TRACKMOUSEEVENT) callconv(.winapi) BOOL;
pub extern "user32" fn SetCapture(hWnd: HWND) callconv(.winapi) HWND;
pub extern "user32" fn ReleaseCapture() callconv(.winapi) BOOL;
pub extern "user32" fn GetKeyState(nVirtKey: INT) callconv(.winapi) i16;
pub extern "user32" fn MapVirtualKeyW(uCode: UINT, uMapType: UINT) callconv(.winapi) UINT;
pub extern "user32" fn ToUnicode(wVirtKey: UINT, wScanCode: UINT, lpKeyState: *const BYTE, pwszBuff: *WCHAR, cchBuff: INT, wFlags: UINT) callconv(.winapi) INT;
pub extern "user32" fn GetKeyboardState(lpKeyState: *BYTE) callconv(.winapi) BOOL;
pub extern "user32" fn GetSystemMetrics(nIndex: INT) callconv(.winapi) INT;
pub extern "user32" fn SystemParametersInfoW(uiAction: UINT, uiParam: UINT, pvParam: ?*anyopaque, fWinIni: UINT) callconv(.winapi) BOOL;
pub extern "user32" fn GetDC(hWnd: HWND) callconv(.winapi) HDC;
pub extern "user32" fn ReleaseDC(hWnd: HWND, hDC: HDC) callconv(.winapi) INT;
pub extern "user32" fn MonitorFromWindow(hwnd: HWND, dwFlags: DWORD) callconv(.winapi) HMONITOR;
pub extern "user32" fn MonitorFromPoint(pt: POINT, dwFlags: DWORD) callconv(.winapi) HMONITOR;
pub extern "user32" fn GetMonitorInfoW(hMonitor: HMONITOR, lpmi: *MONITORINFO) callconv(.winapi) BOOL;
pub extern "user32" fn EnumDisplayMonitors(hdc: HDC, lprcClip: ?*const RECT, lpfnEnum: *const fn (HMONITOR, HDC, *RECT, LPARAM) callconv(.winapi) BOOL, dwData: LPARAM) callconv(.winapi) BOOL;
pub extern "user32" fn EnumDisplayDevicesW(lpDevice: ?LPCWSTR, iDevNum: DWORD, lpDisplayDevice: *DISPLAY_DEVICEW, dwFlags: DWORD) callconv(.winapi) BOOL;
pub extern "user32" fn EnumDisplaySettingsW(lpszDeviceName: ?LPCWSTR, iModeNum: DWORD, lpDevMode: *DEVMODEW) callconv(.winapi) BOOL;
pub extern "user32" fn EnumDisplaySettingsExW(lpszDeviceName: ?LPCWSTR, iModeNum: DWORD, lpDevMode: *DEVMODEW, dwFlags: DWORD) callconv(.winapi) BOOL;
pub extern "user32" fn OpenClipboard(hWndNewOwner: HWND) callconv(.winapi) BOOL;
pub extern "user32" fn CloseClipboard() callconv(.winapi) BOOL;
pub extern "user32" fn EmptyClipboard() callconv(.winapi) BOOL;
pub extern "user32" fn SetClipboardData(uFormat: UINT, hMem: HGLOBAL) callconv(.winapi) HANDLE;
pub extern "user32" fn GetClipboardData(uFormat: UINT) callconv(.winapi) HANDLE;
pub extern "user32" fn IsClipboardFormatAvailable(format: UINT) callconv(.winapi) BOOL;
pub extern "user32" fn RegisterRawInputDevices(pRawInputDevices: *const RAWINPUTDEVICE, uiNumDevices: UINT, cbSize: UINT) callconv(.winapi) BOOL;

pub extern "gdi32" fn CreateDIBSection(hdc: HDC, pbmi: *const BITMAPV5HEADER, usage: UINT, ppvBits: *?*anyopaque, hSection: HANDLE, offset: DWORD) callconv(.winapi) HBITMAP;
pub extern "gdi32" fn CreateBitmap(nWidth: INT, nHeight: INT, nPlanes: UINT, nBitCount: UINT, lpBits: ?*const anyopaque) callconv(.winapi) HBITMAP;
pub extern "gdi32" fn DeleteObject(ho: HGDIOBJ) callconv(.winapi) BOOL;
pub extern "gdi32" fn GetDeviceCaps(hdc: HDC, index: INT) callconv(.winapi) INT;

pub extern "shell32" fn DragAcceptFiles(hWnd: HWND, fAccept: BOOL) callconv(.winapi) void;
pub extern "shell32" fn DragQueryFileW(hDrop: HDROP, iFile: UINT, lpszFile: ?LPWSTR, cch: UINT) callconv(.winapi) UINT;
pub extern "shell32" fn DragFinish(hDrop: HDROP) callconv(.winapi) void;
