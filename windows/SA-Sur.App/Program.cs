// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Limited and Sudeep Audio.com LLP

using Avalonia;

namespace SaSur.App;

internal static class Program
{
    // Held for the life of the process. Two instances would mean two WASAPI clients and two
    // oscillators - two tones whose phases partially cancel, and two writers for one settings file.
    private static Mutex? _instance;

    [STAThread]
    public static void Main(string[] args)
    {
        // Local\ scopes the name to the signed-in session, which is the right boundary for a
        // per-user desktop app: a second user on the same machine gets their own instance.
        _instance = new Mutex(initiallyOwned: true, @"Local\SA-Sur.SingleInstance", out var isFirst);

        if (!isFirst)
        {
            return;
        }

        try
        {
            BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
        }
        finally
        {
            _instance.ReleaseMutex();
            _instance.Dispose();
            _instance = null;
        }
    }

    public static AppBuilder BuildAvaloniaApp() =>
        AppBuilder.Configure<App>()
            .UsePlatformDetect()
            .With(new Win32PlatformOptions
            {
                // Software rendering, deliberately: the window is 730x237 and never animates.
                RenderingMode = [Win32RenderingMode.Software],
            })
            .LogToTrace();
}
