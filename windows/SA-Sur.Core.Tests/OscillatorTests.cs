// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

using SaSur.Core;
using static SaSur.Testing.Measurement;
using Xunit;
using Xunit.Abstractions;

namespace SaSur.Tests;

public class OscillatorTests
{
    private const double SampleRate = 48000.0;
    private const double TestGain = 0.22;

    public OscillatorTests(ITestOutputHelper output) => Output = output;

    private ITestOutputHelper Output { get; }

    [Theory]
    [InlineData(2, 0)]    // C2  65.4064
    [InlineData(4, 9)]    // A4  440
    [InlineData(5, 6)]    // F#5 739.9888
    [InlineData(0, 0)]    // C0  16.3516
    [InlineData(8, 11)]   // B8  7902.13
    public void Rendered_frequency_and_peak_match_the_requested_note(int octave, int semitone)
    {
        var target = NoteMath.Frequency(octave, semitone, a4: 440);
        var osc = new SineOscillator(SampleRate) { Frequency = target, TargetGain = TestGain };

        var buf = new float[(int)(SampleRate * 5.0)];
        osc.Render(buf);

        var measured = Measure(buf, (int)(SampleRate * 0.05), SampleRate);
        var label = NoteMath.Label(octave, semitone);

        Approx.Equal(target, measured.Freq, Math.Max(0.01, target * 1e-5), $"{label} rendered frequency");
        Approx.Equal(TestGain, measured.Peak, 0.0005, $"{label} peak amplitude");
    }

    [Fact]
    public void Start_leaves_silence_smoothly_with_no_step_discontinuity()
    {
        var osc = new SineOscillator(SampleRate) { Frequency = 440, TargetGain = TestGain };
        var buf = new float[480];
        osc.Render(buf);

        Approx.Equal(0.0, buf[0], 1e-6, "first sample is silent (no click)");

        var maxStep = 0.0;
        for (var n = 1; n < buf.Length; n++)
        {
            maxStep = Math.Max(maxStep, Math.Abs(buf[n] - buf[n - 1]));
        }

        var theoretical = 2.0 * Math.PI * 440.0 / SampleRate * TestGain * 2.0;
        Approx.True(maxStep < theoretical,
            $"no start discontinuity: max step {maxStep:R} vs bound {theoretical:R}");
    }

    [Fact]
    public void Pitch_change_mid_stream_does_not_click()
    {
        var osc = new SineOscillator(SampleRate) { Frequency = 220, TargetGain = TestGain };

        const int chunk = 9600;
        osc.Render(new float[chunk]);      // settled at 220 Hz, phase carried
        osc.Frequency = 880;

        var after = new float[chunk];
        osc.Render(after);

        var maxStep = 0.0;
        for (var n = 1; n < after.Length; n++)
        {
            maxStep = Math.Max(maxStep, Math.Abs(after[n] - after[n - 1]));
        }

        var theoretical = 2.0 * Math.PI * 880.0 / SampleRate * TestGain * 1.5;
        Approx.True(maxStep < theoretical,
            $"no discontinuity on pitch change: max step {maxStep:R} vs bound {theoretical:R}");
    }

    [Fact]
    public void Stop_fades_following_the_twelve_millisecond_one_pole()
    {
        var osc = new SineOscillator(SampleRate) { Frequency = 440, TargetGain = TestGain };

        const int chunk = 48000;
        osc.Render(new float[chunk]);      // fully settled at target gain
        osc.TargetGain = 0.0;

        var fade = new float[chunk];
        osc.Render(fade);                  // the fade region

        double Peak(double from, double to)
        {
            var p = 0.0;
            for (var n = (int)(SampleRate * from); n < Math.Min(chunk, (int)(SampleRate * to)); n++)
            {
                p = Math.Max(p, Math.Abs(fade[n]));
            }
            return p;
        }

        var firstWindow = Peak(0, 0.005);
        var at50 = Peak(0.050, 0.100);
        var at100 = Peak(0.100, 0.200);
        var predicted50 = TestGain * Math.Exp(-0.050 / 0.012);

        Approx.Equal(predicted50, at50, predicted50 * 0.25, "release follows the 12 ms one-pole");
        Approx.True(firstWindow > 0.10 && firstWindow <= 0.2201,
            $"fade begins immediately, not an instant cut: peak in first 5 ms = {firstWindow:R}");

        var db50 = 20 * Math.Log10(at50 / TestGain);
        Approx.True(db50 < -35, $"at least 35 dB down 50 ms after stop (measured {db50:F1} dBFS)");
        Approx.True(at100 < 1e-4, $"inaudible (<-66 dB) within 100 ms (measured {at100:R})");
        Approx.Equal(0.0, osc.Gain, 1e-9, "gain reached zero");
    }

    [Fact]
    public void Absurd_frequencies_are_clamped_below_nyquist()
    {
        var osc = new SineOscillator(SampleRate) { Frequency = 40000, TargetGain = TestGain };
        var buf = new float[48000];
        osc.Render(buf);

        var measured = Measure(buf, 2400, SampleRate);
        Approx.Equal(SampleRate * 0.45, measured.Freq, 0.5,
            $"requested 40000 Hz -> clamped to 0.45 * sample rate (measured {measured.Freq:F3})");
    }

    [Fact]
    public void Render_consumes_exactly_the_buffer_it_is_given()
    {
        var osc = new SineOscillator(SampleRate) { Frequency = 440, TargetGain = TestGain };
        osc.Render(new float[1000]);
        var phaseAfterFirst = osc.Phase;

        osc.Render(new float[10]);
        Approx.True(osc.Phase != phaseAfterFirst, "phase carries across render calls");
    }

    [Fact]
    public void The_attack_reaches_the_target_in_tens_of_milliseconds()
    {
        var osc = new SineOscillator(SampleRate) { Frequency = 440, TargetGain = TestGain };

        var chunk = new float[(int)(SampleRate / 1000.0)];
        var trace = new List<(int Ms, double Gain)>();
        for (var ms = 1; ms <= 200; ms++)
        {
            osc.Render(chunk);
            trace.Add((ms, osc.Gain));
        }

        static int? Reaches(IEnumerable<(int Ms, double Gain)> trace, double level) =>
            trace.Where(t => t.Gain >= level).Select(t => (int?)t.Ms).FirstOrDefault();

        var at90 = Reaches(trace, TestGain * 0.90);
        var at99 = Reaches(trace, TestGain * 0.99);

        Output.WriteLine($"attack: 90% at {at90} ms, 99% at {at99} ms (12 ms one-pole)");

        Approx.True(at90 is not null, "the envelope reaches 90% within the 200 ms trace");
        Approx.True(at90 <= 40, $"90% of the target within 40 ms (took {at90} ms)");
        Approx.True(at99 is not null, "the envelope reaches 99% within the 200 ms trace");
        Approx.True(at99 <= 100, $"99% of the target within 100 ms (took {at99} ms)");

        Approx.Equal(TestGain, trace[^1].Gain, TestGain * 1e-4, "the envelope settles on the target");
    }
}
