// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Media;

namespace SaSur.Ui;

public sealed class VolumeSlider : Control
{
    public static readonly StyledProperty<double> ValueProperty =
        AvaloniaProperty.Register<VolumeSlider, double>(nameof(Value), 0.5);

    public static readonly StyledProperty<IBrush?> TrackFillProperty =
        AvaloniaProperty.Register<VolumeSlider, IBrush?>(nameof(TrackFill));

    public static readonly StyledProperty<IBrush?> TrackValueFillProperty =
        AvaloniaProperty.Register<VolumeSlider, IBrush?>(nameof(TrackValueFill));

    public static readonly StyledProperty<IBrush?> KnobFillProperty =
        AvaloniaProperty.Register<VolumeSlider, IBrush?>(nameof(KnobFill));

    public static readonly StyledProperty<IBrush?> KnobStrokeProperty =
        AvaloniaProperty.Register<VolumeSlider, IBrush?>(nameof(KnobStroke));

    // Measured from the macOS render: a 5.5 pt track, a 20 pt knob.
    private const double TrackHeight = 5.5;

    private const double KnobDiameter = 20;

    // One-twentieth of the travel per arrow key, as in the Swift slider.
    private const double KeyboardStep = 0.05;

    public static readonly StyledProperty<IBrush?> FocusRingProperty =
        AvaloniaProperty.Register<VolumeSlider, IBrush?>(nameof(FocusRing));

    static VolumeSlider()
    {
        AffectsRender<VolumeSlider>(
            ValueProperty, TrackFillProperty, TrackValueFillProperty,
            KnobFillProperty, KnobStrokeProperty, FocusRingProperty);
    }

    public VolumeSlider()
    {
        Cursor = new Cursor(StandardCursorType.Hand);

        Focusable = true;
    }

    public double Value
    {
        get => GetValue(ValueProperty);
        set => SetValue(ValueProperty, value);
    }

    public IBrush? FocusRing
    {
        get => GetValue(FocusRingProperty);
        set => SetValue(FocusRingProperty, value);
    }

    public IBrush? TrackFill
    {
        get => GetValue(TrackFillProperty);
        set => SetValue(TrackFillProperty, value);
    }

    public IBrush? TrackValueFill
    {
        get => GetValue(TrackValueFillProperty);
        set => SetValue(TrackValueFillProperty, value);
    }

    public IBrush? KnobFill
    {
        get => GetValue(KnobFillProperty);
        set => SetValue(KnobFillProperty, value);
    }

    public IBrush? KnobStroke
    {
        get => GetValue(KnobStrokeProperty);
        set => SetValue(KnobStrokeProperty, value);
    }

    public Rect KnobBounds
    {
        get
        {
            var first = KnobDiameter / 2;
            var last = Bounds.Width - (KnobDiameter / 2);
            var knobX = first + ((last - first) * Math.Clamp(Value, 0, 1));
            var centreY = Bounds.Height / 2;

            return new Rect(
                knobX - (KnobDiameter / 2),
                centreY - (KnobDiameter / 2),
                KnobDiameter,
                KnobDiameter);
        }
    }

    public override void Render(DrawingContext context)
    {
        var width = Bounds.Width;
        var height = Bounds.Height;
        var centreY = height / 2;
        var radius = TrackHeight / 2;

        context.DrawRectangle(
            TrackFill,
            null,
            new RoundedRect(new Rect(0, centreY - radius, width, TrackHeight), radius));

        context.DrawRectangle(
            TrackValueFill,
            null,
            new RoundedRect(new Rect(0, centreY - radius, KnobBounds.Center.X, TrackHeight), radius));

        var pen = KnobStroke is null ? null : new Pen(KnobStroke, 1);
        context.DrawEllipse(
            KnobFill,
            pen,
            KnobBounds.Center,
            KnobDiameter / 2,
            KnobDiameter / 2);

        if (IsFocused && FocusRing is { } ring)
        {
            context.DrawRectangle(
                null,
                new Pen(ring, 1.5),
                new RoundedRect(new Rect(0.75, 0.75, width - 1.5, height - 1.5), 4));
        }
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        double? delta = e.Key switch
        {
            Key.Left or Key.Down => -KeyboardStep,
            Key.Right or Key.Up => KeyboardStep,
            Key.PageDown => -KeyboardStep * 5,
            Key.PageUp => KeyboardStep * 5,
            Key.Home => -Value,                 // to the bottom of the travel
            Key.End => 1.0 - Value,             // to the top
            _ => null,
        };

        if (delta is null)
        {
            base.OnKeyDown(e);
            return;
        }

        Value = Math.Clamp(Value + delta.Value, 0.0, 1.0);
        e.Handled = true;

        base.OnKeyDown(e);
    }

    protected override void OnPointerPressed(PointerPressedEventArgs e)
    {
        e.Pointer.Capture(this);
        SetFromX(e.GetPosition(this).X);
        e.Handled = true;
        base.OnPointerPressed(e);
    }

    protected override void OnPointerMoved(PointerEventArgs e)
    {
        if (ReferenceEquals(e.Pointer.Captured, this))
        {
            SetFromX(e.GetPosition(this).X);
            e.Handled = true;
        }

        base.OnPointerMoved(e);
    }

    protected override void OnPointerReleased(PointerReleasedEventArgs e)
    {
        e.Pointer.Capture(null);
        base.OnPointerReleased(e);
    }

    private void SetFromX(double x)
    {
        var first = KnobDiameter / 2;
        var last = Bounds.Width - (KnobDiameter / 2);
        var span = Math.Max(1, last - first);

        Value = Math.Clamp((x - first) / span, 0, 1);
    }
}
