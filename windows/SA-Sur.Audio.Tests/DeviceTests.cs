// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

using SaSur.Core;
using Xunit;
using Xunit.Abstractions;

namespace SaSur.Audio.Tests;

public class DeviceTests
{
    public DeviceTests(ITestOutputHelper output) => Output = output;

    private ITestOutputHelper Output { get; }

    private static Task NextStateAsync(IToneOutput tone)
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

    [Fact]
    public void The_reported_device_format_is_always_usable()
    {
        var has = ToneGenerator.HasRenderDevice();
        var (rate, channels) = ToneGenerator.DeviceFormat();

        Output.WriteLine($"render endpoint present: {has}");
        Output.WriteLine($"device mix format: {rate} Hz, {channels} channel(s)");

        Assert.True(rate > 0, "a sample rate must always be reported, device or not");
        Assert.InRange(channels, 1, 2);

        if (!has)
        {
            Assert.Equal((48000, 2), (rate, channels));
        }
    }

    [Fact]
    public async Task Without_a_device_play_is_silent_and_explains_itself()
    {
        if (ToneGenerator.HasRenderDevice())
        {
            Output.WriteLine("this machine has a render endpoint, so the no-device path is not exercised here");
            return;
        }

        using var gen = new ToneGenerator();
        gen.SetFrequency(440);

        var announced = NextStateAsync(gen);
        gen.Play();                       // must not throw

        await announced.WaitAsync(TimeSpan.FromSeconds(5));

        Assert.False(gen.IsRunning);
        Assert.False(gen.HasOutput);
        Assert.Equal(ToneProblem.NoOutputDevice, gen.Problem);

        Output.WriteLine($"problem shown to the user: {gen.Problem}");

        gen.Stop();                       // idempotent
        gen.Shutdown();                   // idempotent
        Assert.False(gen.IsRunning);
    }

    [Fact]
    public async Task Play_and_stop_drive_the_state_machine()
    {
        if (!ToneGenerator.HasRenderDevice())
        {
            Output.WriteLine("no render endpoint on this machine — the device state machine is not exercised");
            return;
        }

        using var gen = new ToneGenerator();
        Assert.False(gen.IsRunning);
        Assert.Null(gen.Problem);

        var started = NextStateAsync(gen);
        gen.Play();
        await started.WaitAsync(TimeSpan.FromSeconds(20));

        Assert.True(gen.IsRunning);
        Assert.True(gen.HasOutput);
        Assert.Null(gen.Problem);

        Output.WriteLine(gen.UsingStreamRouting
            ? "opened following the default device (automatic stream routing)"
            : "opened bound to the default device (stream routing unavailable here)");
        Output.WriteLine($"device: {gen.DeviceName ?? "(the default device)"}");
        Output.WriteLine($"negotiated latency: {gen.NegotiatedLatencyMilliseconds} ms");

        var stopped = NextStateAsync(gen);
        gen.Stop();
        await stopped.WaitAsync(TimeSpan.FromSeconds(5));
        Assert.False(gen.IsRunning);

        var toggledOn = NextStateAsync(gen);
        gen.Toggle();
        await toggledOn.WaitAsync(TimeSpan.FromSeconds(20));
        Assert.True(gen.IsRunning);

        var toggledOff = NextStateAsync(gen);
        gen.Toggle();
        await toggledOff.WaitAsync(TimeSpan.FromSeconds(5));
        Assert.False(gen.IsRunning);

        gen.Shutdown();
        Assert.False(gen.IsRunning);
    }

    [Fact]
    public async Task Volume_only_reaches_the_oscillator_while_playing()
    {
        using var gen = new ToneGenerator(48000, 2);

        gen.Volume = 1.0;
        Assert.Equal(0.0, gen.Oscillator.TargetGain);

        if (!ToneGenerator.HasRenderDevice())
        {
            Output.WriteLine("no render endpoint on this machine — only the stopped case is exercised");
            return;
        }

        var started = NextStateAsync(gen);
        gen.Play();
        await started.WaitAsync(TimeSpan.FromSeconds(20));
        Assert.Equal(ToneGenerator.Headroom, gen.Oscillator.TargetGain, 12);

        var stopped = NextStateAsync(gen);
        gen.Stop();
        await stopped.WaitAsync(TimeSpan.FromSeconds(5));
        Assert.Equal(0.0, gen.Oscillator.TargetGain);
    }

    [Fact]
    public void Dispose_is_idempotent_and_play_afterwards_is_a_no_op()
    {
        var gen = new ToneGenerator();

        gen.Dispose();
        gen.Dispose();

        gen.Play();
        Assert.False(gen.IsRunning);
    }

    [Fact]
    public async Task Start_and_stop_cycles_reuse_the_one_player()
    {
        if (!ToneGenerator.HasRenderDevice())
        {
            Output.WriteLine("no render endpoint on this machine — the restart path is not exercised");
            return;
        }

        using var gen = new ToneGenerator();

        var started = NextStateAsync(gen);
        gen.Play();
        await started.WaitAsync(TimeSpan.FromSeconds(20));
        Assert.True(gen.IsRunning);
        Assert.Equal(1, gen.PlayersOpened);

        for (var cycle = 1; cycle <= 6; cycle++)
        {
            var stopped = NextStateAsync(gen);
            gen.Stop();
            await stopped.WaitAsync(TimeSpan.FromSeconds(5));

            var restarted = NextStateAsync(gen);
            gen.Play();
            await restarted.WaitAsync(TimeSpan.FromSeconds(20));

            Assert.True(gen.IsRunning, $"cycle {cycle}: the tone did not restart");
            Assert.Null(gen.Problem);
            Assert.Equal(1, gen.PlayersOpened);
            Assert.Equal(1, gen.LivePlayers);
        }

        Output.WriteLine($"after 6 stop/start cycles: players opened = {gen.PlayersOpened}, live = {gen.LivePlayers}");
        Output.WriteLine($"restart latency: {gen.NegotiatedLatencyMilliseconds} ms negotiated");
    }
}
