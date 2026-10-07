// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

using System.Globalization;
using SaSur.Core;
using Xunit;

namespace SaSur.Tests;

public class NoteMathTests
{

    [Fact]
    public void A4_is_the_reference_pitch()
        => Approx.Equal(440.0, NoteMath.Frequency(midi: 69, a4: 440), 1e-9, "A4 = 440");

    [Fact]
    public void Anchor_notes_match_the_macOS_build()
    {
        Approx.Equal(261.6255653005986, NoteMath.Frequency(octave: 4, semitone: 0, a4: 440), 1e-9, "C4");
        Approx.Equal(16.351597831287414, NoteMath.Frequency(octave: 0, semitone: 0, a4: 440), 1e-9, "C0");
        Approx.Equal(65.40639132514966, NoteMath.Frequency(octave: 2, semitone: 0, a4: 440), 1e-9, "C2");
    }

    [Fact]
    public void Midi_numbers_follow_scientific_pitch_notation()
    {
        Approx.Int(60, NoteMath.MidiNumber(octave: 4, semitone: 0), "C4 -> 60");
        Approx.Int(69, NoteMath.MidiNumber(octave: 4, semitone: 9), "A4 -> 69");
        Approx.Int(12, NoteMath.MidiNumber(octave: 0, semitone: 0), "C0 -> 12");
        Approx.Int(0, NoteMath.MidiNumber(octave: -1, semitone: 0), "C-1 -> 0");
    }

    [Fact]
    public void Every_octave_doubles_exactly()
    {
        for (var o = 0; o < 8; o++)
        {
            var low = NoteMath.Frequency(octave: o, semitone: 9, a4: 440);
            var high = NoteMath.Frequency(octave: o + 1, semitone: 9, a4: 440);
            Approx.Equal(2.0, high / low, 1e-12, $"A{o} -> A{o + 1} doubles");
        }
    }

    [Fact]
    public void Semitone_ratio_is_the_twelfth_root_of_two()
    {
        var ratio = NoteMath.Frequency(octave: 4, semitone: 10, a4: 440)
                  / NoteMath.Frequency(octave: 4, semitone: 9, a4: 440);
        Approx.Equal(Math.Pow(2.0, 1.0 / 12.0), ratio, 1e-12, "Bb4 / A4");
    }

    [Fact]
    public void Concert_A_presets_retune_the_whole_table()
    {
        Approx.Equal(432.0, NoteMath.Frequency(octave: 4, semitone: 9, a4: 432), 1e-9, "A4 at 432");
        Approx.Equal(432.0 * Math.Pow(2.0, -9.0 / 12.0),
                     NoteMath.Frequency(octave: 4, semitone: 0, a4: 432), 1e-12, "C4 at 432");
        Approx.Equal(415.0, NoteMath.Frequency(octave: 4, semitone: 9, a4: 415), 1e-9, "A4 at 415");
        Approx.Equal(442.0, NoteMath.Frequency(octave: 4, semitone: 9, a4: 442), 1e-9, "A4 at 442");
    }

    [Theory]
    [InlineData(0, "262")]
    [InlineData(1, "261.6")]
    [InlineData(2, "261.63")]
    [InlineData(3, "261.626")]
    public void Formatter_uses_the_requested_decimal_places(int decimals, string expected)
        => Assert.Equal(expected, NoteMath.Formatted(261.6255653005986, decimals));

    [Fact]
    public void Formatter_clamps_decimals_to_the_UI_range()
    {
        Assert.Equal("262", NoteMath.Formatted(261.63, -3));
        Assert.Equal("261.625565", NoteMath.Formatted(261.6255653, 99));
    }

    [Fact]
    public void Formatter_is_culture_invariant_even_on_a_comma_decimal_machine()
    {
        var original = CultureInfo.CurrentCulture;
        try
        {
            CultureInfo.CurrentCulture = new CultureInfo("de-DE");
            Assert.Equal("440.00", NoteMath.Formatted(440.0, 2));
            Assert.Equal("440", NoteMath.Formatted(440.0, 0));
            Assert.Equal("466.16", NoteMath.Formatted(466.1637615180899, 2));
        }
        finally
        {
            CultureInfo.CurrentCulture = original;
        }
    }

    [Fact]
    public void Labels_use_the_sharp_and_flat_spellings_from_the_button_row()
    {
        Assert.Equal("C4", NoteMath.Label(4, 0));
        Assert.Equal("Bb4", NoteMath.Label(4, 10));
        Assert.Equal("Eb0", NoteMath.Label(0, 3));
        Assert.Equal(12, NoteMath.NoteNames.Length);
        Assert.Equal(["C", "C#", "D", "Eb", "E", "F", "F#", "G", "G#", "A", "Bb", "B"], NoteMath.NoteNames);
        Assert.Equal([0, 1, 2, 3, 4, 5, 6, 7, 8], NoteMath.Octaves);
    }
}
