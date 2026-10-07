// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

namespace SaSur.Core;

public sealed class SineOscillator
{
    private readonly double _smoothing;
    private double _frequency = 440.0;
    private double _targetGain;

    public double SampleRate { get; set; }

    public double Phase { get; private set; }

    public double Gain { get; private set; }

    public double Frequency
    {
        get => Volatile.Read(ref _frequency);
        set => Volatile.Write(ref _frequency, value);
    }

    public double TargetGain
    {
        get => Volatile.Read(ref _targetGain);
        set => Volatile.Write(ref _targetGain, value);
    }

    public SineOscillator(double sampleRate, double rampSeconds = 0.012)
    {
        SampleRate = sampleRate;
        _smoothing = 1.0 - Math.Exp(-1.0 / Math.Max(1.0, rampSeconds * sampleRate));
    }

    // Volatile double stores and per-sample gain smoothing: the audio thread takes no lock.
    public void Render(Span<float> buffer)
    {
        var nyquist = SampleRate * 0.45;
        var inc = Math.Min(Frequency, nyquist) / SampleRate;
        var g = Gain;
        var p = Phase;
        var target = TargetGain;
        var a = _smoothing;

        for (var i = 0; i < buffer.Length; i++)
        {
            g += (target - g) * a;
            buffer[i] = (float)(Math.Sin(2.0 * Math.PI * p) * g);
            p += inc;
            if (p >= 1.0) p -= 1.0;
        }

        Gain = g;
        Phase = p;
    }
}
