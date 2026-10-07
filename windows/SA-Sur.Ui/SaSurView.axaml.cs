// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

using System.Diagnostics;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Controls.Shapes;
using Avalonia.Input;
using Avalonia.Markup.Xaml;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using Avalonia.Styling;
using Avalonia.Threading;
using SaSur.Core;
using ShapePath = Avalonia.Controls.Shapes.Path;

namespace SaSur.Ui;

public partial class SaSurView : UserControl
{
    public const double WindowWidth = 730;

    public const double WindowHeight = 237;

    // 44 pt, and the reason stage-logos.sh stages the PNGs at 176 px.
    private const double LogoHeight = 44;

    private const double LogoGap = 4;

    // #DD3938, sampled from the Sudeep Audio tile so the connector agrees with it.
    private static readonly Color SudeepRed = Color.FromRgb(0xDD, 0x39, 0x38);

    private static readonly double[] A4Presets = [440, 432, 415, 442];

    private static readonly Geometry PlayGeometry = Geometry.Parse("M0,0 L10,6 L0,12 Z");
    private static readonly Geometry StopGeometry = Geometry.Parse("M0,0 H10 V12 H0 Z");
    private static readonly Geometry CopyGeometry =
        Geometry.Parse("M0.5,0.5 H7.5 V9.5 H0.5 Z M3.5,3.5 H10.5 V12.5 H3.5 Z");
    private static readonly Geometry TickGeometry = Geometry.Parse("M1.5,6.5 L5,10 L11.5,2");

    private readonly IToneOutput _tone;
    private readonly AppSettings _settings;
    private readonly List<Button> _noteButtons = [];
    private readonly List<Button> _octaveButtons = [];
    private readonly List<Button> _concertButtons = [];

    private int _semitone = 9;          // A
    private int _octave = 4;            // A4, so the default readout is 440.00
    private double _a4 = 440.0;
    private int _decimals = 2;
    private ThemeMode _theme;
    private bool _copied;

    private TextBlock? _readoutText;
    private Button? _copyButton;
    private TextBlock? _decimalsText;
    private TextBlock? _problemText;

    public SaSurView()
        : this(new SilentToneOutput(), AppSettings.Load())
    {
    }

    public SaSurView(IToneOutput tone, AppSettings settings)
    {
        _tone = tone;
        _settings = settings;
        _theme = settings.Appearance;
        _tone.Volume = 0.5;

        _tone.StateChanged += OnToneStateChanged;

        AvaloniaXamlLoader.Load(this);

        ApplyAccent();
        BuildNoteRow();
        BuildOctaveRow();
        BuildReadout();
        BuildMarks();
        BuildFooter();

        RefreshAll();
        ApplyTheme();
    }

    public IToneOutput Tone => _tone;

    public int Semitone => _semitone;

    public int Octave => _octave;

    public int Decimals => _decimals;

    public double ConcertA => _a4;

    public string DisplayValue => NoteMath.Formatted(Frequency, _decimals);

    public double Frequency => NoteMath.Frequency(_octave, _semitone, _a4);

    public void SelectNote(int semitone)
    {
        _semitone = Math.Clamp(semitone, 0, NoteMath.NoteNames.Length - 1);
        _tone.SetFrequency(Frequency);
        RefreshAll();
    }

    public void SelectOctave(int octave)
    {
        _octave = Math.Clamp(octave, 0, 8);
        _tone.SetFrequency(Frequency);
        RefreshAll();
    }

    public void SetConcertA(double a4)
    {
        _a4 = a4;
        _tone.SetFrequency(Frequency);
        RefreshAll();
    }

    public void SetDecimals(int decimals)
    {
        _decimals = Math.Clamp(decimals, 0, 6);
        RefreshAll();
    }

    public void ToggleTransport()
    {
        _tone.Toggle();
        RefreshAll();
    }

    public void CycleAppearance()
    {
        _theme = _theme.Next();
        _settings.Appearance = _theme;
        _settings.Save();
        ApplyTheme();
        RefreshAll();
    }

    public async Task<string> CopyFrequencyAsync()
    {
        var value = DisplayValue;

        try
        {
            var clipboard = TopLevel.GetTopLevel(this)?.Clipboard;
            if (clipboard is not null)
            {
                await clipboard.SetTextAsync(value);
            }
        }
        catch
        {
        }

        _copied = true;
        RefreshAll();

        _ = Task.Delay(TimeSpan.FromMilliseconds(1200)).ContinueWith(
            _ => Avalonia.Threading.Dispatcher.UIThread.Post(() =>
            {
                _copied = false;
                RefreshAll();
            }));

        return value;
    }

    public void Shutdown()
    {
        _tone.StateChanged -= OnToneStateChanged;
        _tone.Shutdown();
    }

    private void OnToneStateChanged(object? sender, EventArgs e) => Dispatcher.UIThread.Post(RefreshAll);

    public ThemeMode AppearanceMode => _theme;

