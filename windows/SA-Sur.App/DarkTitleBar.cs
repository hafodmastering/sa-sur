// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Limited and Sudeep Audio.com LLP

using System.Runtime.InteropServices;

namespace SaSur.App;

// The title bar is drawn by DWM, not by Avalonia. RequestedThemeVariant recolours the content
// only, which is why the dark appearance used to leave a white bar above a black window (the
// macOS build applies NSApp.appearance, which does move the whole window).
//
// DWMWA_USE_IMMERSIVE_DARK_MODE is attribute 20 on Windows 10 2004 and later and 19 on 1809-1909;
// the package's floor is 1809, so both are tried. A non-zero result from the first call means the
// attribute is unknown to this build of Windows.
internal static class DarkTitleBar
{
    private const int ImmersiveDarkMode = 20;
    private const int ImmersiveDarkModePre2004 = 19;

    public static void Apply(IntPtr hwnd, bool dark)
    {
        if (hwnd == IntPtr.Zero)
        {
            return;
        }

        var value = dark ? 1 : 0;
        if (DwmSetWindowAttribute(hwnd, ImmersiveDarkMode, ref value, sizeof(int)) != 0)
        {
            DwmSetWindowAttribute(hwnd, ImmersiveDarkModePre2004, ref value, sizeof(int));
        }
    }

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
}
