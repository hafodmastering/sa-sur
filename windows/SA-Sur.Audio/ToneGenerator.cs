// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

using System.Diagnostics;
using NAudio.CoreAudioApi;
using NAudio.Wave;
using SaSur.Core;

namespace SaSur.Audio;

public sealed class ToneGenerator : IToneOutput, IDisposable
{
    // The app's only gain stage: above ~5 kHz a full-scale sine is unpleasant in a studio, so the
    // ceiling is 0.11 FS and the slider scales 0..1 within it.
    public const double Headroom = 0.11;

    // The macOS law, deliberately: gain = position x headroom, so the two builds stay comparable.
    public static double GainFor(double volume) => Headroom * Math.Clamp(volume, 0.0, 1.0);

    private const int LatencyMilliseconds = 30;

    private const string MmcssTaskName = "Pro Audio";

    private const int FallbackSampleRate = 48000;

    private readonly object _gate = new();

    private readonly FloatWaveProvider _waveProvider;

    private readonly List<WasapiPlayer> _stale = [];

    private WasapiPlayer? _player;
    private bool _isRunning;
    private bool _starting;
    private bool _stopRequested;
    private bool _usingStreamRouting;
    private bool _usingRawMode;
    private string? _problem;
    private int _playersOpened;
    private double _volume = 0.5;
    private bool _disposed;

    public ToneGenerator(int sampleRate, int channels)
    {
        Oscillator = new SineOscillator(sampleRate);
        Provider = new OscillatorProvider(Oscillator, sampleRate, channels);
        _waveProvider = new FloatWaveProvider(Provider);
    }

    public ToneGenerator()
        : this(DeviceFormat())
    {
    }

    private ToneGenerator((int SampleRate, int Channels) format)
        : this(format.SampleRate, format.Channels)
    {
    }

    public event EventHandler? StateChanged;

    public SineOscillator Oscillator { get; }

    public OscillatorProvider Provider { get; }

    public int SampleRate => Provider.WaveFormat.SampleRate;

    public int Channels => Provider.WaveFormat.Channels;

    public bool IsRunning
    {
        get { lock (_gate) { return _isRunning; } }
    }

    public string? Problem
    {
        get { lock (_gate) { return _problem; } }
    }

    public bool HasOutput
    {
        get { lock (_gate) { return _player is not null; } }
    }

    public double Volume
    {
        get { lock (_gate) { return _volume; } }
        set
        {
            lock (_gate)
            {
                _volume = Math.Clamp(value, 0.0, 1.0);
                Oscillator.TargetGain = _isRunning ? GainFor(_volume) : 0.0;
            }
        }
    }

    public bool UsingStreamRouting
    {
        get { lock (_gate) { return _player is not null && _usingStreamRouting; } }
    }

    public bool UsingRawMode
    {
        get { lock (_gate) { return _player is not null && _usingRawMode; } }
    }

    public int PlayersOpened
    {
        get { lock (_gate) { return _playersOpened; } }
    }

    public int LivePlayers
    {
        get { lock (_gate) { return (_player is null ? 0 : 1) + _stale.Count; } }
    }

    public int? NegotiatedLatencyMilliseconds
    {
        get { lock (_gate) { return _player?.LatencyMilliseconds; } }
    }

    public string? DeviceName
    {
        get { lock (_gate) { return _player?.DeviceFriendlyName; } }
    }

