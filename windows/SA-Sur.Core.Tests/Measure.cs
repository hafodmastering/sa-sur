// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

namespace SaSur.Testing;

internal static class Measurement
{
    public static (double Freq, int Cycles, double Peak) Measure(float[] buf, int from, double sampleRate)
    {
        var crossings = new List<double>();
        var peak = 0.0;

        for (var n = from; n < buf.Length; n++)
        {
            var v = (double)buf[n];
            peak = Math.Max(peak, Math.Abs(v));
            if (n > from)
            {
                var prev = (double)buf[n - 1];
                if (prev < 0 && v >= 0)
                {
                    var frac = prev == v ? 0 : -prev / (v - prev);
                    crossings.Add(n - 1 + frac);
                }
            }
        }

        if (crossings.Count < 2)
        {
            return (0, crossings.Count, peak);
        }

        var first = crossings[0];
        var last = crossings[^1];
        if (last <= first)
        {
            return (0, crossings.Count, peak);
        }

        return ((crossings.Count - 1) / (last - first) * sampleRate, crossings.Count, peak);
    }

    public static double Peak(float[] buf, int from, int to)
    {
        var peak = 0.0;
        for (var n = Math.Max(0, from); n < Math.Min(buf.Length, to); n++)
        {
            peak = Math.Max(peak, Math.Abs((double)buf[n]));
        }
        return peak;
    }
}
