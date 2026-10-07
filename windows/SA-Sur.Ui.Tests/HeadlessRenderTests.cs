// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

using Avalonia;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Input;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Styling;
using Avalonia.Themes.Fluent;
using Avalonia.Threading;
using SaSur.Core;
using ShapePath = Avalonia.Controls.Shapes.Path;
using Xunit;
using Xunit.Abstractions;

namespace SaSur.Ui.Tests;

public sealed class RenderApp : Application
{
    public override void Initialize() => Styles.Add(new FluentTheme());
}

public class HeadlessRenderTests
{
    private static readonly object SetupGate = new();
    private static bool _started;

    public HeadlessRenderTests(ITestOutputHelper output) => Output = output;

    private ITestOutputHelper Output { get; }

    private static void EnsureHeadless()
    {
        lock (SetupGate)
        {
            if (_started)
            {
                return;
            }

            AppBuilder.Configure<RenderApp>()
                .UseSkia()
                .UseHeadless(new AvaloniaHeadlessPlatformOptions { UseHeadlessDrawing = false })
                .SetupWithoutStarting();
            _started = true;
        }
    }

    private static SaSurView NewView(out AppSettings settings)
    {
        settings = new AppSettings
        {
            FilePath = Path.Combine(Path.GetTempPath(), $"sa-sur-test-{Guid.NewGuid():N}.json"),
        };
        return new SaSurView(new SilentToneOutput(), settings);
    }

