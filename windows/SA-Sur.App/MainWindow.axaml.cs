// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Limited and Sudeep Audio.com LLP

using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
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
    }

    // Key events bubble to the window from the focused control; a tunnel handler is never invoked
    // on this path, and e.Handled is what stops one press toggling the transport twice.
    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (e.Key == Key.Space && !e.Handled)
        {
            _view.ToggleTransport();
            e.Handled = true;
        }
        else if (e.Key == Key.F1 && !e.Handled)
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
