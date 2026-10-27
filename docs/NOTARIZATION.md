# Notarizing Commando for Distribution

This guide covers building, notarizing, and stapling a Developer ID signed release of Commando for direct download.

## Prerequisites

- Apple Developer Program membership
- **Developer ID Application** certificate installed in your login keychain (not Developer ID *Installer* — that is for `.pkg` files only)
- **Developer ID provisioning profiles** for `com.manticoresw.commando` and `com.manticoresw.commando.loginitem` (the script can create these automatically; see Troubleshooting if export fails)
- Xcode command line tools
- An [app-specific password](https://appleid.apple.com) for notarization (not your Apple ID password)

## One-time credential setup

Store notarization credentials in the keychain using a named profile:

```bash
xcrun notarytool store-credentials "Commando-Notary" \
  --apple-id "jordan@meddle.co.nz" \
  --team-id "5D3622Q6DB" \
  --password "@keychain:AC_PASSWORD"
```

Replace `@keychain:AC_PASSWORD` with your app-specific password directly if you prefer not to use Keychain Access:

```bash
xcrun notarytool store-credentials "Commando-Notary" \
  --apple-id "jordan@meddle.co.nz" \
  --team-id "5D3622Q6DB" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

Or store the password in Keychain Access first:

- Select the **login** keychain
- File → **New Password Item**
- **Keychain Item Name:** `AC_PASSWORD`
- **Account Name:** your Apple ID (e.g. `jordan@meddle.co.nz`)
- **Password:** the app-specific password from [appleid.apple.com](https://appleid.apple.com) (not your Apple ID login password)

Then use `--password "@keychain:AC_PASSWORD"` in the `store-credentials` command above.

Verify the profile was saved:

```bash
xcrun notarytool history --keychain-profile "Commando-Notary"
```

## Build, notarize, and staple

From the repo root:

```bash
chmod +x Scripts/notarize.sh   # first time only
./Scripts/notarize.sh
```

The script will:

1. Archive and export a Release build signed with Developer ID
2. Create `build/Commando.dmg` with `Commando.app` and an **Applications** shortcut
3. Submit the DMG to Apple notarization and wait for approval
4. Staple the ticket to both the DMG and exported app
5. Verify with `stapler validate` and `spctl`

## Output artifacts

| Path                        | Description                                    |
| --------------------------- | ---------------------------------------------- |
| `build/export/Commando.app` | Stapled, notarized app bundle                  |
| `build/Commando.dmg`        | Stapled, notarized disk image for distribution |
| `build/Commando.xcarchive`  | Xcode archive (intermediate)                   |

Upload `build/Commando.dmg` to your download server. You can rename the DMG after notarization and stapling (e.g. `commando-1.0.0.dmg`) without invalidating the ticket — only re-notarize if you change the contents.

## Configuration

Optional environment variables:

```bash
NOTARY_PROFILE="Commando-Notary"   # keychain profile name
SCHEME="Commando"                  # Xcode scheme
CONFIGURATION="Release"            # build configuration
TEAM_ID="5D3622Q6DB"               # Apple Developer team ID
```

Example:

```bash
NOTARY_PROFILE="My-Notary-Profile" ./Scripts/notarize.sh
```

## Manual verification

After the script completes, double-check on the build machine:

```bash
xcrun stapler validate build/Commando.dmg
spctl -a -vv build/export/Commando.app
codesign -dv --verbose=4 build/export/Commando.app
```

On a clean Mac (or another user account), mount the DMG and confirm Gatekeeper accepts the app without a warning.

## Troubleshooting

### Export failed: No signing certificate "Developer ID Application" found

Install a **Developer ID Application** certificate from [Certificates](https://developer.apple.com/account/resources/certificates/list) (+ → Developer ID Application). Developer ID *Installer* cannot sign `.app` bundles.

Verify:

```bash
security find-identity -v -p codesigning
```

You should see `Developer ID Application: … (5D3622Q6DB)`.

### Export failed: No profiles for `com.manticoresw.commando` were found

Sandboxed Mac apps need a **Developer ID** provisioning profile, not just the certificate. The notarize script passes `-allowProvisioningUpdates` so Xcode can create profiles automatically (requires network access and Apple Developer login).

If that still fails, create profiles manually at [Profiles](https://developer.apple.com/account/resources/profiles/list):

1. **+** → **Developer ID** → App ID `com.manticoresw.commando` → your Developer ID Application cert → Download → double-click to install
2. Repeat for `com.manticoresw.commando.loginitem` (login item helper)

Ensure the App ID has **App Sandbox** and **iCloud** (`iCloud.com.manticoresw.commando`) enabled under [Identifiers](https://developer.apple.com/account/resources/identifiers/list).

### Notarization rejected: unsigned or invalid embedded binary

Commando embeds a login item helper at `Contents/Library/LoginItems/CommandoLoginItem.app`. Both the main app and helper must be signed with hardened runtime. Rebuild from a clean archive; do not modify the exported app before submission.

### Notarization rejected: entitlements

Compare entitlements with what you expect:

```bash
codesign -d --entitlements :- build/export/Commando.app
codesign -d --entitlements :- build/export/Commando.app/Contents/Library/LoginItems/CommandoLoginItem.app
```

### `notarytool` authentication failed

- Confirm the keychain profile name matches `NOTARY_PROFILE`
- Regenerate the app-specific password if it was revoked
- Ensure `--team-id` matches your Developer ID team (`5D3622Q6DB`)

### View notarization log for a submission

```bash
xcrun notarytool log <submission-id> --keychain-profile "Commando-Notary"
```

Find submission IDs with:

```bash
xcrun notarytool history --keychain-profile "Commando-Notary"
```

### Stapler fails

Notarization must complete successfully before stapling. If you submitted manually without `--wait`, poll history until status is **Accepted**, then run:

```bash
xcrun stapler staple build/Commando.dmg
xcrun stapler staple build/export/Commando.app
```
