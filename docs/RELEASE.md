# Release runbook

How a SA-Sur release gets from this repository to a stranger's machine. Every
step here has to happen once, or once per release.

## Roles

| Who | Holds |
|---|---|
| **Aditya** | Sudeep Audio Apple Developer Program membership (Account Holder). The team ID, the Developer ID certificate, the Developer Program renewal |
| **Donal** | Signing certificate (his private key never leaves his Mac), notarization credentials, this repository |
| **Gethin** | Reviewer; recipient-side testing |

Copyright is joint (see `NOTICE`). macOS distribution is signed under the Sudeep
Audio Apple team, so **the publisher name users see in the Gatekeeper dialog is
`Sudeep Audio.com LLP`** (the team's registered name), and every future release
depends on that membership staying paid.

## Version numbering

Per release, bump `CFBundleShortVersionString` (and the monotonic
`CFBundleVersion`) in `Info.plist` and `VERSION` in `build.sh` **together**. The
Windows build carries its own number in `windows/SA-Sur.App/SaSur.App.csproj`,
and the two platforms release in step from the same tag.

---

## Step 1 — Aditya, once

All of this runs on the existing Sudeep Audio membership at no extra cost. The
Apple Developer Program has no per-seat fee, and there is no second subscription
to buy.

### 1a. Promote Donal to Admin

Apple's role matrix puts "Create Developer ID certificates" in the **Account
Holder** column only — a member with the *Developer* role cannot do it. Admin is a
free role change in App Store Connect. Required role to change a role: **Account
Holder or Admin**.

1. Sign in at **appstoreconnect.apple.com** as the Account Holder — the Apple
   Account that enrolled Sudeep Audio. Team roles live there, not on the developer
   website.
2. Open **Users and Access**.
3. Find Donal by Apple Account email. If he is not listed, the invitation he was
   sent may have expired — re-invite him as **Admin** rather than Developer, and
   have him accept it before continuing.
4. Click his user record, set **Roles → Admin**, and **Save**.
5. On the same record, enable **Access to Certificates, Identifiers & Profiles**.
   Admin is eligible for this, but it is a separate permission and off by default.
   Without it, Admin sees no certificates area at all.
6. If the account shows any outstanding updated agreement, accept it first —
   pending agreements can block access to Certificates, Identifiers & Profiles for
   the whole team.
7. Have Donal sign in at appstoreconnect.apple.com and confirm his role reads
   **Admin**.

Admin is also what lets him generate an App Store Connect API key (`Generate API
keys` is Account Holder **or Admin**), which is a better credential for automated
signing than an app-specific password.

**Do not bother with cloud-managed Developer ID certificates for this app.** Apple
documents cloud-managed signing as an *Xcode Organizer archive and distribution*
workflow, where Xcode cloud signs "if you're using the Xcode Organizer archive and
distribution workflow, and a local signing certificate is not found". SA-Sur is
built with `swiftc` and a hand-assembled bundle — no Xcode project, no Organizer
archive — and `codesign` needs a signing identity present in a keychain. So the
cloud-managed route cannot produce the signed bundle this build needs, whatever
the role says.

### 1b. Issue the Developer ID Application certificate

Only the Account Holder can create this (up to five *Developer ID Application*
certificates per team). Do it as a **CSR round-trip** so nothing secret ever
changes hands — Donal holds the private key from the start and only the public
request travels:

1. **Donal**, in Keychain Access → **Certificate Assistant → Request a Certificate
   from a Certificate Authority**: enter his email, a Common Name such as
   `Hafod Mastering Developer ID`, select **Saved to disk**, and save
   `DeveloperID.certSigningRequest`. His private key stays in his login keychain.
2. **Donal** sends the `.certSigningRequest` to Aditya. It is a public key — email
   is fine.
3. **Aditya**, at developer.apple.com → **Certificates, Identifiers & Profiles** →
   **Certificates** → **+** → **Developer ID Application** → upload the CSR →
   **Download** the issued `.cer`. If the **+** menu offers Donal Developer ID
   Application after promotion, he can do this step himself; Apple's docs say he
   should not be able to.
4. **Aditya** sends the `.cer` back. Also send the **Team ID** (10 characters)
   from the Membership details page. The Team ID for this project is
   **E37W7LU474**.
5. **Donal** double-clicks the `.cer`. It pairs with the private key already in his
   keychain, and the identity appears as
   `Developer ID Application: Sudeep Audio.com LLP (E37W7LU474)` — Apple issues it
   under the team's legal name, and that is the string `codesign` and
   `tools/notarize.sh` expect.

**Fallback, if Aditya would rather click once in Xcode than wait for a CSR**: he
can create the certificate in Xcode → Settings → Accounts → Manage Certificates →
**+ → Developer ID Application**, then Control-click the certificate → **Export
Certificate** → `.p12` with a strong password. Note that the private key then lives
in *his* keychain, so the `.p12` **and** its password must both reach Donal — over
a password manager, with the password sent through a different channel. A `.p12`
whose password travels in the same channel is a leak. The CSR route above avoids
this entirely and is preferable.

Either way this is a **once-every-five-years** action, not a per-release one: a
Developer ID certificate is valid for five years and Apple allows up to five of
them per team.

## Step 2 — Donal, once per machine

```sh
# 1. Import the certificate. With the CSR round-trip this is the .cer from Aditya,
#    which pairs with the private key already in your keychain. With the .p12
#    fallback it prompts for the password; nothing sensitive in shell history.
open ~/Downloads/DeveloperID.cer      # or DeveloperID.p12
security find-identity -v -p codesigning
#    expect: 1 valid identity -
#      "Developer ID Application: Sudeep Audio.com LLP (E37W7LU474)"

#    If the identity is listed but find-identity reports 0 *valid* identities,
#    the trust chain is broken: the machine is missing Apple's Developer ID
#    intermediate CA. It is public, not secret - download "Developer ID - G2"
#    from apple.com/certificateauthority (DeveloperIDG2CA.cer) and import it into
#    the login keychain. Prove the chain with a scratch signing test:
#      codesign --force --timestamp=none --sign "<identity>" /tmp/t
#      codesign -dvvv /tmp/t    # Authority lines should reach "Apple Root CA"

# 2. Store notarization credentials in the keychain. Use YOUR Apple ID with an
#    app-specific password from appleid.apple.com (Sign-In and Security >
#    App-Specific Passwords), and Sudeep's Team ID. Run this in your own
#    terminal; never paste the password anywhere else. It is validated against
#    Apple before it is saved.
xcrun notarytool store-credentials "notefrequency" \
    --apple-id "<your-apple-id>" \
    --team-id "E37W7LU474"
```

Notarizing needs no special role: Apple's matrix grants "Notarize software" to the
Account Holder, Admin, App Manager **and** Developer, so Donal's own Apple ID can
submit for notarization today. *Signing* is the part that needs the certificate.

The profile name `notefrequency` is what `tools/notarize.sh` reads — a keychain
label only, with no functional meaning. Override with the `NOTARY_PROFILE`
environment variable if you prefer another.

Housekeeping after a `.p12` import: delete the file from both machines and keep
exactly one offline copy in a password manager. Only the Account Holder can issue
a replacement certificate, so a lost private key is a problem for the whole team.

## Step 3 — Build and notarize, per release

Bump `CFBundleShortVersionString`/`CFBundleVersion` in `Info.plist` and
`VERSION` in `build.sh` **together** before starting.

```sh
./verify.sh                                                    # must be all green
./build.sh
./tools/notarize.sh "Developer ID Application: Sudeep Audio.com LLP (E37W7LU474)"
```

`notarize.sh` re-signs with the hardened runtime and a secure timestamp, submits
to Apple, staples the ticket, and repackages. Confirm the verdict it prints at the
end:

```
accepted, source=Notarized Developer ID
```

Anything else is a failed release; the raw `notarytool` log is the place to look.

## Step 4 — Publish

```sh
shasum -a 256 build/SA-Sur-<version>-notarized.zip
git commit -am "SA-Sur <version>"
git tag -a v<version> -m "SA-Sur <version>"
git push origin main --tags
```

Then create a GitHub Release at that tag, attach the **notarized** zip (the
repackaged one from step 3 — the ticket only travels inside an archive built
*after* stapling), and paste the SHA-256 into the release notes.

## Step 5 — Prove it, on a machine that has never seen the app

The whole point of notarization is the recipient's experience, and Gatekeeper only
assesses a file that carries the quarantine flag — so testing from a local copy
proves nothing.

1. Download the asset from the published Release page in a browser (not `scp`, not
   a network share — those do not add the quarantine attribute).
2. Unzip by double-clicking, drag to `/Applications`, launch.
3. Expect the ordinary "downloaded from the internet" confirmation, and no
   System Settings excursion. Confirm the publisher shown is `Sudeep Audio.com LLP`.

```sh
xattr -p com.apple.quarantine /Applications/SA-Sur.app   # should be present
spctl -a -vvv -t exec /Applications/SA-Sur.app           # accepted, source=Notarized Developer ID
```

If step 5 fails, the release is not published yet — delete the release and go back
to step 3.

---

## Windows

The Windows build is the same app in C# + Avalonia, carried by its own number in
`windows/SA-Sur.App/SaSur.App.csproj` and built, tested and packaged by
`.github/workflows/windows.yml` (`dotnet publish`, single-file, win-x64). Its
artifact ships from the same tag as the macOS zip, carries the same `LICENSE` and
`NOTICE`, and its release notes carry a SHA-256.

It is unsigned for now: an unsigned `.exe` plus a published hash is the same
trade macOS made before notarization, at £0, and a purchased certificate would
still warn until reputation accrues. The signing position — SignPath Foundation,
and what that signature does and does not prove — is in
[docs/CODE-SIGNING.md](CODE-SIGNING.md).

## If the collaboration changes

Existing releases keep working forever, whether or not the membership lapses.
What stops is the ability to sign and notarize **new** builds under the same team
identity. If Hafod Mastering later wants macOS releases not to depend on Sudeep
Audio's account and renewal, that means a second Apple Developer Program
membership and a new signing identity — worth knowing as a cost, not a blocker.
