// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;
using SaSur.Audio;
using SaSur.Ui;

namespace SaSur.App;

public partial class App : Application
{
    private ToneGenerator? _tone;

    public override void Initialize() => AvaloniaXamlLoader.Load(this);

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            _tone = new ToneGenerator();

            desktop.MainWindow = new MainWindow(_tone, AppSettings.Load());
            desktop.ShutdownRequested += (_, _) => _tone?.Dispose();
        }

        base.OnFrameworkInitializationCompleted();
    }
}