    private static string RenderDirectory()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null)
        {
            if (Directory.Exists(Path.Combine(dir.FullName, "src"))
                && Directory.Exists(Path.Combine(dir.FullName, "docs")))
            {
                return Path.Combine(dir.FullName, "windows", "build", "render");
            }
            dir = dir.Parent;
        }
        return Path.Combine(Directory.GetCurrentDirectory(), "render");
    }

    [Theory]
    [InlineData("light")]
    [InlineData("dark")]
    public void The_window_renders_offscreen_in_both_appearances(string appearance)
    {
        EnsureHeadless();
        var theme = appearance == "dark" ? ThemeVariant.Dark : ThemeVariant.Light;

        var view = NewView(out _);
        var window = new Window
        {
            Content = view,
            Width = SaSurView.WindowWidth,
            Height = SaSurView.WindowHeight,
            CanResize = false,
            RequestedThemeVariant = theme,
            Background = theme == ThemeVariant.Dark ? Brushes.Black : Brushes.White,
        };

        window.Show();
        Dispatcher.UIThread.RunJobs();

        var frame = window.CaptureRenderedFrame();
        Assert.NotNull(frame);

        var directory = RenderDirectory();
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, $"sa-sur-{appearance}.png");
        frame!.Save(path);

        Output.WriteLine($"RENDER={path}");
        Output.WriteLine($"SIZE={frame.PixelSize.Width}x{frame.PixelSize.Height}");
    }

    [Fact]
    public void The_layout_measures_the_shipped_window()
    {
        EnsureHeadless();

        var view = NewView(out _);
        var window = new Window
        {
            Content = view,
            Width = SaSurView.WindowWidth,
            Height = SaSurView.WindowHeight,
        };

        window.Show();
        Dispatcher.UIThread.RunJobs();

        var notes = view.FindControl<StackPanel>("NoteRow")!;
        var octaves = view.FindControl<StackPanel>("OctaveRow")!;

        notes.Measure(Size.Infinity);
        octaves.Measure(Size.Infinity);

        Output.WriteLine($"view      = {view.Bounds.Width:F1} x {view.Bounds.Height:F1}");
        Output.WriteLine($"note row  = {notes.DesiredSize.Width:F1}  (12 x 52 + 11 x 6 = 690)");
        Output.WriteLine($"octave row= {octaves.DesiredSize.Width:F1}  (9 x 52 + 8 x 6 = 516)");

        var root = view.FindControl<StackPanel>("RootPanel")!;
        root.Measure(Size.Infinity);
        Output.WriteLine($"content needs = {root.DesiredSize.Width:F1} x {root.DesiredSize.Height:F1}");
        foreach (var child in root.Children)
        {
            child.Measure(Size.Infinity);
            Output.WriteLine($"   {child.GetType().Name,-12} {child.DesiredSize.Width:F1} x {child.DesiredSize.Height:F1}");
        }

        Assert.True(view.Bounds.Width > 0 && view.Bounds.Height > 0, "the content must be arranged");

        Assert.True(root.DesiredSize.Height <= SaSurView.WindowHeight + 0.5,
            $"the content needs {root.DesiredSize.Height:F1} px of height but the window is "
            + $"{SaSurView.WindowHeight:F0} — the footer is being clipped");

        Assert.True(root.DesiredSize.Width <= SaSurView.WindowWidth + 0.5,
            $"the content needs {root.DesiredSize.Width:F1} px of width but the window is "
            + $"{SaSurView.WindowWidth:F0}");

        Assert.Equal(690.0, notes.DesiredSize.Width, 1);
        Assert.Equal(516.0, octaves.DesiredSize.Width, 1);

        Assert.True(view.Bounds.Width <= SaSurView.WindowWidth + 0.5,
            $"the content is {view.Bounds.Width:F1} px wide; the window is {SaSurView.WindowWidth:F0}");
        Assert.True(view.Bounds.Height <= SaSurView.WindowHeight + 0.5,
            $"the content is {view.Bounds.Height:F1} px tall; the window is {SaSurView.WindowHeight:F0}");
    }

    [Fact]
    public void The_code_built_controls_are_populated()
    {
        EnsureHeadless();
        var view = NewView(out _);

        var window = new Window
        {
            Content = view,
            Width = SaSurView.WindowWidth,
            Height = SaSurView.WindowHeight,
        };
        window.Show();
        Dispatcher.UIThread.RunJobs();

        var readout = view.FindControl<StackPanel>("ReadoutRow")!;
        var readoutText = readout.Children.OfType<TextBlock>().First();
        Assert.Equal("440.00", readoutText.Text);

        var copyButton = readout.Children.OfType<Button>().Single();
        Assert.NotNull(copyButton.Content);

        var decimals = view.FindControl<StackPanel>("DecimalsRow")!;
        Assert.Equal("Decimals: 2", decimals.Children.OfType<TextBlock>().Single().Text);

        var stepperFrame = decimals.Children.OfType<Border>().Single();
        Assert.Equal(2, ((Grid)stepperFrame.Child!).Children.OfType<Button>().Count());

        var marks = view.FindControl<StackPanel>("BrandRow")!;
        Assert.Equal(3, marks.Children.Count);
        Assert.Equal(2, marks.Children.OfType<Button>().Count());
        Assert.All(marks.Children.OfType<Button>(), button => Assert.NotNull(button.Content));
        Assert.Equal("+", marks.Children.OfType<TextBlock>().Single().Text);

        var transport = view.FindControl<Button>("TransportButton")!;
        var transportRow = (StackPanel)transport.Content!;
        Assert.Equal("Play", transportRow.Children.OfType<TextBlock>().Single().Text);
        Assert.NotNull(transportRow.Children.OfType<ShapePath>().Single().Data);
    }

    [Fact]
    public void The_view_defines_every_brush_it_uses()
    {
        EnsureHeadless();
        var view = NewView(out _);

        string[] keys =
        [
            "PadFill", "PadHover", "PadPress", "PrimaryText", "SecondaryText", "Divider",
            "ControlFill", "ControlFillHover", "ControlFillPress", "StepSeparator",
            "SliderFilled", "SliderRest", "KnobFill", "KnobStroke", "SegmentSeparator",
        ];
        ThemeVariant[] variants = [ThemeVariant.Light, ThemeVariant.Dark];

        foreach (var key in keys)
        {
            foreach (var variant in variants)
            {
                Assert.True(view.Resources.TryGetResource(key, variant, out var value) && value is IBrush,
                    $"{key} must resolve as a brush for {variant}");
            }
        }
    }

    [Theory]
    [InlineData("light", 0x8E)]
    [InlineData("dark", 0x98)]
    public void The_copy_glyph_is_stroked_and_the_label_follows_the_appearance(string appearance, int redChannel)
    {
        EnsureHeadless();
        var theme = appearance == "dark" ? ThemeVariant.Dark : ThemeVariant.Light;

        var view = NewView(out _);
        var window = new Window
        {
            Content = view,
            Width = SaSurView.WindowWidth,
            Height = SaSurView.WindowHeight,
            RequestedThemeVariant = theme,
            Background = theme == ThemeVariant.Dark ? Brushes.Black : Brushes.White,
        };
        window.Show();
        Dispatcher.UIThread.RunJobs();

        var readout = view.FindControl<StackPanel>("ReadoutRow")!;
        var glyph = (ShapePath)readout.Children.OfType<Button>().Single().Content!;
        var stroke = Assert.IsAssignableFrom<ISolidColorBrush>(glyph.Stroke);
        Assert.Equal(redChannel, stroke.Color.R);

        var decimals = view.FindControl<StackPanel>("DecimalsRow")!;
        var label = decimals.Children.OfType<TextBlock>().Single();
        var labelBrush = Assert.IsAssignableFrom<ISolidColorBrush>(label.Foreground);
        Assert.Equal(redChannel, labelBrush.Color.R);
    }

    [Fact]
    public void The_footer_and_keyboard_match_the_measured_macos_geometry()
    {
        EnsureHeadless();
        var view = NewView(out _);

        var window = new Window
        {
            Content = view,
            Width = SaSurView.WindowWidth,
            Height = SaSurView.WindowHeight,
            Background = Brushes.White,
        };
        window.Show();
        Dispatcher.UIThread.RunJobs();

        Assert.Equal(730.0, view.Bounds.Width);

        var notes = view.FindControl<StackPanel>("NoteRow")!.Children.OfType<Button>().ToList();
        Assert.Equal(12, notes.Count);
        Assert.All(notes, button => Assert.Equal(52.0, button.Bounds.Width));
        Assert.Equal(690.0, notes.Sum(b => b.Bounds.Width) + (11 * 6));

        var octaves = view.FindControl<StackPanel>("OctaveRow")!.Children.OfType<Button>().ToList();
        Assert.Equal(9, octaves.Count);
        Assert.All(octaves, button => Assert.Equal(52.0, button.Bounds.Width));
        Assert.Equal(516.0, octaves.Sum(b => b.Bounds.Width) + (8 * 6));

        var transport = view.FindControl<Button>("TransportButton")!;
        Assert.Equal(82.0, transport.Bounds.Width);
        Assert.Equal(24.0, transport.Bounds.Height);

        var footer = (Grid)transport.Parent!;
        Assert.Equal(26.0, footer.Bounds.Height);

        var slider = view.FindControl<VolumeSlider>("VolumeSlider")!;
        Assert.Equal(96.0, slider.Bounds.Width);
        Assert.Equal(26.0, slider.Bounds.Height);
        Assert.True(
            slider.Bounds.Contains(slider.KnobBounds),
            $"the knob {slider.KnobBounds} escapes the slider {slider.Bounds}");

        var decimals = view.FindControl<StackPanel>("DecimalsRow")!;
        Assert.Equal("Decimals: 2", decimals.Children.OfType<TextBlock>().Single().Text);

        var stepper = decimals.Children.OfType<Border>().Single();
        Assert.Equal(20.0, stepper.Bounds.Width);
        Assert.Equal(26.0, stepper.Bounds.Height);

        var halves = ((Grid)stepper.Child!).Children.OfType<Button>().ToList();
        Assert.Equal(2, halves.Count);
        Assert.True(
            halves[0].Bounds.Y < halves[1].Bounds.Y,
            "the up chevron must sit above the down chevron");

        var stepperGrid = (Grid)stepper.Child!;
        foreach (var half in halves)
        {
            var chevron = (ShapePath)half.Content!;
            var origin = chevron.TranslatePoint(default, stepperGrid);
            Assert.NotNull(origin);

            var chevronCentreY = origin.Value.Y + (chevron.Bounds.Height / 2);
            Output.WriteLine(
                $"half={half.Bounds}  chevron bounds={chevron.Bounds} desired={chevron.DesiredSize}"
                + $"  originInGrid=({origin.Value.X:F2},{origin.Value.Y:F2})"
                + $"  centreX={origin.Value.X + (chevron.Bounds.Width / 2):F2}"
                + $"  wantCentreX={half.Bounds.Center.X:F2}");

            Assert.True(
                Math.Abs(chevronCentreY - half.Bounds.Center.Y) <= 0.5,
                $"a chevron centres at y {chevronCentreY:F2} in a button centred at "
                + $"{half.Bounds.Center.Y:F2}");

            var chevronCentreX = origin.Value.X + (chevron.Bounds.Width / 2);
            Assert.True(
                Math.Abs(chevronCentreX - half.Bounds.Center.X) <= 0.75,
                $"a chevron centres at x {chevronCentreX:F2} in a button centred at "
                + $"{half.Bounds.Center.X:F2}");
        }
    }

    [Fact]
    public void The_segment_separators_follow_the_selection()
    {
        EnsureHeadless();
        var view = NewView(out _);

        var segments = view.FindControl<StackPanel>("ConcertRow")!.Children.OfType<Button>().ToList();
        Assert.Equal(4, segments.Count);

        bool Separated(int i) => segments[i].Classes.Contains("sep");
        bool Active(int i) => segments[i].Classes.Contains("active");

        Assert.True(Active(0));
        Assert.False(Separated(1));
        Assert.True(Separated(2));
        Assert.True(Separated(3));

        view.SetConcertA(415);
        Dispatcher.UIThread.RunJobs();
        Assert.True(Active(2));
        Assert.True(Separated(1));
        Assert.False(Separated(2));
        Assert.False(Separated(3));

        view.SetConcertA(442);
        Dispatcher.UIThread.RunJobs();
        Assert.True(Active(3));
        Assert.True(Separated(1));
        Assert.True(Separated(2));
        Assert.False(Separated(3));

        view.SetConcertA(440);
        Dispatcher.UIThread.RunJobs();
        Assert.True(Active(0));
        Assert.False(Separated(1));
        Assert.True(Separated(2));
    }

    [Fact]
    public void Every_footer_control_shares_one_vertical_centre()
    {
        EnsureHeadless();
        var view = NewView(out _);

        var window = new Window
        {
            Content = view,
            Width = SaSurView.WindowWidth,
            Height = SaSurView.WindowHeight,
            Background = Brushes.White,
        };
        window.Show();
        Dispatcher.UIThread.RunJobs();

        var footer = (Grid)view.FindControl<Button>("TransportButton")!.Parent!;
        var centres = footer.Children
            .OfType<Control>()
            .Where(c => c.Bounds.Height > 0)
            .Select(c => c.Bounds.Center.Y)
            .ToList();

        Assert.True(centres.Count >= 6, $"expected the whole footer row, saw {centres.Count} items");

        var spread = centres.Max() - centres.Min();
        Assert.True(spread <= 1.0, $"footer centres differ by {spread:F2} pt: {string.Join(", ", centres.Select(c => c.ToString("F1")))}");
    }

    [Fact]
    public void The_keyboard_has_the_shipped_notes_and_octaves()
    {
        EnsureHeadless();
        var view = NewView(out _);

        var notes = view.FindControl<StackPanel>("NoteRow")!.Children.OfType<Button>().ToList();
        var octaves = view.FindControl<StackPanel>("OctaveRow")!.Children.OfType<Button>().ToList();

        Assert.Equal(12, notes.Count);
        Assert.Equal(["C", "C#", "D", "Eb", "E", "F", "F#", "G", "G#", "A", "Bb", "B"],
                     notes.Select(b => (string)b.Content!).ToArray());
        Assert.Equal(9, octaves.Count);
        Assert.Equal(["0", "1", "2", "3", "4", "5", "6", "7", "8"],
                     octaves.Select(b => (string)b.Content!).ToArray());
    }

    [Fact]
    public void Clicking_a_note_only_selects_it()
    {
        EnsureHeadless();
        var view = NewView(out _);
        var tone = (SilentToneOutput)view.Tone;

        foreach (var semitone in Enumerable.Range(0, 12))
        {
            view.SelectNote(semitone);
            Assert.False(tone.IsRunning);
        }

        view.SelectNote(0);
        Assert.Equal(0, view.Semitone);
        Assert.Equal("261.63", view.DisplayValue);
        Assert.Equal(view.Frequency, tone.LastFrequency, 9);
    }

    [Fact]
    public void Selecting_a_note_retunes_a_sounding_tone()
    {
        EnsureHeadless();
        var view = NewView(out _);
        var tone = (SilentToneOutput)view.Tone;

        view.ToggleTransport();
        Assert.True(tone.IsRunning);

        view.SelectNote(0);
        Assert.Equal(261.6255653005986, tone.LastFrequency, 9);

        view.SelectOctave(2);
        Assert.Equal(65.40639132514966, tone.LastFrequency, 9);
    }

    [Fact]
    public void A_fresh_view_opens_at_A4_440_with_two_decimals()
    {
        EnsureHeadless();
        var view = NewView(out _);

        Assert.Equal(9, view.Semitone);          // A
        Assert.Equal(4, view.Octave);            // octave 4
        Assert.Equal(440.0, view.ConcertA);
        Assert.Equal(2, view.Decimals);
        Assert.Equal("440.00", view.DisplayValue);
        Assert.False(view.Tone.IsRunning);       // and silent until asked
    }

    [Fact]
    public void The_decimals_stepper_changes_the_readout()
    {
        EnsureHeadless();
        var view = NewView(out _);

        view.SelectNote(0);                      // C4 = 261.625565...
        view.SelectOctave(4);

        view.SetDecimals(0);
        Assert.Equal("262", view.DisplayValue);

        view.SetDecimals(1);
        Assert.Equal("261.6", view.DisplayValue);

        view.SetDecimals(3);
        Assert.Equal("261.626", view.DisplayValue);

        view.SetDecimals(6);
        Assert.Equal("261.625565", view.DisplayValue);

        view.SetDecimals(2);
        Assert.Equal("261.63", view.DisplayValue);
    }

    [Fact]
    public void Concert_A_retunes_the_readout_and_the_tone()
    {
        EnsureHeadless();
        var view = NewView(out _);
        var tone = (SilentToneOutput)view.Tone;

        view.SelectNote(9);
        view.SelectOctave(4);
        Assert.Equal("440.00", view.DisplayValue);

        view.SetConcertA(432);
        Assert.Equal("432.00", view.DisplayValue);
        Assert.Equal(432.0, tone.LastFrequency, 9);

        view.SetConcertA(415);
        Assert.Equal("415.00", view.DisplayValue);
    }

    [Fact]
    public async Task The_copy_button_yields_exactly_what_the_readout_shows()
    {
        EnsureHeadless();
        var view = NewView(out _);

        view.SelectNote(9);
        view.SelectOctave(4);

        Assert.Equal("440.00", await view.CopyFrequencyAsync());

        view.SetDecimals(4);
        Assert.Equal("440.0000", await view.CopyFrequencyAsync());
    }

    [Fact]
    public void The_appearance_cycles_system_light_dark_and_is_remembered()
    {
        EnsureHeadless();
        var view = NewView(out var settings);

        Assert.Equal(ThemeMode.System, view.AppearanceMode);

        view.CycleAppearance();
        Assert.Equal(ThemeMode.Light, view.AppearanceMode);

        view.CycleAppearance();
        Assert.Equal(ThemeMode.Dark, view.AppearanceMode);

        view.CycleAppearance();
        Assert.Equal(ThemeMode.System, view.AppearanceMode);

        Assert.True(File.Exists(settings.FilePath));
        Assert.Equal(ThemeMode.System, AppSettings.LoadFrom(settings.FilePath).Appearance);

        File.Delete(settings.FilePath);
    }

    private static TextBlock ProblemText(SaSurView view) =>
        view.FindControl<StackPanel>("ReadoutRow")!.Children.OfType<TextBlock>().Last();

    [Fact]
    public void A_tone_that_cannot_start_says_so_instead_of_looking_like_a_dead_button()
    {
        EnsureHeadless();

        var settings = new AppSettings
        {
            FilePath = Path.Combine(Path.GetTempPath(), $"sa-sur-test-{Guid.NewGuid():N}.json"),
        };
        var tone = new SilentToneOutput { Failure = ToneProblem.NoOutputDevice };
        var view = new SaSurView(tone, settings);

        var window = new Window
        {
            Content = view,
            Width = SaSurView.WindowWidth,
            Height = SaSurView.WindowHeight,
            Background = Brushes.White,
        };
        window.Show();
        Dispatcher.UIThread.RunJobs();

        var problem = ProblemText(view);
        Assert.False(problem.IsVisible);

        view.ToggleTransport();
        Dispatcher.UIThread.RunJobs();          // the announcement is posted to the UI thread

        var transport = view.FindControl<Button>("TransportButton")!;
        var transportRow = (StackPanel)transport.Content!;

        Assert.False(tone.IsRunning);
        Assert.Equal("Play", transportRow.Children.OfType<TextBlock>().Single().Text);

        Assert.True(problem.IsVisible);
        Assert.Equal(ToneProblem.NoOutputDevice, problem.Text);
        Assert.Contains(ToneProblem.NoOutputDevice, Assert.IsType<string>(ToolTip.GetTip(transport)));

        var root = view.FindControl<StackPanel>("RootPanel")!;
        root.Measure(Size.Infinity);
        Assert.True(root.DesiredSize.Height <= SaSurView.WindowHeight + 0.5,
            $"the message takes the content to {root.DesiredSize.Height:F1} px in a {SaSurView.WindowHeight:F0} px window");
        Assert.True(root.DesiredSize.Width <= SaSurView.WindowWidth + 0.5,
            $"the message takes the content to {root.DesiredSize.Width:F1} px in a {SaSurView.WindowWidth:F0} px window");

        var frame = window.CaptureRenderedFrame();
        Assert.NotNull(frame);
        var directory = RenderDirectory();
        Directory.CreateDirectory(directory);
        var render = Path.Combine(directory, "sa-sur-no-audio-device.png");
        frame!.Save(render);
        Output.WriteLine($"RENDER={render}");

        tone.Failure = null;
        view.ToggleTransport();
        Dispatcher.UIThread.RunJobs();

        Assert.True(tone.IsRunning);
        Assert.False(problem.IsVisible);
        Assert.Equal("Stop", transportRow.Children.OfType<TextBlock>().Single().Text);
    }

    private static void Press(Control control, Key key) =>
        control.RaiseEvent(new KeyEventArgs { RoutedEvent = InputElement.KeyDownEvent, Key = key });

    [Fact]
    public void The_volume_slider_can_be_reached_and_adjusted_from_the_keyboard()
    {
        EnsureHeadless();
        var view = NewView(out _);
        var tone = (SilentToneOutput)view.Tone;

        var window = new Window
        {
            Content = view,
            Width = SaSurView.WindowWidth,
            Height = SaSurView.WindowHeight,
        };
        window.Show();
        Dispatcher.UIThread.RunJobs();

        var slider = view.FindControl<VolumeSlider>("VolumeSlider")!;
        Assert.True(slider.Focusable, "the slider must be reachable with Tab");

        slider.Focus();
        Dispatcher.UIThread.RunJobs();
        Assert.True(slider.IsFocused, "the slider took no focus");

        var start = slider.Value;
        Press(slider, Key.Right);
        Assert.Equal(start + 0.05, slider.Value, 9);
        Assert.Equal(slider.Value, tone.Volume, 9);

        Press(slider, Key.Left);
        Assert.Equal(start, slider.Value, 9);

        slider.Value = 0.5;
        Press(slider, Key.Up);
        Assert.Equal(0.55, slider.Value, 9);

        Press(slider, Key.PageDown);
        Assert.Equal(0.30, slider.Value, 9);
        Press(slider, Key.PageUp);
        Assert.Equal(0.55, slider.Value, 9);

        Press(slider, Key.End);
        Assert.Equal(1.0, slider.Value, 9);
        Assert.Equal(1.0, tone.Volume, 9);

        Press(slider, Key.Right);
        Assert.Equal(1.0, slider.Value, 9);

        Press(slider, Key.Home);
        Assert.Equal(0.0, slider.Value, 9);

        Press(slider, Key.Left);
        Assert.Equal(0.0, slider.Value, 9);

        var centre = slider
            .TranslatePoint(new Point(slider.Bounds.Width / 2, slider.Bounds.Height / 2), window)!.Value;

        window.MouseDown(centre, MouseButton.Left);
        Dispatcher.UIThread.RunJobs();
        Assert.Equal(0.5, slider.Value, 1);
        Assert.Equal(slider.Value, tone.Volume, 9);

        var right = slider
            .TranslatePoint(new Point(slider.Bounds.Width - 2, slider.Bounds.Height / 2), window)!.Value;

        window.MouseMove(right);
        Dispatcher.UIThread.RunJobs();
        Assert.True(slider.Value > 0.9, $"dragging to the right end gave {slider.Value:F2}");

        window.MouseUp(right, MouseButton.Left);
        Dispatcher.UIThread.RunJobs();

        var before = slider.Value;
        var space = new KeyEventArgs { RoutedEvent = InputElement.KeyDownEvent, Key = Key.Space };
        slider.RaiseEvent(space);
        Dispatcher.UIThread.RunJobs();

        Assert.False(space.Handled, "the slider must not claim Space - Space is the transport's shortcut");
        Assert.Equal(before, slider.Value, 9);

        var frame = window.CaptureRenderedFrame();
        Assert.NotNull(frame);
        var directory = RenderDirectory();
        Directory.CreateDirectory(directory);
        var render = Path.Combine(directory, "sa-sur-slider-focused.png");
        frame!.Save(render);
        Output.WriteLine($"RENDER={render}");
    }
}
