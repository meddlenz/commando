# Notarizing Commando for Distribution

This guide covers building, notarizing, and stapling a Developer ID signed release of Commando for direct download.

## Prerequisites

- Apple Developer Program membership
- **Developer ID Application** certificate installed in your login keychain
- Xcode command line tools
- An [app-specific password](https://appleid.apple.com) for notarization (not your Apple ID password)

## One-time credential setup

Store notarization credentials in the keychain using a named profile:

```bash
xcrun notarytool store-credentials "Commando-Notary" \
  --apple-id "you@example.com" \
  --team-id "5D3622Q6DB" \
  --password "@keychain:AC_PASSWORD"
```

Replace:

- `you@example.com` with your Apple ID
- `AC_PASSWORD` with a keychain item containing your app-specific password

To store the app-specific password in Keychain Access: create a new password item named `AC_PASSWORD`, then reference it as `@keychain:AC_PASSWORD` above.

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

| Path | Description |
|------|-------------|
| `build/export/Commando.app` | Stapled, notarized app bundle |
| `build/Commando.dmg` | Stapled, notarized disk image for distribution |
| `build/Commando.xcarchive` | Xcode archive (intermediate) |

Upload `build/Commando.dmg` to your download server.

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
