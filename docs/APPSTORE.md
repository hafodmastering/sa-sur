# Mac App Store

SA-Sur is submitted to the Mac App Store as well as published here. The store build
is the same app from the same source, sandboxed and signed with *Apple
Distribution* — a second pipeline, not an extension of [RELEASE.md](RELEASE.md),
and gated by App Review.

| | Direct download | Mac App Store |
|---|---|---|
| Version | 1.0 | **1.1** |
| Signing | Developer ID Application | Apple Distribution |
| Envelope | `.app` in a zip | `.pkg` |
| Sandbox | not required | mandatory |
| Privacy manifest | not required | required |
| Gatekeeper | notarized + stapled ticket | store install, no dialog |
| Updates | a new download | store updates, each gated by review |
| Seller shown | `Sudeep Audio.com LLP` | `Sudeep Audio.com LLP` |

**Why 1.1 and not 1.0.** The store build is a different artifact — sandboxed, with a
privacy manifest — and it lands on App Review's clock, so the two version lines are
independent. The direct download shipped as 1.0; the store debut is 1.1.

**The sandbox needs almost nothing.** Audio output, the pasteboard (the copy
button), and handing the two company links to the default browser; preferences live
inside the app's own container. No file access, no network client, no camera or mic,
no accessibility. The privacy manifest declares one required-reason API,
`UserDefaults`, for the appearance preference, and nothing is collected or tracked.

**The listing** needs a support URL and a privacy policy URL that resolve; both are
served from this repository — [SUPPORT.md](SUPPORT.md) and [PRIVACY.md](PRIVACY.md).

**One publisher.** The seller string is `Sudeep Audio.com LLP`, the Sudeep Audio
Apple Developer team's registered name, and it matches what Gatekeeper shows for the
direct download, so the two channels read as one publisher.

The listing lives or dies with the Sudeep Audio Developer Program membership: a lapse
pulls it from the store while already-installed copies keep working.