    public static bool HasRenderDevice()
    {
        try
        {
            using var enumerator = new MMDeviceEnumerator();
            if (!enumerator.TryGetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia, out var device)
                || device is null)
            {
                return false;
            }

            using var client = device.CreateAudioClient();
            return client.MixFormat.SampleRate > 0;
        }
        catch
        {
            return false;
        }
    }

    public static (int SampleRate, int Channels) DeviceFormat()
    {
        try
        {
            using var enumerator = new MMDeviceEnumerator();
            if (enumerator.TryGetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia, out var device)
                && device is not null)
            {
                using var client = device.CreateAudioClient();
                var format = client.MixFormat;
                if (format.SampleRate > 0)
                {
                    return (format.SampleRate, Math.Clamp(format.Channels, 1, 2));
                }
            }
        }
        catch
        {
        }
        return (FallbackSampleRate, 2);
    }

    // Stream routing activates asynchronously, so routed attempts must use BuildAsync(); the
    // synchronous Build() refuses it. Raw mode bypasses the endpoint's APO chain, where a leveller
    // would alter the tone and flatten the slider - so it leads the ladder rather than ending it.
    public static async Task<(WasapiPlayer Player, bool Routed, bool Raw)> OpenOutputAsync(IWaveProvider source)
    {
        (bool Routed, bool Raw, string What)[] attempts =
        [
            (true,  true,  "stream routing with the endpoint's processing bypassed"),
            (true,  false, "stream routing with the endpoint's processing left on"),
            (false, true,  "raw output bound to the default device"),
            (false, false, "output bound to the default device"),
        ];

        Exception? refusal = null;

        foreach (var (routed, raw, what) in attempts)
        {
            try
            {
                var player = routed
                    ? await Configure(routed: true, raw).BuildAsync().ConfigureAwait(false)
                    : Configure(routed: false, raw).Build();
                player.Init(source);
                return (player, routed, raw);
            }
            catch (Exception ex) when (!IsConfigurationRefusal(ex))
            {
                refusal = ex;
                Debug.WriteLine($"SA-Sur: {what} unavailable ({ex.Message}).");
            }
        }

        throw refusal ?? new InvalidOperationException("No audio output could be opened.");
    }

    private static WasapiPlayerBuilder Configure(bool routed, bool raw)
    {
        var builder = new WasapiPlayerBuilder()
            .WithSharedMode()
            .WithEventSync()
            .WithLatency(LatencyMilliseconds)
            .WithMmcssThreadPriority(MmcssTaskName);

        if (routed)
        {
            builder = builder.WithDefaultDeviceStreamRouting();
        }

        if (raw)
        {
            builder = builder.WithRawMode();
        }

        return builder;
    }

    // These fire before any hardware is touched, so they mean this app is misconfigured,
    // identically on every machine. The ladder must never swallow one.
    private static bool IsConfigurationRefusal(Exception ex) =>
        ex is InvalidOperationException
        && (ex.Message.Contains("BuildAsync() instead of Build()", StringComparison.Ordinal)
            || ex.Message.Contains("not supported with automatic stream routing", StringComparison.Ordinal)
            || ex.Message.Contains("cannot be combined with WithDevice", StringComparison.Ordinal)
            || ex.Message.Contains("only available in shared mode", StringComparison.Ordinal));

    public void Play()
    {
        WasapiPlayer[] stale;
        var announce = false;

        lock (_gate)
        {
            if (_disposed || _isRunning)
            {
                return;
            }

            if (_starting)
            {
                _stopRequested = false;
                return;
            }

            _stopRequested = false;

            if (_player is not null && _player.PlaybackState != PlaybackState.Playing)
            {
                RetirePlayerLocked();
            }

            stale = TakeStaleLocked();
            _problem = null;

            if (_player is not null)
            {
                Oscillator.TargetGain = GainFor(_volume);
                _isRunning = true;
                announce = true;
            }
            else if (!HasRenderDevice())
            {
                _problem = ToneProblem.NoOutputDevice;
                announce = true;
            }
            else
            {
                _starting = true;
            }
        }

        DisposeAll(stale);
        if (announce)
        {
            Announce();
            return;
        }

        _ = StartAsync();
    }

    private async Task StartAsync()
    {
        WasapiPlayer? player = null;
        var routed = false;
        var raw = false;
        string? failure = null;

        try
        {
            (player, routed, raw) = await OpenOutputAsync(_waveProvider).ConfigureAwait(false);
            player.PlaybackStopped += OnPlaybackStopped;

            Oscillator.TargetGain = GainFor(_volume);
            player.Play();
        }
        catch (Exception ex)
        {
            failure = Describe(ex);
            Debug.WriteLine($"SA-Sur: audio output failed to start: {ex}");
            DisposePlayer(player);
            player = null;
        }

        WasapiPlayer? toDispose = null;
        WasapiPlayer[] retired = [];
        var announce = false;

        lock (_gate)
        {
            _starting = false;

            if (player is not null && !_disposed && !_stopRequested)
            {
                if (_player is not null)
                {
                    RetirePlayerLocked();
                    retired = TakeStaleLocked();
                }

                _player = player;
                _playersOpened++;
                _usingStreamRouting = routed;
                _usingRawMode = raw;
                _isRunning = true;
                Oscillator.TargetGain = GainFor(_volume);
                _problem = null;
            }
            else
            {
                _isRunning = false;
                Oscillator.TargetGain = 0.0;
                if (!_disposed && !_stopRequested)
                {
                    _problem = failure;
                }

                toDispose = player;
            }

            _stopRequested = false;
            announce = !_disposed;
        }

        DisposePlayer(toDispose);
        DisposeAll(retired);
        if (announce)
        {
            Announce();
        }
    }

    public void Stop()
    {
        var announce = false;

        lock (_gate)
        {
            if (!_isRunning && !_starting)
            {
                return;
            }

            _stopRequested = true;
            Oscillator.TargetGain = 0.0;
            _isRunning = false;
            announce = true;
        }

        if (announce)
        {
            Announce();
        }
    }

    public void Toggle()
    {
        if (IsRunning || IsStarting)
        {
            Stop();
        }
        else
        {
            Play();
        }
    }

    public void SetFrequency(double hz) => Oscillator.Frequency = hz;

    public void Shutdown()
    {
        WasapiPlayer[] stale;

        lock (_gate)
        {
            _stopRequested = true;
            _isRunning = false;
            Oscillator.TargetGain = 0.0;
            RetirePlayerLocked();
            stale = TakeStaleLocked();
        }

        DisposeAll(stale);
    }

    private bool IsStarting
    {
        get { lock (_gate) { return _starting; } }
    }

    private void OnPlaybackStopped(object? sender, StoppedEventArgs e)
    {
        var announce = false;

        lock (_gate)
        {
            if (_disposed || _player is null || !ReferenceEquals(sender, _player))
            {
                return;
            }

            _isRunning = false;
            Oscillator.TargetGain = 0.0;
            _stale.Add(_player);
            _player = null;

            if (e.Exception is not null)
            {
                _problem = Describe(e.Exception);
                Debug.WriteLine($"SA-Sur: playback stopped: {e.Exception}");
            }

            announce = true;
        }

        if (announce)
        {
            Announce();
        }
    }

    private void RetirePlayerLocked()
    {
        if (_player is null)
        {
            return;
        }

        _stale.Add(_player);
        _player = null;
    }

    private WasapiPlayer[] TakeStaleLocked()
    {
        if (_stale.Count == 0)
        {
            return [];
        }

        var taken = _stale.ToArray();
        _stale.Clear();
        return taken;
    }

    private static void DisposeAll(WasapiPlayer[] players)
    {
        foreach (var player in players)
        {
            DisposePlayer(player);
        }
    }

    private static void DisposePlayer(WasapiPlayer? player)
    {
        try
        {
            player?.Dispose();
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"SA-Sur: disposing the output failed: {ex.Message}");
        }
    }

    private void Announce() => StateChanged?.Invoke(this, EventArgs.Empty);

    private static string Describe(Exception ex)
    {
        var collapsed = string.Join(
            ' ',
            ex.Message.Split(['\r', '\n', '\t', ' '], StringSplitOptions.RemoveEmptyEntries));

        if (collapsed.Length == 0)
        {
            return "The audio output could not be started";
        }

        return collapsed.Length > 96 ? collapsed[..93] + "…" : collapsed;
    }

    public (float[] Left, float[] Right, int SampleRate, int Channels) MeasureOffline(
        double seconds, double gain)
    {
        var wasRunning = IsRunning;
        Stop();

        var channels = Channels;
        var rate = SampleRate;
        var frames = (int)(rate * seconds);
        var scratch = new float[4096 * channels];
        var left = new List<float>(frames);
        var right = new List<float>(frames);

        Oscillator.TargetGain = gain;
        var remaining = frames;
        while (remaining > 0)
        {
            var want = Math.Min(scratch.Length, remaining * channels);
            var got = Provider.Read(scratch.AsSpan(0, want));
            if (got <= 0)
            {
                break;
            }

            var produced = got / channels;
            for (var f = 0; f < produced; f++)
            {
                left.Add(scratch[f * channels]);
                right.Add(channels > 1 ? scratch[f * channels + 1] : scratch[f * channels]);
            }
            remaining -= produced;
        }

        Oscillator.TargetGain = 0.0;
        if (wasRunning)
        {
            Play();
        }

        return (left.ToArray(), right.ToArray(), rate, channels);
    }

    public void Dispose()
    {
        WasapiPlayer[] stale;

        lock (_gate)
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;
            _stopRequested = true;
            _isRunning = false;
            Oscillator.TargetGain = 0.0;
            RetirePlayerLocked();
            stale = TakeStaleLocked();
        }

        DisposeAll(stale);
    }
}

public sealed class OscillatorProvider : ISampleProvider
{
    private readonly SineOscillator _osc;
    private readonly int _channels;
    private float[] _scratch = new float[8192];

    public OscillatorProvider(SineOscillator osc, int sampleRate, int channels)
    {
        _osc = osc;
        _channels = channels;
        WaveFormat = WaveFormat.CreateIeeeFloatWaveFormat(sampleRate, channels);
    }

    public WaveFormat WaveFormat { get; }

    public int Read(Span<float> buffer)
    {
        var frames = buffer.Length / _channels;
        if (frames <= 0)
        {
            return 0;
        }

        if (_scratch.Length < frames)
        {
            _scratch = new float[frames];
        }

        var mono = _scratch.AsSpan(0, frames);
        _osc.Render(mono);

        for (var f = 0; f < frames; f++)
        {
            var v = mono[f];
            var at = f * _channels;
            for (var c = 0; c < _channels; c++)
            {
                buffer[at + c] = v;
            }
        }

        return frames * _channels;
    }
}
