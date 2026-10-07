// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

using System.Runtime.InteropServices;
using SaSur.Core;
using SaSur.Testing;
using Xunit;

namespace SaSur.Audio.Tests;

public class FloatWaveProviderTests
{
    private static FloatWaveProvider Build(double gain = 0.22, double hz = 440)
    {
        var osc = new SineOscillator(48000) { Frequency = hz, TargetGain = gain };
        return new FloatWaveProvider(new OscillatorProvider(osc, 48000, 2));
    }

    [Fact]
    public void It_reports_the_sources_format_unchanged()
    {
        var wave = Build();

        Assert.Equal(48000, wave.WaveFormat.SampleRate);
        Assert.Equal(2, wave.WaveFormat.Channels);
        Assert.Equal(32, wave.WaveFormat.BitsPerSample);
    }

    [Fact]
    public void Read_returns_four_bytes_per_float_and_writes_every_frame()
    {
        var wave = Build();

        var bytes = new byte[400];            // 100 floats = 50 stereo frames
        var got = wave.Read(bytes);

        Assert.Equal(400, got);
        var floats = MemoryMarshal.Cast<byte, float>(bytes);
        Assert.Equal(100, floats.Length);
    }

    [Fact]
    public void The_interleave_puts_the_same_sample_in_both_channels()
    {
        var wave = Build();
        var bytes = new byte[8192];
        wave.Read(bytes);

        var floats = MemoryMarshal.Cast<byte, float>(bytes);
        for (var f = 0; f < floats.Length / 2; f++)
        {
            Assert.Equal(floats[f * 2], floats[f * 2 + 1]);
        }
    }

    [Fact]
    public void The_bytes_decode_back_to_the_measured_tone()
    {
        var wave = Build();
        var bytes = new byte[8192];

        for (var i = 0; i < 12; i++)
        {
            wave.Read(bytes);
        }

        var floats = MemoryMarshal.Cast<byte, float>(bytes);
        var mono = new float[floats.Length / 2];
        for (var f = 0; f < mono.Length; f++)
        {
            mono[f] = floats[f * 2];
        }

        var measured = Measurement.Measure(mono, 100, 48000);

        Assert.True(Math.Abs(measured.Freq - 440) <= 1.0,
            $"the decoded bytes should still be the 440 Hz tone, measured {measured.Freq:R}");
        Assert.True(Math.Abs(measured.Peak - 0.22) <= 0.001,
            $"peak after the byte round trip: {measured.Peak:R}");
    }

    [Fact]
    public void A_partial_frame_is_never_emitted()
    {
        var wave = Build();

        Assert.Equal(0, wave.Read(new byte[7]));

        Assert.Equal(8, wave.Read(new byte[8]));
    }

    [Fact]
    public void Read_allocates_nothing_on_the_audio_thread_once_warm()
    {
        var wave = Build();
        var bytes = new byte[8192];

        for (var i = 0; i < 8; i++)
        {
            wave.Read(bytes);                  // let both scratch buffers reach full size
        }

        var before = GC.GetAllocatedBytesForCurrentThread();
        for (var i = 0; i < 200; i++)
        {
            wave.Read(bytes);
        }
        var after = GC.GetAllocatedBytesForCurrentThread();

        Assert.True(after == before,
            $"200 reads should allocate nothing, but allocated {after - before} bytes");
    }
}
