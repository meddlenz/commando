# Commando licensing

Commando uses **Ed25519-signed registration keys** verified offline in the app, with optional **server ban checks** and **integrity tamper reporting**. The license key itself is not device-bound; users can re-enter the same key on another Mac.

## Layout

```
Commando/Licensing/
  LicenseKey.swift           Ed25519 verify + COMMANDO1 wire format (mirrored in MSW Keygen)
  LicenseSecrets.swift       Obfuscated embedded public key (production key goes here)
  LicenseStatus.swift        Registration, revocation cache, feature gates
  LicenseGuard.swift         Code-sign + unlock/sentinel integrity checks
  LicenseRemoteCheck.swift   Ban check + tamper report HTTP client
  LicenseEndpoints.swift     Obfuscated server URLs
  RegistrationKeychain.swift Device-local AES key for registration.dat
  AppLock.swift              Force-update lock from commando.xml
```

Related repos:

- **MSW Keygen** — generate keys and export the obfuscated public key for `LicenseSecrets.swift`
- **legacyai-proxy** (`licenses/`) — Stripe issuance, ban list, activation/tamper audit logs

## Production key setup

Do this once before shipping a build that validates real customer keys.

### 1. Generate an Ed25519 keypair on the server

```bash
cd /root/legacyai-proxy
./.venv/bin/pip install -r requirements.txt   # includes cryptography
./.venv/bin/python -m licenses.ed25519_license gen-keypair
```

Save the output. **Never commit the private key.**

Set on the VPS (supervisor `environment=` for `legacyai`, or your secrets store):

| Variable                       | Purpose                                                         |
| ------------------------------ | --------------------------------------------------------------- |
| `COMMANDO_LICENSE_PRIVATE_KEY` | 32-byte seed, base64 (or PEM) — signs keys at Stripe checkout   |
| `COMMANDO_LICENSE_PUBLIC_KEY`  | Optional if private key is set; used for verification on server |

Restart after changing env:

```bash
sudo supervisorctl restart legacyai
```

### 2. Embed the public key in Commando

1. Open **MSW Keygen**.
2. Paste the **public key** (base64) from step 1.
3. Click **Copy unfolded section**.
4. Replace the `unfolded` property body in `Commando/Licensing/LicenseSecrets.swift` with the copied block.

The app only ships the **public** key, XOR-obfuscated. The private key stays on the server.

### 3. Verify cross-language vectors

```bash
cd /path/to/legacyai-proxy
./.venv/bin/python -m licenses.test_ed25519_license
```

In Xcode, run `CommandoTests` — license vector tests should pass.

### 4. Stripe (if not already configured)

Server env also needs `COMMANDO_STRIPE_PRICE_ID`, `STRIPE_WEBHOOK_SECRET`, and SMTP vars. See `legacyai-proxy/licenses/README.md`.

## Registration key format

Wire format:

```
COMMANDO1.<base64url-payload>.<base64url-signature>
```

Payload JSON (canonical field order on sign/verify):

```json
{
  "email": "...",
  "id": "ZSR9AWMFSW38",
  "issued": 1724140800,
  "name": "Pat Example",
  "v": 1
}
```

- **`id`** — 12-character ban/revocation token (derived from signature)
- Keys are validated locally with the embedded public key; name and email must match the payload exactly (case-sensitive name, lowercased email).

## Server endpoints

| Method | Path                         | Purpose                          |
| ------ | ---------------------------- | -------------------------------- |
| GET    | `/legacyai/commando/license` | Ban check + activation audit log |
| POST   | `/legacyai/commando/report`  | Tamper reports                   |

Query/body includes `token` (12-char ban ID), `version`, and `reason`/`detail`.

Ban list file on server: `banned-commando.txt` (one token per line; `#` comments allowed).

Auto-ban on tamper reports is **on by default** (`COMMANDO_AUTO_BAN_TAMPER=0` to disable).

## Runtime behavior

### Offline-friendly activation

- Valid keys work without network access.
- Ban checks run at registration and periodically (~24h). If the server is unreachable, a previously valid license keeps working unless it was **already** cached as revoked.

### Fail-closed revocation

Once banned/revoked, the app caches `cachedRevoked: true` in encrypted `registration.dat` and stays locked offline.

### Force update

`UpdateChecker` reads `minimumVersionAllowed` from `commando.xml`. When the installed version is too old, `AppLock` blocks registration and paid features until the user updates.

### Free vs paid features

Unregistered users can use a limited subset (first command set, single session). Paid actions call `LicenseGuard.permits(...)` and `LicenseStatus.ensureCan*`.

## Tamper detection

Tamper checks are **not** a CRC or checksum of the app binary, and they do **not** inspect whether specific functions were NOP’d out or hooked at the machine-code level.

Instead, `LicenseGuard` runs **runtime consistency checks** — essentially: _does the app still look signed, and do all the unlock signals still agree?_

| Check                 | What it detects                                                                                                                                   | Report detail       |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------- |
| **Code signature**    | Binary modified or re-signed outside your Developer ID pipeline (`SecStaticCodeCheckValidity` on the app bundle)                                  | `codesign_invalid`  |
| **Unlock mismatch**   | `isUnlocked` patched to `true` without a cryptographically valid stored key (recomputes unlock from `LicenseKey.isValid` vs public `isUnlocked`)  | `unlock_mismatch`   |
| **Sentinel mismatch** | Unlock flags flipped but Keychain sentinel not updated (`SHA256("commando.sentinel.v1" + "unlocked"\|"locked")` written on license state changes) | `sentinel_mismatch` |

**When checks run**

- **Startup** — `LicenseStatus.runStartupIntegrityCheck()` reports to the server but does not block launch.
- **Gated actions** — `LicenseGuard.permits(...)` runs checks before paid features (run commands, extra sessions, import, etc.). Failure blocks the action.

**On failure**

The app POSTs a tamper report to `/legacyai/commando/report`. The server logs it and may **auto-ban** the license’s 12-character ID (`COMMANDO_AUTO_BAN_TAMPER` is on by default).

## Manual ban

Add the 12-character ban ID (shown in MSW Keygen as **Ban ID**) to `banned-commando.txt` on the VPS, one per line:

```
ZSR9AWMFSW38
```

Clients pick this up on the next ban check (registration or periodic refresh).

## Local registration storage

Encrypted file (not the license key itself):

```
~/Library/Containers/com.manticoresw.commando/Data/Library/Application Support/Commando/registration.dat
```

Encryption uses a **device-local Keychain key** (`RegistrationKeychain`). The file is not portable to another Mac; users re-enter name, email, and key on a new machine.

## Testing

Unit tests live in `CommandoTests/CommandoTests.swift`. Useful overrides:

- `LicenseGuard.skipIntegrityChecks` — disable integrity checks in tests
- `LicenseRemoteCheck.skipNetwork` — skip HTTP
- `LicenseKey.publicKeyOverride` — test vectors without touching `LicenseSecrets`

Run **Product → Test** in Xcode or:

```bash
xcodebuild test -scheme Commando -destination 'platform=macOS'
```

## Shipping checklist

- [ ] Production Ed25519 keypair generated; private key only on VPS
- [ ] `LicenseSecrets.swift` updated from MSW Keygen unfolded export
- [ ] `licenses.test_ed25519_license` and Commando license tests pass
- [ ] Stripe + SMTP env configured on server
- [ ] `commando.xml` `minimumVersionAllowed` set appropriately for release
- [ ] Release build signed and notarized (see `/NOTARIZATION.md`)
