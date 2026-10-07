// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

using System.Text.Json;

namespace SaSur.Ui;

public enum ThemeMode
{
    System,
    Light,
    Dark,
}

public sealed class AppSettings
{
    private const string FolderName = "SA-Sur";
    private const string FileName = "settings.json";

    private static readonly JsonSerializerOptions Format = new() { WriteIndented = true };

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
                var loaded = JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(path));
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
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this, Format));
        }
        catch
        {
        }
    }
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
