# Packaging SA-Sur for the Microsoft Store

The Windows build ships two ways: the bare `SA-Sur.exe` attached to the GitHub release (unsigned,
verified by its published SHA-256), and an MSIX package published in the Microsoft Store, where
Microsoft signs it and users never see a SmartScreen prompt.

Nothing here needs Visual Studio. Microsoft's project-level MSIX support covers its own app models -
a Windows App SDK project packages itself, a WPF/WinForms project gets a Windows Application
Packaging Project - and an Avalonia app is neither. So the manifest the wizard would have written is
written by hand in this folder and handed to `MakeAppx`, which validates it against the schema.

## Files

| File | What it is |
|---|---|
| `AppxManifest.xml` | The package manifest, with four `__TOKEN__` values substituted by the script. Static XML: it declares the identity, the entry point (`Windows.FullTrustApplication`), the tile assets and the `runFullTrust` capability a packaged Win32 app needs. |
| `store-identity.psd1` | The single source of the four identity values. Three of them come from Partner Center and are marked PLACEHOLDER until the product name is reserved. |
| `pack-msix.ps1` | Publishes with the Store version stamped in, stages the layout, packs, unpacks and reads the result back. `-SelfSign` adds a throwaway certificate and trusts it; `-Install` installs the result and reports what landed. |
| `make-assets.sh` | Regenerates `Assets/` and `SA-Sur.App/SA-Sur.ico` from the composed icon master. macOS tooling only (`sips`, `python3`); the outputs are committed, so the Windows build never needs an image tool. |
| `Assets/` | The tile, wide tile, splash and store logos referenced by the manifest. |

## Building and checking a package

On Windows, from this folder:

```powershell
.\pack-msix.ps1                 # publish, stage, pack, verify - unsigned
.\pack-msix.ps1 -SelfSign -Install   # ... plus a dev certificate, install and report (elevation)
```

Notes from the toolchain this was built against:

- **`MakeAppx` comes from NuGet, not an installer.** There is no `winget` on a Windows Server SKU and
  MSI installs fail for a passwordless account, so the Windows SDK is not an option. The tools come
  out of `Microsoft.Windows.SDK.BuildTools` (a NuGet package that is just a zip) and the script finds
  them under `C:\Tools\sdk-buildtools`. Any SDK install works too; `-MakeAppx` overrides the search.
- **The version is stamped, never inherited.** `-p:Version=<Version from store-identity.psd1>` is
  passed to `dotnet publish`, so the Store's number and the number inside the binary agree. This is
  the same rule `tools/store-build.sh` applies on the macOS side, and D22 is the record of what
  happens when one channel inherits the other's number.
- **The four-part version must end in `.0`.** Partner Center reserves the revision field. The third
  part is the packaging iteration: the same code resubmitted (new listing metadata, a re-cut) needs
  `1.1.1.0`.

## Publishing to the Store

1. **Register a developer account** at <https://storedeveloper.microsoft.com/> - the only supported
   entry point for the current free flow. Choose **Company**; an account cannot be changed from
   Individual to Company afterwards. Sudeep Audio's account needs business verification (D-U-N-S
   number, or formation/registration documents) and a work email on the organisation's own domain.
2. **Reserve the product name `SA-Sur`**, free, held up to three months. This is where the three
   Partner Center identity values come from - replace the placeholders in `store-identity.psd1`:
   *Product identity → Package/Identity/Name*, *Package/Identity/Publisher*, and the account's
   *Publisher display name*.
3. **Build the package**: `.\pack-msix.ps1`. A Store submission does **not** need our signature - the
   Store re-signs the package with a Microsoft certificate after certification, replacing it - so the
   unsigned output is the submission artifact.
4. **Create the submission** in Partner Center: upload the `.msix`, complete the listing (description,
   screenshots, category, age-rating questionnaire, support and privacy URLs), and **declare
   `runFullTrust` in Restricted capabilities** with the reason: it is mandatory for any packaged Win32
   application and the app is a full-trust desktop utility.
5. **Certification takes up to three business days.** The listing is usually visible about fifteen
   minutes after it passes.
6. **Check the installed result before announcing anything**: `Get-AppxPackage *SASur*` for the
   version, then launch it and confirm the window, the tone and the appearance preference.

## What the Store build changes, and what it does not

- **The warning goes away for good.** Store-distributed apps are signed by Microsoft and never
  subject to SmartScreen download warnings; they also satisfy Smart App Control and enterprise
  policies that refuse unsigned executables.
- **Updates arrive automatically.** That is a real difference from the GitHub `.exe`, which is the
  frozen channel: a Studio install of the Store app can change under a user between sessions.
- **It needs a Microsoft account to install**, which the app's "free, no account, no telemetry"
  position otherwise does without. The direct download stays for anyone who wants neither the Store
  nor automatic updates.
- **It is not sandboxed.** `runFullTrust` means the packaged app runs with the user's own rights,
  exactly as the downloaded exe does. Same code, same audio path, different install and update
  mechanics.
- **The MSIX outside the Store is not a distribution route.** Windows will not install an unsigned
  MSIX, and Microsoft disabled the `ms-appinstaller` web-link protocol by default in December 2023 -
  so a signed-once-for-the-Store package is not something to attach to a GitHub release. Distributing
  the MSIX ourselves would need a certificate of our own, which is the cost this route exists to
  avoid.
