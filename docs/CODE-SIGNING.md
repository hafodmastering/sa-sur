# Code signing

Where each channel's trust comes from, what the signature actually proves, and what is still open.

## macOS - signed and notarized

`SA-Sur-1.0-MacOS.zip` is signed with an Apple **Developer ID Application** certificate issued to
**Sudeep Audio.com LLP** (team `E37W7LU474`), notarized by Apple, and the ticket is stapled. On a
quarantined copy Gatekeeper reports `accepted, source=Notarized Developer ID`. The steps live in
[docs/RELEASE.md](RELEASE.md); the identity and notarization credentials are held by Donal.

## Windows release download - unsigned, verified by hash

`SA-Sur-1.0-windows.exe` is **not signed**. A downloaded copy carries Mark-of-the-Web, so SmartScreen
shows *"Windows protected your PC"* with an **unknown publisher** until the user picks *More info →
Run anyway*; machines under an application-whitelisting policy, and Windows 11 machines with Smart App
Control on, may refuse to run it at all. An unsigned file also starts from zero reputation on every
release, so the warning does not fade as versions go by.

Verification here is the **SHA-256 published in the release notes**. The .NET single-file bundler is
not deterministic across environments, so a download cannot be checked by rebuilding it and comparing
hashes; the published digest is the check, and the release notes say so.

## Windows, Microsoft Store - signed by Microsoft, no prompt at all

A package published in the Microsoft Store is **re-signed by Microsoft** after certification, and
Store-distributed apps are never subject to SmartScreen download warnings. They also satisfy Smart App
Control and enterprise policies that refuse unsigned executables. That is the channel that removes the
prompt rather than softening it, and it costs nothing: developer registration, certification and
binary hosting are free, and there is no certificate to buy or renew.

The package is an **MSIX**. Its manifest, tile assets and packaging scripts are kept with the store
work rather than in this repository, so the listing and the package are prepared together and neither
can drift from the other. The Store line carries its own version number - **1.1.1.0** - stamped into
the package identity *and* into the binary, the same rule `tools/store-build.sh` applies to the macOS
store build.

**State.** The package is built, verified and uploaded to Partner Center, and the store listing is
complete. Submission 1 (`SA-Sur_1.1.1.0_x64.msix`) is **in certification**; publishing is manual,
so nothing becomes public until *Publish now* is pressed after certification passes.

## What was considered, and why this is the route

| Route | Cost | Outcome |
|---|---|---|
| Microsoft Store (MSIX) | **free** | **Chosen.** Microsoft re-signs; the prompt never appears; nothing to renew. |
| Certificate in the publisher's name, from a commercial signing service | ~$500/year | The publisher string would read `Sudeep Audio.com LLP`, matching macOS. Possible later; not needed while the Store signs for free. |
| Microsoft's own signing service | ~$10/month | Organisation validation is limited to a list of countries that **does not include India**, so Sudeep Audio cannot hold it. |
| OV / EV certificate of our own | $150-400/year | Plus an HSM or token since June 2023. **EV has not bypassed SmartScreen since 2024**, so the premium buys nothing here. |

Every paid route buys a *named publisher* and reputation that accrues across releases. None of them
buys silence on the first download; only the Store does that.

## What a signature proves, and what it does not

- **Store package:** the signature is Microsoft's, so it attests that this is the package Microsoft
  certified, not who wrote it. Identity lives in the listing's publisher name, which is Sudeep
  Audio's.
- **macOS build:** the certificate is issued to the legal entity `Sudeep Audio.com LLP`, and Apple has
  validated the account behind it, so the Gatekeeper prompt names the company. This is the strongest
  of the three.
- **Direct download:** no signature at all; the hash proves only that the file is the file that was
  published.
- **None of them make a claim about the source code.** The repository is the source of truth for that,
  and anyone may build their own binary from it.
