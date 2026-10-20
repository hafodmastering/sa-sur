// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Limited and Sudeep Audio.com LLP

using System.Diagnostics;
using System.Reflection;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Platform;

namespace SaSur.App;

/// Where the Help menu's three items are answered from.
///
/// The manual and the licence files ship inside the package or beside the executable, so a
/// Microsoft Store user - who never sees the GitHub release page - reaches the same documents a
/// direct download does. Files are read from the application directory: inside an MSIX that is the
/// package folder, which is readable but not writable, so anything that has to be opened by another
/// program is copied to LocalApplicationData first.
internal static class HelpFiles
{
    public const string ManualName = "SA-Sur-Manual.pdf";
    public const string LicenceName = "LICENSE";
    public const string NoticeName = "NOTICE";
    public const string EulaName = "EULA.txt";
    public const string ThirdPartyName = "THIRD-PARTY-NOTICES.txt";
    public const string FontLicenceName = "OFL.txt";

    public static string ApplicationDirectory => AppContext.BaseDirectory;

    public static string ManualPath => Path.Combine(ApplicationDirectory, ManualName);

    /// The manual, copied somewhere the user's PDF viewer may write its own state.
    public static string? OpenManual()
    {
        var source = ManualPath;
        if (!File.Exists(source))
        {
            return null;
        }

        var target = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "SA-Sur",
            ManualName);

        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            File.Copy(source, target, overwrite: true);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"SA-Sur: could not stage the manual beside the user's data ({ex.Message}); opening the package copy.");
            target = source;
        }

        try
        {
            Process.Start(new ProcessStartInfo(target) { UseShellExecute = true });
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"SA-Sur: could not open {target}: {ex.Message}");
        }

        return target;
    }

    /// The licence, notice and third-party texts, concatenated for the Licences window. A file that
    /// is missing is named rather than silently dropped: the reader can see what the build carries.
    public static string LicenceText()
    {
        var parts = new List<string>();
        foreach (var (name, heading) in new[]
                 {
                     (EulaName, "SA-Sur End User Licence Agreement (the store build)"),
                     (LicenceName, "Apache License 2.0 (the source code)"),
                     (NoticeName, "NOTICE"),
                     (ThirdPartyName, "Third-party notices"),
                     (FontLicenceName, "Nunito - SIL Open Font License 1.1"),
                 })
        {
            var path = Path.Combine(ApplicationDirectory, name);
            try
            {
                parts.Add(File.Exists(path)
                    ? $"{heading}\n\n{File.ReadAllText(path).Trim()}"
                    : $"{heading}\n\n[This build does not carry {name}.]");
            }
            catch (Exception ex)
            {
                parts.Add($"{heading}\n\n[Could not read {name}: {ex.Message}]");
            }
        }

        return string.Join("\n\n" + new string('-', 78) + "\n\n", parts);
    }

    public static void ShowLicences(Window owner) =>
        TextWindow.Show(owner, "SA-Sur licences", LicenceText());

    public static void ShowAbout(Window owner)
    {
        var version = Assembly.GetExecutingAssembly()
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion
            ?? typeof(HelpFiles).Assembly.GetName().Version?.ToString()
            ?? "1.2.0";

        var text = string.Join(
            "\n\n",
            $"SA-Sur : Note to Frequency {version}",
            "A single-window note-to-frequency utility with a sine-tone audition.",
            "© 2026 Hafod Mastering Limited and Sudeep Audio.com LLP",
            "Built by Hafod Mastering (Wales) with Sudeep Audio (India).",
            "The source code is Apache-2.0 and lives at github.com/hafodmastering/sa-sur. "
            + "This Microsoft Store build is licensed under the SA-Sur End User Licence Agreement; "
            + "see Licences.",
            "No account, no analytics, no network connection.");

        TextWindow.Show(owner, "About SA-Sur", text);
    }
}

/// A plain read-only window for text the app carries. Deliberately not a dialog box: the licences
/// are long, and text the user can select and copy is worth more than a button that dismisses.
///
/// The palette is fixed rather than themed. A document window that inherits the app's dark
/// variant would need every brush declared twice to stay legible, and getting one wrong makes the
/// text invisible on its own background - the failure this project has already had once.
internal static class TextWindow
{
    private static readonly Color Ink = Color.FromRgb(0x27, 0x27, 0x27);
    private static readonly Color Paper = Color.FromRgb(0xFF, 0xFF, 0xFF);

    public static void Show(Window owner, string title, string text)
    {
        var brush = new SolidColorBrush(Ink);
        var heading = new TextBlock
        {
            Text = title,
            FontSize = 15,
            FontWeight = FontWeight.SemiBold,
            Foreground = brush,
            Margin = new Thickness(0, 0, 0, 10),
        };

        var body = new SelectableTextBlock
        {
            Text = text,
            FontSize = 12,
            TextWrapping = TextWrapping.Wrap,
            Foreground = brush,
        };

        var window = new Window
        {
            Title = title,
            Width = 560,
            Height = 520,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            CanResize = true,
            Content = new Border
            {
                Padding = new Thickness(18),
                Background = new SolidColorBrush(Paper),
                Child = new StackPanel
                {
                    Orientation = Orientation.Vertical,
                    Children =
                    {
                        heading,
                        new ScrollViewer
                        {
                            Content = body,
                            VerticalScrollBarVisibility = Avalonia.Controls.Primitives.ScrollBarVisibility.Auto,
                        },
                    },
                },
            },
        };

        window.Show(owner);
    }
}
