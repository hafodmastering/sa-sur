// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

using Xunit;

namespace SaSur.Tests;

internal static class Approx
{
    public static void Equal(double expected, double actual, double tol, string label)
    {
        var delta = Math.Abs(actual - expected);
        Assert.True(delta <= tol,
            $"{label}: expected {expected:R} ± {tol:R}, got {actual:R} (delta {delta:R})");
    }

    public static void True(bool condition, string label)
        => Assert.True(condition, label);

    public static void Int(int expected, int actual, string label)
        => Assert.True(expected == actual, $"{label}: expected {expected}, got {actual}");
}
