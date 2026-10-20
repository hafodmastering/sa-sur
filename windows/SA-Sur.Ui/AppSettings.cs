// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Limited and Sudeep Audio.com LLP

using System.Text.Json;
using System.Text.Json.Serialization;

namespace SaSur.Ui;

public enum ThemeMode
{
    System,
    Light,
    Dark,
}

// The settings file's serialization contract, generated at build time rather than discovered by
// reflection. The reflection path resolves these members by name at run time, which the trimmer
// cannot see, so it would remove Appearance and the preference would silently stop persisting.
[JsonSourceGenerationOptions(WriteIndented = true)]
[JsonSerializable(typeof(AppSettings))]
internal partial class AppSettingsJson : JsonSerializerContext
{
}

public sealed class AppSettings
{
    private const string FolderName = "SA-Sur";
    private const string FileName = "settings.json";

    public ThemeMode Appearance { get; set; } = ThemeMode.System;

    public string FilePath { get; init; } = DefaultPath;

    public static string DefaultDirectory =>
        System.IO.Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), FolderName);

    public static string DefaultPath => System.IO.Path.Combine(DefaultDirectory, FileName);

    public static AppSettings Load() => LoadFrom(DefaultPath);

    public static AppSettings LoadFrom(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                var loaded = JsonSerializer.Deserialize(
                    File.ReadAllText(path), AppSettingsJson.Default.AppSettings);
                if (loaded is not null)
                {
                    return new AppSettings { Appearance = loaded.Appearance, FilePath = path };
                }
            }
        }
        catch
        {
        }

        return new AppSettings { FilePath = path };
    }

    public void Save()
    {
        try
        {
            var directory = System.IO.Path.GetDirectoryName(FilePath);
            if (!string.IsNullOrEmpty(directory))
            {
                System.IO.Directory.CreateDirectory(directory);
            }
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this, AppSettingsJson.Default.AppSettings));
            LastSaveFailed = false;
        }
        catch (Exception ex)
        {
            // A read-only %APPDATA% is not worth interrupting the user for, but a preference that
            // silently stops persisting is indistinguishable from a broken control - so it is
            // recorded, and a test can see it.
            LastSaveFailed = true;
            System.Diagnostics.Debug.WriteLine($"SA-Sur: could not save {FilePath} ({ex.Message}).");
        }
    }

    /// True when the last Save() could not write. The appearance still applies for this session;
    /// it just will not be remembered.
    [JsonIgnore]
    public bool LastSaveFailed { get; private set; }
}

public static class ThemeModeExtensions
{
    public static ThemeMode Next(this ThemeMode mode) => mode switch
    {
        ThemeMode.System => ThemeMode.Light,
        ThemeMode.Light => ThemeMode.Dark,
        _ => ThemeMode.System,
    };

    public static string Help(this ThemeMode mode) => mode switch
    {
        ThemeMode.System => "Appearance: following the system - click for light",
        ThemeMode.Light => "Appearance: light - click for dark",
        _ => "Appearance: dark - click to follow the system",
    };

    public static string Symbol(this ThemeMode mode) => mode switch
    {
        ThemeMode.System => "\u25D0",   // half-filled circle
        ThemeMode.Light => "\u2600",    // sun
        _ => "\u263D",                   // crescent
    };
}