    private void ApplyAccent()
    {
        var accent = Color.FromRgb(0x00, 0x78, 0xD4);
        try
        {
            var values = Application.Current?.PlatformSettings?.GetColorValues();
            if (values is { } platform && platform.AccentColor1.A > 0)
            {
                accent = platform.AccentColor1;
            }
        }
        catch
        {
        }

        Resources["AccentBrush"] = new SolidColorBrush(accent);
    }

    private Button Pad(string text, Action onClick)
    {
        var button = new Button { Content = text };
        button.Classes.Add("pad");
        button.Click += (_, _) => onClick();
        return button;
    }

    private void BuildNoteRow()
    {
        var row = this.FindControl<StackPanel>("NoteRow")!;
        for (var i = 0; i < NoteMath.NoteNames.Length; i++)
        {
            var index = i;
            var button = Pad(NoteMath.NoteNames[i], () => SelectNote(index));
            _noteButtons.Add(button);
            row.Children.Add(button);
        }
    }

    private void BuildOctaveRow()
    {
        var row = this.FindControl<StackPanel>("OctaveRow")!;
        foreach (var octave in NoteMath.Octaves)
        {
            var value = octave;
            var button = Pad(value.ToString(), () => SelectOctave(value));
            _octaveButtons.Add(button);
            row.Children.Add(button);

        }
    }

    private void BuildReadout()
    {
        var row = this.FindControl<StackPanel>("ReadoutRow")!;
        row.VerticalAlignment = Avalonia.Layout.VerticalAlignment.Bottom;

        _readoutText = new TextBlock();
        _readoutText.Classes.Add("readout");
        row.Children.Add(_readoutText);

        var unit = new TextBlock { Text = "Hz" };
        unit.Classes.Add("unit");
        unit.VerticalAlignment = Avalonia.Layout.VerticalAlignment.Bottom;
        unit.Margin = new Thickness(0, 0, 0, 6);
        row.Children.Add(unit);

        _copyButton = new Button { Width = 24, Height = 24, Margin = new Thickness(2, 0, 0, 8) };
        _copyButton.Classes.Add("bare");
        _copyButton.VerticalAlignment = Avalonia.Layout.VerticalAlignment.Bottom;
        _copyButton.Click += async (_, _) => await CopyFrequencyAsync();
        row.Children.Add(_copyButton);

        _problemText = new TextBlock { IsVisible = false };
        _problemText.Classes.Add("problem");
        row.Children.Add(_problemText);
    }

    private void BuildMarks()
    {
        var row = this.FindControl<StackPanel>("BrandRow")!;
        row.Spacing = LogoGap;

        row.Children.Add(MarkButton("avares://SaSur.Ui/Assets/Images/hafod-mastering.png",
                                    "https://hafodmastering.co.uk", "hafod-mastering"));

        var plus = new TextBlock
        {
            Text = "+",
            // 18, not the Swift's 13: a text "+" reads smaller than SF Symbols' plus, which fills
            // its own bounds. A visual match, not a like-for-like number.
            FontSize = 18,
            FontWeight = FontWeight.SemiBold,
            Foreground = new SolidColorBrush(SudeepRed),
            VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
            HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Center,
        };
        row.Children.Add(plus);

        row.Children.Add(MarkButton("avares://SaSur.Ui/Assets/Images/sudeep-audio.png",
                                    "https://sudeepaudio.com", "sudeep-audio"));
    }

    private static Button MarkButton(string asset, string url, string name)
    {
        var image = new Image
        {
            Source = new Bitmap(AssetLoader.Open(new Uri(asset))),
            Height = LogoHeight,
            Stretch = Stretch.Uniform,
        };

        var button = new Button { Content = image, Name = name };
        button.Classes.Add("bare");
        button.Click += (_, _) =>
        {
            try
            {
                Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
            }
            catch
            {
            }
        };

        ToolTip.SetTip(button, new Uri(url).Host);
        return button;
    }

    private void BuildFooter()
    {
        var transport = this.FindControl<Button>("TransportButton")!;
        transport.Click += (_, _) => ToggleTransport();

        var slider = this.FindControl<VolumeSlider>("VolumeSlider")!;
        slider.PropertyChanged += (_, e) =>
        {
            if (e.Property == VolumeSlider.ValueProperty)
            {
                _tone.Volume = slider.Value;
            }
        };

        var concert = this.FindControl<StackPanel>("ConcertRow")!;
        for (var i = 0; i < A4Presets.Length; i++)
        {
            var value = A4Presets[i];
            var button = new Button { Content = ((int)value).ToString() };
            button.Classes.Add("segment");
            if (i == 0)
            {
                button.Classes.Add("first");
            }
            if (i == A4Presets.Length - 1)
            {
                button.Classes.Add("last");
            }
            button.Click += (_, _) => SetConcertA(value);
            _concertButtons.Add(button);
            concert.Children.Add(button);
        }

        var decimals = this.FindControl<StackPanel>("DecimalsRow")!;
        _decimalsText = new TextBlock();
        _decimalsText.Classes.Add("label");
        decimals.Children.Add(_decimalsText);

        var stepper = DecimalsStepper(
            up: () => SetDecimals(_decimals + 1),
            down: () => SetDecimals(_decimals - 1));
        stepper.Margin = new Thickness(8, 0, 0, 0);
        decimals.Children.Add(stepper);

        var appearance = this.FindControl<Button>("AppearanceButton")!;
        appearance.Click += (_, _) => CycleAppearance();
    }

