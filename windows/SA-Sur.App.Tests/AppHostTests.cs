// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

using Avalonia;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Input;
using Avalonia.Threading;
using Avalonia.VisualTree;
using SaSur.Core;
using SaSur.Ui;

namespace SaSur.App.Tests;

public class AppHostTests
{
    private static readonly object SetupGate = new();
    private static bool _started;

    private static void EnsureHeadless()
    {
        lock (SetupGate)
        {
            if (_started)
            {
                return;
            }

            AppBuilder.Configure<SaSur.App.App>()
                .UseSkia()
                .UseHeadless(new AvaloniaHeadlessPlatformOptions { UseHeadlessDrawing = false })
                .SetupWithoutStarting();
            _started = true;
        }
    }

    private static SaSur.App.MainWindow Show(IToneOutput tone)
    {
        var window = new SaSur.App.MainWindow(tone, new AppSettings());
        window.Show();
        Dispatcher.UIThread.RunJobs();
        return window;
    }

    private static SaSurView ViewIn(Window window) =>
        window.GetVisualDescendants().OfType<SaSurView>().Single();

    private static string TransportLabel(Window window)
    {
        var button = ViewIn(window).FindControl<Button>("TransportButton")!;
        return ((StackPanel)button.Content!).Children.OfType<TextBlock>().Single().Text!;
    }

    [Fact]
    public void The_window_hosts_the_interface_at_the_designed_size()
    {
        EnsureHeadless();
        var window = Show(new SilentToneOutput());
        var view = ViewIn(window);

        Assert.Equal(730.0, SaSurView.WindowWidth);
        Assert.Equal(237.0, SaSurView.WindowHeight);

        Assert.Equal(730.0, view.Bounds.Width);
        Assert.Equal(237.0, view.Bounds.Height);
    }

    private static void PressSpaceOnTheWindow(Window window) =>
        window.RaiseEvent(new KeyEventArgs
        {
            RoutedEvent = InputElement.KeyDownEvent,
            Key = Key.Space,
        });

    [Fact]
    public void Space_starts_and_stops_the_tone_one_toggle_per_press()
    {
        EnsureHeadless();
        var tone = new SilentToneOutput();
        var window = Show(tone);

        Assert.False(tone.IsRunning);
        Assert.Equal("Play", TransportLabel(window));

        PressSpaceOnTheWindow(window);
        Dispatcher.UIThread.RunJobs();
        Assert.True(tone.IsRunning);
        Assert.Equal("Stop", TransportLabel(window));

        PressSpaceOnTheWindow(window);
        Dispatcher.UIThread.RunJobs();
        Assert.False(tone.IsRunning);
        Assert.Equal("Play", TransportLabel(window));
    }

    [Fact]
    public void Space_is_left_alone_when_a_focused_control_has_already_handled_it()
    {
        EnsureHeadless();
        var tone = new SilentToneOutput();
        var window = Show(tone);

        var button = ViewIn(window).FindControl<Button>("TransportButton")!;
        button.Focus();
        Dispatcher.UIThread.RunJobs();

        window.RaiseEvent(new KeyEventArgs
        {
            RoutedEvent = InputElement.KeyDownEvent,
            Key = Key.Space,
            Handled = true,
        });
        Dispatcher.UIThread.RunJobs();

        Assert.False(tone.IsRunning);
    }

    [Fact]
    public void Space_still_starts_the_tone_with_the_volume_slider_focused()
    {
        EnsureHeadless();
        var tone = new SilentToneOutput();
        var window = Show(tone);

        var slider = ViewIn(window).FindControl<VolumeSlider>("VolumeSlider")!;
        slider.Focus();
        Dispatcher.UIThread.RunJobs();
        Assert.True(slider.IsFocused);

        slider.RaiseEvent(new KeyEventArgs
        {
            RoutedEvent = InputElement.KeyDownEvent,
            Key = Key.Space,
        });
        Dispatcher.UIThread.RunJobs();

        Assert.True(tone.IsRunning);
        Assert.Equal("Stop", TransportLabel(window));
    }

    [Fact]
    public void The_window_title_is_the_shipped_string()
    {
        EnsureHeadless();
        var window = Show(new SilentToneOutput());

        Assert.Equal("SA-Sur : Note to Frequency", window.Title);
    }

    [Fact]
    public void Closing_the_window_shuts_the_tone_down()
    {
        EnsureHeadless();
        var tone = new SpyTone();
        var window = Show(tone);

        window.Close();
        Dispatcher.UIThread.RunJobs();

        Assert.True(tone.WasShutdown);
    }

    private sealed class SpyTone : IToneOutput
    {
        public bool WasShutdown { get; private set; }

        public bool IsRunning { get; private set; }

        public string? Problem { get; private set; }

        public double Volume { get; set; } = 0.5;

        public event EventHandler? StateChanged;

        public void Play()
        {
            IsRunning = true;
            Announce();
        }

        public void Stop()
        {
            IsRunning = false;
            Announce();
        }

        public void Toggle()
        {
            if (IsRunning)
            {
                Stop();
            }
            else
            {
                Play();
            }
        }

        public void SetFrequency(double hz)
        {
        }

        public void Shutdown()
        {
            WasShutdown = true;
            IsRunning = false;
            Announce();
        }

        private void Announce() => StateChanged?.Invoke(this, EventArgs.Empty);
    }
}
