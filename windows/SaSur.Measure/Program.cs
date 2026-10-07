// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

using System.Diagnostics;
using System.Runtime.InteropServices;
using NAudio.CoreAudioApi;
using NAudio.Wave;
using SaSur.Audio;
using SaSur.Core;

namespace SaSur.Measure;

internal static class Program
{
    private static int Main(string[] args)
    {
        Console.WriteLine("SA-Sur measure - what actually comes out of the device");
        Console.WriteLine($"{Environment.MachineName}, {RuntimeInformation.OSDescription}");
        Console.WriteLine();

        Heading("1. the device");
        var present = ToneGenerator.HasRenderDevice();
        var (mixRate, mixChannels) = ToneGenerator.DeviceFormat();

        Console.WriteLine($"render endpoint present : {present}");
        Console.WriteLine($"device mix format       : {mixRate} Hz, {mixChannels} channel(s)");

        using var tone = new ToneGenerator();
        Console.WriteLine($"oscillator              : {tone.SampleRate} Hz, {tone.Channels} channel(s)");
        Console.WriteLine($"volume law              : gain = position x {ToneGenerator.Headroom} (the macOS law)");

        if (!present)
        {
            Console.WriteLine();
            Console.WriteLine("No render endpoint, so there is nothing to measure: the app reports exactly that");
            Console.WriteLine("in its window instead of playing. (The normal answer on a VM or a Server SKU.)");
            return 0;
        }

        var started = NextState(tone);
        tone.Play();
        if (!started.Wait(TimeSpan.FromSeconds(20)))
        {
            Console.WriteLine();
            Console.WriteLine($"Play never announced a state change. Problem: {tone.Problem ?? "(none)"}");
            return 1;
        }

        Console.WriteLine();
        Console.WriteLine($"playing                 : {tone.IsRunning}");
        Console.WriteLine($"problem                 : {tone.Problem ?? "(none)"}");
        Console.WriteLine($"opened by               : {(tone.UsingStreamRouting ? "stream routing" : "bound to the default device")}"
                          + $", endpoint processing {(tone.UsingRawMode ? "BYPASSED (raw)" : "left ON")}");
        Console.WriteLine($"device                  : {tone.DeviceName ?? "(following the default device)"}");
        Console.WriteLine($"negotiated latency      : {tone.NegotiatedLatencyMilliseconds} ms");

        if (!tone.UsingRawMode)
        {
            Console.WriteLine();
            Console.WriteLine("!! The endpoint's processing is on for this stream, so the machine may be levelling,");
            Console.WriteLine("!! equalising or downmixing what follows. Read section 2 with that in mind.");
        }

        using var loop = new Loopback();
        Console.WriteLine($"loopback capture        : {loop.SampleRate} Hz, {loop.Channels} channel(s), "
                          + $"{loop.WaveFormat.Encoding}, {loop.WaveFormat.BitsPerSample}-bit");

        tone.SetFrequency(440);

        Heading("2. the volume law, measured at the endpoint");
        Console.WriteLine("A linear law means each step down is 20*log10 of the position ratio. Each position is");
        Console.WriteLine("measured from a fresh start after a full second, so that anything the endpoint does over");
        Console.WriteLine("time is not read as part of the law: a leveller or AGC fighting a *change* is exactly");
        Console.WriteLine("what a slider feels like while it is being dragged, and this separates the two.");
        Console.WriteLine();
        Console.WriteLine("position      level RMS      step    expected     delta");

        double[] positions = [1.0, 0.75, 0.5, 0.25, 0.1];
        double? previousLevel = null;
        double? previousPosition = null;

        foreach (var position in positions)
        {
            tone.Stop();
            tone.Volume = position;
            Thread.Sleep(250);
            loop.Take();
            tone.Play();
            Thread.Sleep(1000);                 // settled: the 12 ms ramp plus a second of the machine
            var window = loop.Take();
            var level = Level(window);

            var step = previousLevel is null ? null : (double?)(level - previousLevel.Value);
            var expected = previousPosition is null ? null : (double?)20 * Math.Log10(position / previousPosition.Value);
            var delta = step is null || expected is null ? null : (double?)(step.Value - expected.Value);

            Console.WriteLine($"{position,8:F3}   {level,9:F2} dB  "
                + $"{Describe(step)}   {Describe(expected)}   {Describe(delta)}");

            previousLevel = level;
            previousPosition = position;
        }

        Heading("3. the attack - the reported two-second fade");
        tone.Volume = 0.25;
        tone.Stop();
        Thread.Sleep(250);
        loop.Take();
        tone.Play();

        var attack = new List<float>();
        var clock = Stopwatch.StartNew();
        while (clock.ElapsedMilliseconds < 1500)
        {
            attack.AddRange(loop.Take());
            Thread.Sleep(15);
        }

        var samples = attack.ToArray();
        var seconds = samples.Length / (double)loop.SampleRate;
        var settledFrom = Math.Max(0, samples.Length - (int)(loop.SampleRate * 0.2));
        var settledDb = Level(samples[settledFrom..]);

        Console.WriteLine($"captured {seconds:F2} s at slider 0.250; settled level {settledDb:F2} dBFS");
        Console.WriteLine();
        Console.WriteLine("  time      level RMS");

        var block = loop.SampleRate / 40;       // 25 ms
        int? riseBlock = null;
        for (var start = 0; start + block <= samples.Length && start < loop.SampleRate / 4; start += block)
        {
            var db = Level(samples[start..(start + block)]);
            var index = start / block;
            var reached = db >= settledDb - 1.0;
            riseBlock ??= reached ? index : null;

            var marker = riseBlock == index ? "   <- within 1 dB of settled" : "";
            Console.WriteLine($"{((start + (block / 2)) * 1000.0 / loop.SampleRate),6:F0} ms   {db,7:F2} dB{marker}");
        }

        if (riseBlock is not null)
        {
            Console.WriteLine();
            Console.WriteLine($"rise to within 1 dB    : about {(riseBlock.Value + 1) * 25} ms");
        }

        Heading("4. restart cycles - one client, or a leak");
        tone.Volume = 0.5;
        double? firstLevel = null;

        for (var cycle = 1; cycle <= 6; cycle++)
        {
            tone.Stop();
            Thread.Sleep(120);
            tone.Play();
            Thread.Sleep(320);
            loop.Take();
            Thread.Sleep(300);

            var level = Level(loop.Take());
            firstLevel ??= level;

            Console.WriteLine($"cycle {cycle}: playing={tone.IsRunning,-5} level={level,7:F2} dB  "
                + $"opened={tone.PlayersOpened} live={tone.LivePlayers}  "
                + $"first cycle was {firstLevel.Value:F2} dB");
        }

        Console.WriteLine();
        Console.WriteLine($"players opened in total : {tone.PlayersOpened} (1 is correct: restarting is a gain change)");
        Console.WriteLine($"live players            : {tone.LivePlayers} (more than 1 means shared DSP state)");

        Heading("5. the tone at the device");
        tone.Volume = 1.0;

        (int Octave, int Semitone)[] notes = [(4, 9), (5, 9), (3, 9), (0, 0)];
        foreach (var (octave, semitone) in notes)
        {
            var requested = NoteMath.Frequency(octave, semitone, a4: 440);
            tone.SetFrequency(requested);
            tone.Stop();
            Thread.Sleep(120);
            tone.Play();
            Thread.Sleep(250);
            loop.Take();
            Thread.Sleep(800);

            var window = loop.Take();
            var measured = Frequency(window, loop.SampleRate);
            var peakDb = 20 * Math.Log10(Math.Max(Peak(window), 1e-12));

            Console.WriteLine($"{NoteMath.Label(octave, semitone),4}  requested {requested,10:F4} Hz   "
                + $"measured {measured,10:F3} Hz   peak {peakDb,7:F2} dBFS");
        }

        Heading("done");
        return 0;
    }