    private static Border DecimalsStepper(Action up, Action down)
    {
        var grid = new Grid
        {
            RowDefinitions = new RowDefinitions("*,1,*"),
            ColumnDefinitions = new ColumnDefinitions("*"),
        };

        var upButton = Chevron(down: false, up);
        grid.Children.Add(upButton);
        Grid.SetRow(upButton, 0);

        var separator = new Border { Height = 1 };
        separator.Classes.Add("stepSeparator");
        grid.Children.Add(separator);
        Grid.SetRow(separator, 1);

        var downButton = Chevron(down: true, down);
        grid.Children.Add(downButton);
        Grid.SetRow(downButton, 2);

        var frame = new Border
        {
            Width = 20,
            Height = 26,
            CornerRadius = new CornerRadius(6),
            ClipToBounds = true,
            Child = grid,
        };
        frame.Classes.Add("stepper");
        return frame;
    }

    private static Button Chevron(bool down, Action onClick)
    {
        var path = new ShapePath
        {
            Width = 9,
            Height = 6,
            Stretch = Stretch.None,
            Data = Geometry.Parse(down ? "M1,1 L4.5,5 L8,1" : "M1,5 L4.5,1 L8,5"),
            HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Center,
            VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
        };
        path.Classes.Add("chevron");

        var button = new Button { Content = path };
        button.Classes.Add("step");
        button.HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Stretch;
        button.VerticalAlignment = Avalonia.Layout.VerticalAlignment.Stretch;
        button.Click += (_, _) => onClick();
        button.Name = down ? "DecimalsDown" : "DecimalsUp";
        ToolTip.SetTip(button, down ? "Fewer decimals" : "More decimals");
        return button;
    }

    private void RefreshAll()
    {
        if (_readoutText is null)
        {
            return;
        }

        _readoutText.Text = DisplayValue;

        for (var i = 0; i < _noteButtons.Count; i++)
        {
            _noteButtons[i].Classes.Set("active", i == _semitone);
        }

        for (var i = 0; i < _octaveButtons.Count; i++)
        {
            _octaveButtons[i].Classes.Set("active", NoteMath.Octaves[i] == _octave);
        }

        for (var i = 0; i < _concertButtons.Count; i++)
        {
            _concertButtons[i].Classes.Set("active", Math.Abs(A4Presets[i] - _a4) < 0.5);
        }

        for (var i = 1; i < _concertButtons.Count; i++)
        {
            var bothUnselected =
                !_concertButtons[i].Classes.Contains("active")
                && !_concertButtons[i - 1].Classes.Contains("active");

            _concertButtons[i].Classes.Set("sep", bothUnselected);
        }

        if (_decimalsText is not null)
        {
            _decimalsText.Text = $"Decimals: {_decimals}";
        }

        var transport = this.FindControl<Button>("TransportButton");
        if (transport is not null)
        {
            var running = _tone.IsRunning;
            if (transport.Content is StackPanel content
                && content.Children.Count == 2
                && content.Children[0] is ShapePath icon
                && content.Children[1] is TextBlock label)
            {
                icon.Data = running ? StopGeometry : PlayGeometry;
                label.Text = running ? "Stop" : "Play";
            }

            ToolTip.SetTip(transport, _tone.Problem is { Length: > 0 } why
                ? $"The tone cannot play: {why}"
                : "Start or stop the tone (Space)");
        }

        if (_problemText is not null)
        {
            var problem = _tone.Problem;
            _problemText.Text = problem ?? string.Empty;
            _problemText.IsVisible = !string.IsNullOrEmpty(problem);
        }

        if (_copyButton is not null)
        {
            _copyButton.Content = CopiedIcon();
            ToolTip.SetTip(_copyButton, $"Copy {DisplayValue} to the clipboard");
        }

        var appearance = this.FindControl<Button>("AppearanceButton");
        if (appearance is not null)
        {
            appearance.Content = new TextBlock
            {
                Text = _theme.Symbol(),
                FontSize = 13,
                HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Center,
                VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
            };
            ToolTip.SetTip(appearance, _theme.Help());
        }
    }

    private Control CopiedIcon()
    {
        var path = new ShapePath
        {
            Width = 15,
            Height = 13,
            Data = _copied ? TickGeometry : CopyGeometry,
        };

        path.Classes.Add("icon");
        path.Classes.Set("copied", _copied);
        return path;
    }

    private void ApplyTheme()
    {
        var variant = _theme switch
        {
            ThemeMode.Light => ThemeVariant.Light,
            ThemeMode.Dark => ThemeVariant.Dark,
            _ => ThemeVariant.Default,
        };

        if (Application.Current is { } application)
        {
            application.RequestedThemeVariant = variant;
        }

        if (TopLevel.GetTopLevel(this) is { } top)
        {
            top.RequestedThemeVariant = variant;
        }
    }
}
