# Code signing

## macOS — done

`SA-Sur-1.0-notarized.zip` is signed with an Apple **Developer ID Application** certificate issued to
**Sudeep Audio.com LLP** (team `E37W7LU474`), notarized by Apple, and the ticket is stapled. On a
quarantined copy Gatekeeper reports `accepted, source=Notarized Developer ID`. The steps live in
[docs/RELEASE.md](RELEASE.md); the identity and notarization credentials are held by Donal.

## Windows — in progress

The Windows build is **not signed**. A downloaded `SA-Sur.exe` carries Mark-of-the-Web, so SmartScreen
shows *"Windows protected your PC"* with an **unknown publisher** until the user picks *More info →
Run anyway*, and machines under an application-whitelisting policy may refuse to run it at all.

### Why SignPath Foundation, and not a certificate

| Option | Cost | Note |
|---|---|---|
| Microsoft Store (MSIX) | free | Microsoft re-signs; nothing to buy. Requires a Store listing. |
| **SignPath Foundation** | **free** | For OSS projects. Certificate is issued to *them*. |
| Azure Artifact Signing | ~$9.99/month | Needs an eligible organisation and Microsoft identity validation. |
| OV certificate | $150–300/year | Plus an HSM or USB token, required since June 2023. |
| EV certificate | $400+/year | **No longer an instant SmartScreen bypass** — that stopped in 2024. |

SA-Sur is given away free of charge and there is no paid edition, so a subscription to sign it is not
defensible. EV in particular buys nothing here that OV does not.

### What the certificate is, and what it is not

SignPath Foundation is a programme run by **SignPath GmbH**, a company that sells code signing as a
service. It is not a foundation and it has nothing to do with Microsoft — Microsoft merely links to it
on its [code signing options](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options)
page. Their own terms are explicit:

> *"The code signing certificate is issued to SignPath Foundation. This means that SignPath Foundation
> is the publisher of the OSS project."*

So **the publisher shown by Windows will read "SignPath Foundation", not Hafod Mastering Ltd.** Because
they are not a certificate authority they cannot validate us, so instead they verify that the binary is
an automated build of this public repository and vouch for that with their own name. The signature
attests **provenance, not identity** — which for a free app whose users gain most from knowing the
binary matches the source is arguably the more useful of the two.

Their signature does **not** buy silence: SmartScreen reputation is per-identity and per-file, and a
brand-new file hash still warns. The advantage over a fresh certificate of our own is that SignPath
Foundation's identity has signed releases for years, so the publisher side is already known.

### Their conditions, and where we stand

| Condition | State |
|---|---|
| OSI-approved licence, no commercial dual-licensing for any component | ✅ Apache-2.0 |
| No proprietary, non-open-source component | ⚠️ see [The marks](#the-marks-disclosed) |
| Actively maintained | ✅ |
| Already released in the form to be signed | ✅ SA-Sur 1.0 |
| Functionality described on its download page | ✅ README and release notes |
| Sign our own projects and binaries only | ✅ all source and build scripts are ours |
| Automated, verifiable build; manual approval per release | ✅ `.github/workflows/windows.yml` |
| Metadata enforced on signed binaries (product name, one product version) | ✅ set in `SaSur.App.csproj` |
| MFA on GitHub and SignPath for every team member | ⚠️ **2FA on the GitHub account is still outstanding** |
| "Code signing policy" section on the project home page | ✅ README |
| Privacy policy, or no unrequested data transfer | ✅ `docs/PRIVACY.md` |
| Uninstallation for anything that installs | n/a — a single `.exe`, no installer |

### The marks, disclosed

This is the one substantive question, and it is raised here rather than left to be discovered.

The Windows binary embeds the Hafod Mastering and Sudeep Audio logos. Those marks are **not** licensed
with the code — the README says so under *Licence and marks*, and Apache-2.0 §6 excludes trademarks —
so a fork is expected to replace them. They are brand artwork owned by the two companies that publish
the app, not third-party code, and the entire source and build script set is ours and public: a build
of the repository reproduces the binary.

SignPath's clause reads *"no proprietary, non open-source component (especially code published by a
maintainer or an affiliated person/organization)"*. We read that as aimed at proprietary code and
functionality rather than at the publisher's own brand marks, but it is their call and the application
says so plainly.

If they decline on this point, the options are to ship a build with substitute marks, or to drop the
SignPath route and keep publishing unsigned with a SHA-256.

### A note on reproducibility

The same commit built in CI and on the dev VM produces the same *size* but not the
same *hash*: the .NET single-file bundler is not deterministic across environments.
This does not affect SignPath, whose claim is that a signature attests an
*automated build of the repository*; the signing step runs in the same pipeline that
produced the binary, and they never compare two machines bit for bit. It does mean a
user cannot verify a download by rebuilding and comparing hashes, so the published
SHA-256 and the signature are the verification route, and the release notes say so.

### Order of work

1. Merge the policy section and the build workflow. ✅
2. Get the workflow green on `windows-latest`. ✅ — 1m33s, and the artifact downloaded back hashes
   identically to the digest the runner printed.
3. Cut a public Windows release from the workflow's artifact, with its SHA-256 in the notes. ✅
   SA-Sur 1.0, attached to the `v1.0` release.
4. Enable 2FA on the GitHub account, and SignPath accounts for every team member. ⬜
5. Apply, disclosing the marks. ⬜
6. Once approved: wire `signpath/github-action-submit-signing-request` into the workflow at the
   commented step, and add a `signtool verify /pa` readback of the publisher name to the release
   checks — the same discipline the macOS side applies by reading back Gatekeeper's verdict. ⬜
