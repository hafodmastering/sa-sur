// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

using System.Runtime.InteropServices;
using NAudio.Wave;

namespace SaSur.Audio;

public sealed class FloatWaveProvider : IWaveProvider
{
    private readonly ISampleProvider _source;
    private float[] _scratch = new float[8192];

    public FloatWaveProvider(ISampleProvider source)
    {
        _source = source;
        WaveFormat = source.WaveFormat;
    }

    public WaveFormat WaveFormat { get; }

    public int Read(Span<byte> buffer)
    {
        var wantFloats = buffer.Length / sizeof(float);
        if (wantFloats <= 0)
        {
            return 0;
        }

        if (_scratch.Length < wantFloats)
        {
            _scratch = new float[wantFloats];
        }

        var got = _source.Read(_scratch.AsSpan(0, wantFloats));
        if (got <= 0)
        {
            return 0;
        }

        var bytes = MemoryMarshal.AsBytes(_scratch.AsSpan(0, got));
        bytes.CopyTo(buffer);
        return bytes.Length;
    }
}
