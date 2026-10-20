# Mac App Store

SA-Sur is live on the Mac App Store. **1.1** was approved on 19 October 2026 and
released the same evening; **1.2.0** is the current submission. The store build is
the same app from the same source, sandboxed and signed with *Apple Distribution* -
a second pipeline, not an extension of [RELEASE.md](RELEASE.md), and gated by App
Review.

| | Direct download | Mac App Store |
|---|---|---|
| Version | **1.2.0** | **1.2.0** |
| Signing | Developer ID Application | Apple Distribution |
| Envelope | `.app` in a zip | `.pkg` |
| Sandbox | not required | mandatory |
| Privacy manifest | not required | required |
| Gatekeeper | notarized + stapled ticket | store install, no dialog |
| Updates | a new download | store updates, each gated by review |
| Seller shown | `Sudeep Audio.com LLP` | `Sudeep Audio.com LLP` |
| Licence | Apache-2.0 | the SA-Sur EULA, which incorporates Apache-2.0 |

**One version since 1.2.0.** Until then the store ran its own line (1.1) because it
debuts on App Review's clock. That is no longer how the project numbers releases:
see the version-numbering section of [RELEASE.md](RELEASE.md). App Review still
gates the store's *release*; a build waiting for review does not hold back the
direct download, and a rejection does not renumber anything.

**The sandbox needs almost nothing.** Audio output, the pasteboard (the copy
button), and handing the two company links to the default browser; preferences live
inside the app's own container. No file access, no network client, no camera or mic,
no accessibility. The privacy manifest declares one required-reason API,
`UserDefaults`, for the appearance preference, and nothing is collected or tracked.

**The bundle carries the documents.** `tools/store-build.sh` copies `LICENSE`,
`NOTICE`, `EULA.md`, `THIRD-PARTY-NOTICES.md` and the manual into
`Contents/Resources`; the Help menu opens them.

**The listing** needs a support URL and a privacy policy URL that resolve; both are
served from this repository - [SUPPORT.md](SUPPORT.md) and [PRIVACY.md](PRIVACY.md).
The custom licence agreement is the text in [EULA.md](../EULA.md), pasted at App
Information → License Agreement. Until 1.2.0 the listing used Apple's Standard
EULA, which is not what a user of the source code is offered here.

**One publisher.** The seller string is `Sudeep Audio.com LLP`, the Sudeep Audio
Apple Developer team's registered name, and it matches what Gatekeeper shows for the
direct download, so the two channels read as one publisher.

The listing lives or dies with the Sudeep Audio Developer Program membership: a lapse
pulls it from the store while already-installed copies keep working.

## The pkg, and why its name carries the build number

`tools/store-build.sh` writes `build/store/SA-Sur-<version>-<build>-store.pkg`. It
used to drop the build number, and that produced a real mistake: `build/store/` held
build 11 while the build in App Review was build 12, and the two files were
indistinguishable by name. The build number is now part of the filename, and the
script prints the version, the build and the SHA-256 it produced.

The build that shipped as 1.1 was **build 12**; this round is **build 13**.
