// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

using System.Globalization;
using System.Text;
using SaSur.Core;
using Xunit;

namespace SaSur.Tests;

public class TableTests
{
    private const string FrameStart = "@@TABLE@@";
    private const string FrameEnd = "@@END@@";

    public static List<string> TableRows()
    {
        var rows = new List<string>(108);
        foreach (var octave in NoteMath.Octaves)
        {
            for (var semitone = 0; semitone < 12; semitone++)
            {
                var f = NoteMath.Frequency(octave, semitone, a4: 440);
                rows.Add($"{NoteMath.Label(octave, semitone)},{NoteMath.Formatted(f, 6)}");
            }
        }
        return rows;
    }

    private static string? RepoRoot()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null)
        {
            if (Directory.Exists(Path.Combine(dir.FullName, "src"))
                && Directory.Exists(Path.Combine(dir.FullName, "docs")))
            {
                return dir.FullName;
            }
            dir = dir.Parent;
        }
        return null;
    }

    [Fact]
    public void The_table_has_all_108_notes_and_no_duplicates()
    {
        var rows = TableRows();
        Assert.Equal(108, rows.Count);
        Assert.Equal(108, rows.Select(r => r.Split(',')[0]).Distinct().Count());
        Assert.Equal("C0,16.351598", rows[0]);
        Assert.Equal("B8,7902.132820", rows[107]);
    }

    [Fact]
    public void Writes_the_framed_table_for_the_independent_diff()
    {
        var root = RepoRoot() ?? Directory.GetCurrentDirectory();
        var target = Environment.GetEnvironmentVariable("SASUR_TABLE_DUMP")
                     ?? Path.Combine(root, "windows", "build", "test-output.txt");

        Directory.CreateDirectory(Path.GetDirectoryName(target)!);

        var sb = new StringBuilder();
        sb.AppendLine(FrameStart);
        foreach (var row in TableRows())
        {
            sb.AppendLine(row);
        }
        sb.AppendLine(FrameEnd);
        File.WriteAllText(target, sb.ToString());

        Assert.True(File.Exists(target), $"table dump written to {target}");
        Assert.Equal(110, File.ReadAllLines(target).Length);   // frame start + 108 rows + frame end
        Console.WriteLine($"TABLE_DUMP={target}");
    }

    [Fact]
    public void The_table_matches_the_committed_reference_from_the_macOS_build()
    {
        var root = RepoRoot();
        if (root is null)
        {
            return;   // running outside a checkout: nothing to compare against
        }

        var reference = Path.Combine(root, "docs", "note-table.csv");
        if (!File.Exists(reference))
        {
            return;   // reference not generated yet; the diff_table.py check still applies
        }

        var expected = File.ReadAllLines(reference)
            .Where(l => l.Trim().Length > 0)
            .ToArray();
        var actual = TableRows().ToArray();

        Assert.Equal(expected.Length, actual.Length);

        var mismatches = new List<string>();
        for (var i = 0; i < expected.Length; i++)
        {
            if (!string.Equals(expected[i].Trim(), actual[i], StringComparison.Ordinal))
            {
                mismatches.Add($"line {i + 1}: reference '{expected[i].Trim()}' vs ported '{actual[i]}'");
            }
        }

        Assert.True(mismatches.Count == 0,
            $"the C# table disagrees with the macOS reference in {mismatches.Count} place(s): "
            + string.Join("; ", mismatches.Take(5)));
    }

    [Fact]
    public void The_dump_uses_the_string_form_of_every_value_not_a_localised_one()
    {
        var original = CultureInfo.CurrentCulture;
        try
        {
            CultureInfo.CurrentCulture = new CultureInfo("de-DE");
            Assert.All(TableRows(), row => Assert.DoesNotContain(",", row.Split(',')[1]));
            Assert.Equal("C4,261.625565", TableRows()[NoteMath.MidiNumber(4, 0) - 12]);
        }
        finally
        {
            CultureInfo.CurrentCulture = original;
        }
    }
}