    private static void Heading(string text)
    {
        Console.WriteLine();
        Console.WriteLine($"=== {text} ===");
    }

    private static Task NextState(IToneOutput tone)
    {
        var announced = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);

        void OnStateChanged(object? sender, EventArgs e)
        {
            tone.StateChanged -= OnStateChanged;
            announced.TrySetResult();
        }

        tone.StateChanged += OnStateChanged;
        return announced.Task;
    }

    private static string Describe(double? value) => value is null ? "      -" : $"{value.Value,7:F2}";

    private static double Level(float[] window)
    {
        if (window.Length == 0)
        {
            return double.NaN;
        }

        double sum = 0;
        foreach (var sample in window)
        {
            sum += (double)sample * sample;
        }

        return 20 * Math.Log10(Math.Max(Math.Sqrt(sum / window.Length), 1e-12));
    }

    private static double Peak(float[] window)
    {
        var peak = 0.0;
        foreach (var sample in window)
        {
            peak = Math.Max(peak, Math.Abs(sample));
        }

        return peak;
    }

    private static double Frequency(float[] window, int sampleRate)
    {
        if (window.Length < 2 || sampleRate <= 0)
        {
            return double.NaN;
        }

        var threshold = Peak(window) * 0.3;
        var below = true;
        var crossings = 0;
        var first = -1;
        var last = -1;

        for (var i = 0; i < window.Length; i++)
        {
            if (below && window[i] > threshold)
            {
                below = false;
                crossings++;
                first = first < 0 ? i : first;
                last = i;
            }
            else if (!below && window[i] < -threshold)
            {
                below = true;
            }
        }

        if (crossings < 2 || last <= first)
        {
            return double.NaN;
        }

        return (crossings - 1) * (double)sampleRate / (last - first);
    }

    private sealed class Loopback : IDisposable
    {
        private readonly WasapiRecorder _recorder;
        private readonly List<float> _samples = [];
        private readonly object _gate = new();
        private bool _warned;

        public Loopback()
        {
            _recorder = new WasapiRecorderBuilder()
                .WithLoopbackCapture()          // no device set: the default render endpoint
                .WithRawMode()                  // and do not let the *capture* chain process it either
                .WithBufferLength(50)
                .Build();

            WaveFormat = _recorder.WaveFormat;
            _recorder.DataAvailable += OnDataAvailable;
            _recorder.StartRecording();
            Thread.Sleep(250);                  // let the first callbacks land
        }

        public WaveFormat WaveFormat { get; }

        public int SampleRate => WaveFormat.SampleRate;

        public int Channels => Math.Max(1, WaveFormat.Channels);

        public float[] Take()
        {
            lock (_gate)
            {
                var taken = _samples.ToArray();
                _samples.Clear();
                return taken;
            }
        }

        private void OnDataAvailable(
            ReadOnlySpan<byte> buffer,
            AudioClientBufferFlags flags,
            long devicePosition,
            long qpcPosition)
        {
            var format = WaveFormat;
            var channels = Channels;

            var isFloat = format.Encoding == WaveFormatEncoding.IeeeFloat
                || (format is WaveFormatExtensible ext
                    && ext.SubFormat == AudioMediaSubtypes.MEDIASUBTYPE_IEEE_FLOAT);

            lock (_gate)
            {
                if (isFloat && format.BitsPerSample == 32)
                {
                    for (var at = 0; at + 4 <= buffer.Length; at += 4 * channels)
                    {
                        _samples.Add(BitConverter.ToSingle(buffer[at..]));
                    }

                    return;
                }

                if (!isFloat && format.BitsPerSample == 16)
                {
                    for (var at = 0; at + 2 <= buffer.Length; at += 2 * channels)
                    {
                        _samples.Add(BitConverter.ToInt16(buffer[at..]) / 32768f);
                    }

                    return;
                }

                if (!_warned)
                {
                    _warned = true;
                    Console.WriteLine($"!! unhandled loopback format: {format} (float={isFloat})");
                }
            }
        }

        public void Dispose()
        {
            try
            {
                _recorder.StopRecording();
            }
            catch
            {
            }

            _recorder.Dispose();
        }
    }
}
