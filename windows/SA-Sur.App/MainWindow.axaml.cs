// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Markup.Xaml;
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

        base.OnKeyDown(e);
    }

    protected override void OnClosed(EventArgs e)
    {
        _view.Shutdown();
        base.OnClosed(e);
    }
}
