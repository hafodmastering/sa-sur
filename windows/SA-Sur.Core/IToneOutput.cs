// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

namespace SaSur.Core;

public interface IToneOutput
{
    bool IsRunning { get; }

    string? Problem { get; }

    double Volume { get; set; }

    event EventHandler? StateChanged;

    void Play();

    void Stop();

    void Toggle();

    void SetFrequency(double hz);

    void Shutdown();
}

public static class ToneProblem
{
    public const string NoOutputDevice = "No audio output device";
}

public sealed class SilentToneOutput : IToneOutput
{
    public bool IsRunning { get; private set; }

    public string? Problem { get; private set; }

    public double Volume { get; set; } = 0.5;

    public event EventHandler? StateChanged;

    public string? Failure { get; set; }

    public void Play()
    {
        if (Failure is { Length: > 0 } why)
        {
            Problem = why;
        }
        else
        {
            Problem = null;
            IsRunning = true;
        }

        Announce();
    }

    public void Stop()
    {
        IsRunning = false;
        Announce();
    }

    public void Toggle()
    {
        if (IsRunning)
        {
            Stop();
        }
        else
        {
            Play();
        }
    }

    public double LastFrequency { get; private set; } = 440.0;

    public void SetFrequency(double hz) => LastFrequency = hz;

    public void Shutdown()
    {
        IsRunning = false;
        Announce();
    }

    private void Announce() => StateChanged?.Invoke(this, EventArgs.Empty);
}
