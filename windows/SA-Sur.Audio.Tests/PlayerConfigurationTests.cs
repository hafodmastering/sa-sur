// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

using SaSur.Core;
using Xunit;
using Xunit.Abstractions;

namespace SaSur.Audio.Tests;

public class PlayerConfigurationTests
{
    public PlayerConfigurationTests(ITestOutputHelper output) => Output = output;

    private ITestOutputHelper Output { get; }

    [Fact]
    public async Task The_configuration_the_app_plays_through_is_accepted_by_naudio()
    {
        var failure = await Record.ExceptionAsync(async () =>
        {
            var source = new FloatWaveProvider(new OscillatorProvider(new SineOscillator(48000), 48000, 2));
            var (player, routed, raw) = await ToneGenerator.OpenOutputAsync(source);
            using (player)
            {
                Output.WriteLine($"opened: routing={routed}, endpoint processing bypassed={raw}");
            }
        });

        Output.WriteLine(failure is null
            ? "the output opened on this machine"
            : $"{failure.GetType().Name}: {Compress(failure.Message)}");

        Assert.False(
            failure is not null && IsConfigurationRefusal(failure.Message),
            $"NAudio refused the app's own configuration: {Compress(failure?.Message ?? string.Empty)}");
    }

    [Fact]
    public async Task Play_never_shows_the_user_a_configuration_refusal()
    {
        using var gen = new ToneGenerator(48000, 2);

        var announced = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        gen.StateChanged += (_, _) => announced.TrySetResult();

        gen.Play();
        await announced.Task.WaitAsync(TimeSpan.FromSeconds(20));

        Output.WriteLine($"running={gen.IsRunning}  problem={(gen.Problem is null ? "(none)" : gen.Problem)}");

        if (gen.Problem is { } problem)
        {
            Assert.False(IsConfigurationRefusal(problem), $"the user was shown a configuration refusal: {problem}");
        }
    }

    private static bool IsConfigurationRefusal(string message) =>
        message.Contains("BuildAsync() instead of Build()", StringComparison.Ordinal)
        || message.Contains("not supported with automatic stream routing", StringComparison.Ordinal)
        || message.Contains("cannot be combined with WithDevice", StringComparison.Ordinal)
        || message.Contains("only available in shared mode", StringComparison.Ordinal);

    private static string Compress(string message) =>
        string.Join(' ', message.Split(['\r', '\n', '\t', ' '], StringSplitOptions.RemoveEmptyEntries));
}
