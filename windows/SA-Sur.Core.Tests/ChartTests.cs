// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

using SaSur.Core;
using Xunit;

namespace SaSur.Tests;

public class ChartTests
{
    private static readonly Dictionary<int, int[]> Published = new()
    {
        [0] = [16, 33, 65, 131, 262, 523, 1047, 2093, 4186],   // C
        [1] = [17, 35, 69, 139, 277, 554, 1109, 2217, 4435],   // C#
        [2] = [18, 37, 73, 147, 294, 587, 1175, 2349, 4699],   // D
        [3] = [19, 39, 78, 156, 311, 622, 1245, 2489, 4978],   // Eb
        [4] = [21, 41, 82, 165, 330, 659, 1319, 2637, 5274],   // E
        [5] = [22, 44, 87, 175, 349, 698, 1397, 2794, 5588],   // F
        [6] = [23, 46, 93, 185, 370, 740, 1480, 2960, 5920],   // F#
        [7] = [25, 49, 98, 196],                               // G (published rows 0-3 only)
    };

    // The chart prints 93 for F#2 and 25 for G0; the true values (92.4986, 24.4997) round down.
    // Recorded, not matched - see the test below.
    private static readonly Dictionary<string, (int Published, int Correct)> ChartErrata = new()
    {
        ["F#2"] = (Published: 93, Correct: 92),
        ["G0"] = (Published: 25, Correct: 24),
    };

    [Fact]
    public void Rounded_values_match_the_published_chart_apart_from_the_documented_errata()
    {
        var compared = 0;
        var errataSeen = 0;
        var failures = new List<string>();

        foreach (var (semitone, row) in Published.OrderBy(kv => kv.Key))
        {
            for (var octave = 0; octave < row.Length; octave++)
            {
                var label = NoteMath.Label(octave, semitone);
                var mine = int.Parse(
                    NoteMath.Formatted(NoteMath.Frequency(octave, semitone, a4: 440), 0));
                var expected = row[octave];
                compared++;

                if (mine == expected)
                {
                    continue;
                }

                if (ChartErrata.TryGetValue(label, out var errata)
                    && errata.Published == expected
                    && errata.Correct == mine)
                {
                    errataSeen++;
                    continue;
                }

                failures.Add($"{label} = {mine}, published {expected}");
            }
        }

        Assert.Equal(67, compared);
        Assert.Equal(2, errataSeen);
        Assert.True(failures.Count == 0,
            $"compared {compared} published values, {errataSeen} documented errata, "
            + $"{failures.Count} unexpected: {string.Join("; ", failures)}");
    }

    // Stated as facts so a later edit to the maths cannot quietly "fix" them.
    [Fact]
    public void The_two_chart_errata_are_real_and_deliberate()
    {
        Approx.Equal(92.4986, NoteMath.Frequency(octave: 2, semitone: 6, a4: 440), 1e-4, "F#2");
        Assert.Equal("92", NoteMath.Formatted(NoteMath.Frequency(2, 6), 0));

        Approx.Equal(24.4997, NoteMath.Frequency(octave: 0, semitone: 7, a4: 440), 1e-4, "G0");
        Assert.Equal("24", NoteMath.Formatted(NoteMath.Frequency(0, 7), 0));
    }
}
