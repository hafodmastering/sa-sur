# Mac App Store runbook

Aditya wants the 1.0 release to reach users through the Mac App Store as well as
the notarized GitHub download. This is the plan for that. It is a *second
pipeline*, not an extension of `RELEASE.md`: the store build is a different
artifact with different signing, and it is gated by App Review.

Nothing here is decided except by Donal and Aditya; the open questions are at the
end.

## What the store changes, and what it does not

| | GitHub (direct download) | Mac App Store |
|---|---|---|
| Signing | Developer ID Application | Apple Distribution |
| Envelope | `.app` in a `zip` | `.pkg` (Mac Installer Distribution) |
| Sandbox | not required | **mandatory** |
| Privacy manifest | not required | **required** (required-reason APIs) |
| Gatekeeper | notarized + stapled ticket | store install, no Gatekeeper dialog |
| Updates | new download | store updates (App Review each time) |
| Who can publish | Donal | Donal, with the Sudeep team + accepted agreements |
| Seller name shown | `Sudeep Audio.com LLP` | `Sudeep Audio.com LLP` |

Already true, and worth not re-litigating:

- **The membership covers it.** The existing Sudeep Audio.com LLP Developer
  Program membership is exactly what store distribution requires — no second
  enrolment, no extra fee, same Team ID `E37W7LU474`.
- **Licence is fine.** Apache-2.0 has no App Store conflict (that concern is GPL).
  The trademark carve-out still applies: the store listing and the app bundle
  carry the studios' marks, and the licence grants nobody else that right.
- **The seller string matches** what Gatekeeper already shows for the direct
  download, so the two channels look like the same studios.

## The engineering delta

Small, and the only part with real risk of surprises:

1. **App Sandbox.** Add `SASur.entitlements` with
   `com.apple.security.app-sandbox = true` and build a store variant that signs
   with it. What the app actually needs:
   - audio output — allowed, no entitlement needed;
   - the pasteboard — `NSPasteboard` write for the copy button, allowed for a
     user-initiated copy;
   - opening the two studio links — `NSWorkspace.open` hands off to the default
     browser, allowed;
   - preferences — `UserDefaults` inside the container, allowed.
   No file access, no network client, no camera/mic, no accessibility. If a
   sandbox pass turns out to need something, it will be visible immediately
   because the app's whole job is one window, one tone and one copy button.
2. **`PrivacyInfo.xcprivacy`.** The appearance preference (added in 0.96) is the
   app's first use of `UserDefaults`, which is a required-reason API: declare
   `NSPrivacyAccessedAPICategoryUserDefaults` with reason **CA92.1** (access to
   the app's own preferences). No tracking, no data collection, so the tracking
   and collected-data-type arrays stay empty. Check the rest of the list
   (file timestamps, disk space, active keyboard) at implementation time — the
   app touches none of them, but the list itself is revised by Apple.
3. **A store build script**, `tools/store-build.sh`, alongside `build.sh`:
   same sources, sandbox entitlement, privacy manifest copied into the bundle,
   signed with *Apple Distribution*, wrapped with `pkgbuild`/`productbuild`.
   Keep the two scripts separate so the direct download keeps building exactly
   as it does today.
4. **A sandbox verification pass.** `verify.sh` currently covers maths, the audio
   graph and the UI render. The store build adds one manual smoke test on a
   sandboxed copy: launch it, play a tone, change the octave while it sounds,
   copy the readout, click both marks, cycle the appearance. Then repeat on a
   machine that has never seen the app, installed *from the store*.

## Certificates and profiles

Unlike Developer ID, **store certificates can be created by an Admin** — no
Aditya round trip:

- *Apple Distribution* — signs the app for App Store Connect;
- *Mac Installer Distribution* — signs the installer package.

One of each type per team. Create the **explicit App ID** for the bundle
identifier and a distribution provisioning profile. Account Holder only:
accepting updated agreements, membership renewal, and banking (irrelevant here,
the app is free).

Submission path needs no Xcode: `pkgbuild` + `productbuild` (already in the
Studio's Command Line Tools), then upload with **Transporter** (GUI), its
`iTMSTransporter` CLI, or App Store Connect's build-upload API. `altool` is
deprecated and not installed here. **Strip the `com.apple.quarantine` xattr from
every file before upload** — required by Apple since Feb 2025.

## Listing work (the friction is here, not in the code)

- App Store Connect record: name, subtitle, description, keywords, category
  (Music), age rating, copyright.
- **Support URL** that resolves. The README's "released as-is, no support"
  posture is a licence-and-docs posture, not store metadata: the listing needs a
  URL a reviewer can open. The repository or a page on hafodmastering.co.uk both
  work; the wording there should say what the app is and that issues can be
  reported, without promising maintenance.
- **Privacy policy URL — required for every app**, even one that collects
  nothing. A plain "this app collects no data" page is enough.
- App Privacy answers: "No, we do not collect data".
- macOS screenshots (one size required, several accepted — confirm current
  requirements at submission time) — the 0.96 light/dark renders are the natural
  source.
- **EU DSA trader status** — without it the app is pulled in the EU.
- Export compliance: no encryption beyond what the OS provides; the standard
  answer applies.

## Sequencing

1. **0.96 notarized, for Aditya's review** — done; it is a developer build, not a
   store candidate.
2. **Decisions** (below): bundle identifier, whether the store release *is* 1.0,
   who writes the support/privacy pages.
3. **Sandbox pass + privacy manifest + `store-build.sh`**, then `verify.sh` and
   the sandboxed smoke test. This is the only engineering, and it can happen
   before any Apple-side setup.
4. **Certs, App ID, profile** (Donal, Admin) and the App Store Connect record.
5. **Upload, then TestFlight** for Aditya and Gethin to install a real store
   build on their own machines before a public submission.
6. **Submit for review.** Expect metadata questions rather than code problems:
   the app is a self-contained native utility with no third-party SDKs and no
   data collection.
7. **Release.** Whether that lands as 1.0 or as 1.0.1 depends on decision 2.

## Open questions

- **Bundle identifier.** Today it is `com.donal.sasur` for the direct download.
  Options: keep the same identifier for the store (simplest, one identity to
  reason about), or register a Sudeep-owned identifier such as
  `com.sudeepaudio.sasur` for the store build (branding consistency, but the two
  channels are then formally different apps). Changing it after a public release
  forks app identity, so this is worth settling before 1.0 either way.
- **Is the store release the 1.0 moment?** The earlier recommendation was to
  ship the notarized GitHub 1.0 without waiting for App Review, and let the store
  follow as its own increment. If the store must *be* 1.0, then review timing
  gates the release date and the two channels launch together.
- **Support and privacy URLs.** Needed before submission; best decided by
  Hafod (Donal) even though the listing sits under the Sudeep team.
- **Versioning.** The store's version line is independent of the Git tags; the
  simplest is to keep the same numbers in both channels.

## Watch-outs

- The listing lives or dies with the Sudeep membership: a lapse pulls it from the
  store, while already-downloaded copies keep working.
- Every future store update is gated by App Review — the direct download is not.
- The Account Holder must keep accepting updated Program agreements, or the
  listing is removed.
- App Sandbox means the store build is **not** byte-identical to the GitHub
  artifact, so "1.0 is the same as 0.96 apart from the version string" holds for
  the GitHub channel only.
