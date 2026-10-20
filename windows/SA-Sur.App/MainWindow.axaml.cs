// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Limited and Sudeep Audio.com LLP

using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Markup.Xaml;
using Avalonia.Styling;
using SaSur.Core;
using SaSur.Ui;

namespace SaSur.App;

public partial class MainWindow : Window
{
    private readonly SaSurView _view;

    public MainWindow() : this(new SilentToneOutput(), AppSettings.Load())
    {
    }

    public MainWindow(IToneOutput tone, AppSettings settings)
    {
        AvaloniaXamlLoader.Load(this);

        _view = new SaSurView(tone, settings);
        this.FindControl<ContentControl>("Host")!.Content = _view;
        _view.HelpRequested += OnHelpRequested;
        _view.AppearanceChanged += (_, _) => ApplyTitleBarTheme();

        // Space is the transport's shortcut wherever the focus is in this window. A Button claims
        // Space and activates itself, so a bubbling-only handler let a click on a note leave Space
        // re-triggering that note instead of reaching the transport. KeyDown is registered
        // Tunnel | Bubble, and the tunnel pass reaches the window before the focused control, so
        // handling it here pre-empts the button; e.Handled then keeps the bubble pass from
        // toggling a second time.
        AddHandler(KeyDownEvent, OnTransportKeyDown, RoutingStrategies.Tunnel);
    }

    private void OnTransportKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.Handled || e.Key != Key.Space)
        {
            return;
        }

        e.Handled = true;
        _view.ToggleTransport();
    }

    // F1 is not claimed by any control the view builds, so it can be answered on the bubble pass.
    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (e.Key == Key.F1 && !e.Handled)
        {
            _view.OpenHelpMenu();
            e.Handled = true;
        }

        base.OnKeyDown(e);
    }

    protected override void OnOpened(EventArgs e)
    {
        base.OnOpened(e);
        ApplyTitleBarTheme();
    }

    private void OnHelpRequested(object? sender, HelpTopic topic)
    {
        switch (topic)
        {
            case HelpTopic.Manual:
                if (HelpFiles.OpenManual() is null)
                {
                    TextWindow.Show(this, "User manual",
                        "This build does not carry SA-Sur-Manual.pdf.\n\n"
                        + "The manual is attached to the GitHub release as "
                        + "SA-Sur-User-Manual.pdf, and the same text is in docs/MANUAL.md in the "
                        + "source repository.");
                }
                break;

            case HelpTopic.Licences:
                HelpFiles.ShowLicences(this);
                break;

            default:
                HelpFiles.ShowAbout(this);
                break;
        }
    }

    // The non-client area is DWM's, so the appearance has to be pushed at the window as well as
    // set on the content. ThemeVariant.Default means "follow the system", which is resolved here
    // through ActualThemeVariant rather than assumed.
    private void ApplyTitleBarTheme()
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        var dark = ActualThemeVariant == ThemeVariant.Dark;
        var handle = TryGetPlatformHandle();
        if (handle is not null)
        {
            DarkTitleBar.Apply(handle.Handle, dark);
        }
    }

    protected override void OnClosed(EventArgs e)
    {
        _view.HelpRequested -= OnHelpRequested;
        _view.Shutdown();
        base.OnClosed(e);
    }
}
