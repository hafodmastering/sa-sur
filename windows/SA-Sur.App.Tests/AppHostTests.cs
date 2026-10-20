// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Limited and Sudeep Audio.com LLP

using Avalonia;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Input;
using Avalonia.Threading;
using Avalonia.VisualTree;
using SaSur.Core;
using SaSur.Ui;

namespace SaSur.App.Tests;

public class AppHostTests : IDisposable
{
    private static readonly object SetupGate = new();
    private static bool _started;

    private SaSur.App.MainWindow? _window;

    // xunit builds a new instance per test, so closing here retires the window before the next
    // test runs. The headless host keeps every window it is given alive, and pointer input then
    // arrives at whichever one is active, which made the click helpers order-dependent.
    public void Dispose()
    {
        _window?.Close();
        _window = null;
        Dispatcher.UIThread.RunJobs();
    }

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

    private SaSur.App.MainWindow Show(IToneOutput tone)
    {
        var window = new SaSur.App.MainWindow(tone, new AppSettings());
        _window = window;
        window.Show();
        // Pointer input goes to the active window, and this test's window must be it.
        window.Activate();
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

    // A real press, not a synthesized event on the window: it goes through the headless input
    // stack to whatever holds the focus, which is the path the defect lives on.
    private static void PressSpace(TopLevel window) =>
        window.KeyPress(Key.Space, RawInputModifiers.None, PhysicalKey.Space, " ");

    private static void ClickControl(Window window, Control control)
    {
        Assert.True(control.Bounds.Width > 0 && control.Bounds.Height > 0,
            $"{control.Name ?? control.GetType().Name} has bounds {control.Bounds} - it was not laid out, so there is nothing to click");

        var centre = control.TranslatePoint(
            new Point(control.Bounds.Width / 2, control.Bounds.Height / 2), window);
        Assert.NotNull(centre);

        // A move first: that is the order a real pointer arrives in, and the headless host keeps
        // one pointer, so pressing at a new point without moving left the press un-delivered.
        window.MouseMove(centre.Value);
        Dispatcher.UIThread.RunJobs();
        window.MouseDown(centre.Value, MouseButton.Left);
        window.MouseUp(centre.Value, MouseButton.Left);
        Dispatcher.UIThread.RunJobs();
    }

    [Fact]
    public void The_window_carries_the_app_icon_not_the_generic_Windows_one()
    {
        EnsureHeadless();
        var window = Show(new SilentToneOutput());

        // Window.Icon is what Avalonia passes to SetIcon; the .csproj's ApplicationIcon only
        // brands the file. Null here is the generic-title-bar bug the Store screenshots caught.
        Assert.NotNull(window.Icon);
    }

    [Fact]
    public void F1_opens_the_help_menu_on_the_window()
    {
        EnsureHeadless();
        var window = Show(new SilentToneOutput());
        var view = ViewIn(window);

        Assert.NotNull(view.HelpMenu);
        Assert.False(view.HelpMenu!.IsOpen);

        window.RaiseEvent(new KeyEventArgs
        {
            RoutedEvent = InputElement.KeyDownEvent,
            Key = Key.F1,
        });
        Dispatcher.UIThread.RunJobs();

        Assert.True(view.HelpMenu.IsOpen, "F1 did not open the help menu");
    }

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
    public void Space_starts_the_tone_after_a_note_has_been_clicked()
    {
        EnsureHeadless();
        var tone = new SilentToneOutput();
        var window = Show(tone);
        var view = ViewIn(window);

        var c = view.FindControl<StackPanel>("NoteRow")!.Children.OfType<Button>()
            .Single(b => (string)b.Content! == "C");

        ClickControl(window, c);

        // A click focuses the button. That is the whole defect: the focused Button claims Space
        // and activates itself, so the transport never sees the key.
        Assert.True(c.IsFocused, "the click should have focused the note button");
        Assert.Equal(0, view.Semitone);
        Assert.False(tone.IsRunning);

        PressSpace(window);
        Dispatcher.UIThread.RunJobs();

        Assert.True(tone.IsRunning, "Space must start the tone after a note has been clicked");
        Assert.Equal("Stop", TransportLabel(window));
        Assert.Equal(0, view.Semitone);

        PressSpace(window);
        Dispatcher.UIThread.RunJobs();

        Assert.False(tone.IsRunning, "Space must stop the tone again");
        Assert.Equal("Play", TransportLabel(window));
    }

    [Theory]
    [InlineData("OctaveRow", "2")]
    [InlineData("ConcertRow", "432")]
    public void Space_starts_the_tone_after_another_button_has_been_clicked(string row, string label)
    {
        EnsureHeadless();
        var tone = new SilentToneOutput();
        var window = Show(tone);
        var view = ViewIn(window);

        var button = view.FindControl<StackPanel>(row)!.Children.OfType<Button>()
            .Single(b => (string)b.Content! == label);

        ClickControl(window, button);
        Assert.True(button.IsFocused, $"the click should have focused the {label} button");

        PressSpace(window);
        Dispatcher.UIThread.RunJobs();

        Assert.True(tone.IsRunning, $"Space must start the tone after {label} was clicked");
        Assert.Equal("Stop", TransportLabel(window));
    }

    [Fact]
    public void Space_toggles_the_transport_after_the_transport_itself_was_clicked()
    {
        EnsureHeadless();
        var tone = new SilentToneOutput();
        var window = Show(tone);
        var transport = ViewIn(window).FindControl<Button>("TransportButton")!;

        ClickControl(window, transport);
        Assert.True(tone.IsRunning, "the click should have started the tone");
        Assert.True(transport.IsFocused, "the click should have focused the transport button");

        PressSpace(window);
        Dispatcher.UIThread.RunJobs();

        // Once, not twice: the focused button would otherwise toggle it a second time.
        Assert.False(tone.IsRunning);
        Assert.Equal("Play", TransportLabel(window));
    }

    [Fact]
    public void Space_does_not_activate_the_button_it_was_pressed_over()
    {
        EnsureHeadless();
        var tone = new SilentToneOutput();
        var window = Show(tone);
        var view = ViewIn(window);

        // The decimals chevrons are built in code, so FindControl's namescope cannot see them.
        var up = view.GetVisualDescendants().OfType<Button>().Single(b => b.Name == "DecimalsUp");

        ClickControl(window, up);
        Assert.True(up.IsFocused, "the click should have focused the chevron");

        var decimals = view.Decimals;

        PressSpace(window);
        Dispatcher.UIThread.RunJobs();

        Assert.True(tone.IsRunning, "Space must start the tone with the chevron focused");
        Assert.Equal(decimals, view.Decimals);
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
