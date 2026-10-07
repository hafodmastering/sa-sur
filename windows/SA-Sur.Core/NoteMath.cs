// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

using System.Globalization;

namespace SaSur.Core;

public static class NoteMath
{
    public static readonly string[] NoteNames =
        ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "G#", "A", "Bb", "B"];

    public static readonly int[] Octaves = [0, 1, 2, 3, 4, 5, 6, 7, 8];

    public static int MidiNumber(int octave, int semitone) => (octave + 1) * 12 + semitone;

    public static double Frequency(int midi, double a4) => a4 * Math.Pow(2.0, (midi - 69) / 12.0);

    public static double Frequency(int octave, int semitone, double a4 = 440.0)
        => Frequency(MidiNumber(octave, semitone), a4);

    public static string Label(int octave, int semitone)
        => NoteNames[semitone] + octave.ToString(CultureInfo.InvariantCulture);

    // Swift's String(format:) rounds ties half-to-even and .NET's "F<n>" ties away from zero. They
    // agree on all 108 values; TableTests keeps the difference from being silently "fixed".
    public static string Formatted(double value, int decimals)
        => value.ToString(
            "F" + Math.Clamp(decimals, 0, 6).ToString(CultureInfo.InvariantCulture),
            CultureInfo.InvariantCulture);
}
