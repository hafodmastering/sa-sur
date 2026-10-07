// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

using SaSur.Core;
using static SaSur.Testing.Measurement;
using Xunit;
using Xunit.Abstractions;

namespace SaSur.Audio.Tests;

public class AudioMeasurementTests
{
    private const int Rate = 48000;
    private const int Channels = 2;
    private const double TestGain = 0.22;

    public AudioMeasurementTests(ITestOutputHelper output) => Output = output;

    private ITestOutputHelper Output { get; }

    [Theory]
    [InlineData(4, 9)]    // A4 440
    [InlineData(0, 0)]    // C0 16.3516
    [InlineData(8, 11)]   // B8 7902.13
    public void The_tone_measures_the_same_through_the_audio_path(int octave, int semitone)
    {
        using var gen = new ToneGenerator(Rate, Channels);
        var target = NoteMath.Frequency(octave, semitone, a4: 440);
        gen.SetFrequency(target);

        var (left, right, rate, channels) = gen.MeasureOffline(5.0, TestGain);

        Assert.Equal(Rate, rate);
        Assert.Equal(Channels, channels);
        Assert.Equal(240_000, left.Length);
        Assert.Equal(left.Length, right.Length);

        var measured = Measure(left, (int)(Rate * 0.05), Rate);
        var label = NoteMath.Label(octave, semitone);
        Output.WriteLine($"{label}: measured {measured.Freq:F5} Hz over {measured.Cycles} cycles, peak {measured.Peak:F5}");

        Assert.True(Math.Abs(measured.Freq - target) <= Math.Max(0.01, target * 1e-5),
            $"{label} rendered frequency: expected {target:R}, got {measured.Freq:R}");
        Assert.True(Math.Abs(measured.Peak - TestGain) <= 0.0005,
            $"{label} peak amplitude: expected {TestGain}, got {measured.Peak:R}");
    }

    [Fact]
    public void Both_channels_carry_bit_identical_samples()
    {
        using var gen = new ToneGenerator(Rate, Channels);
        gen.SetFrequency(440);

        var (left, right, _, _) = gen.MeasureOffline(0.25, TestGain);

        Assert.Equal(left.Length, right.Length);
        for (var i = 0; i < left.Length; i++)
        {
            Assert.Equal(left[i], right[i]);
        }
    }

    [Fact]
    public void The_headroom_ceiling_is_the_only_gain_stage()
    {
        Assert.Equal(0.11, ToneGenerator.Headroom, 12);

        using var gen = new ToneGenerator(Rate, Channels);
        gen.SetFrequency(440);

        var (left, _, _, _) = gen.MeasureOffline(0.25, ToneGenerator.Headroom);
        var peak = Peak(left, 0, left.Length);

        Assert.True(Math.Abs(peak - ToneGenerator.Headroom) <= 0.0005,
            $"a full slider should peak at {ToneGenerator.Headroom:R} FS, measured {peak:R}");
    }

    [Fact]
    public void A_stopped_generator_renders_silence()
    {
        using var gen = new ToneGenerator(Rate, Channels);
        gen.SetFrequency(440);

        var (left, _, _, _) = gen.MeasureOffline(0.05, 0.0);

        Assert.Equal(0.0, Peak(left, 0, left.Length));
    }

    [Fact]
    public void The_volume_slider_is_clamped_to_its_range()
    {
        using var gen = new ToneGenerator(Rate, Channels);

        gen.Volume = 2.0;
        Assert.Equal(1.0, gen.Volume);

        gen.Volume = -1.0;
        Assert.Equal(0.0, gen.Volume);

        gen.Volume = 0.5;
        Assert.Equal(0.5, gen.Volume);
    }

    [Fact]
    public void A_cold_start_is_silent_through_the_provider()
    {
        using var gen = new ToneGenerator(Rate, Channels);
        gen.SetFrequency(440);

        var (left, _, _, _) = gen.MeasureOffline(0.01, TestGain);

        Assert.Equal(0f, left[0]);
    }

    [Fact]
    public void Coverage_is_the_whole_requested_duration_and_not_a_partial_buffer()
    {
        using var gen = new ToneGenerator(Rate, Channels);
        gen.SetFrequency(440);

        var (left, right, _, _) = gen.MeasureOffline(0.1, TestGain);

        Assert.Equal(4800, left.Length);
        Assert.Equal(4800, right.Length);
    }

    [Fact]
    public void The_volume_law_is_the_macos_builds_law()
    {
        double[] positions = [0.0, 0.25, 0.5, 0.75, 1.0];
        foreach (var position in positions)
        {
            Assert.Equal(ToneGenerator.Headroom * position, ToneGenerator.GainFor(position), 12);
        }

        Assert.Equal(0.0, ToneGenerator.GainFor(-1.0));
        Assert.Equal(ToneGenerator.Headroom, ToneGenerator.GainFor(2.0));

        var previous = -1.0;
        for (var i = 0; i <= 100; i++)
        {
            var gain = ToneGenerator.GainFor(i / 100.0);
            Assert.True(gain > previous, $"the gain fell or stalled at slider {i}");
            if (i > 0)
            {
                Assert.True(gain > 0.0, "only a zero slider may be silent");
            }

            previous = gain;
        }

        Output.WriteLine("top half of the travel spans "
            + $"{20 * Math.Log10(ToneGenerator.GainFor(1.0) / ToneGenerator.GainFor(0.5)):F1} dB, "
            + "as it does on the Mac");
    }
}
