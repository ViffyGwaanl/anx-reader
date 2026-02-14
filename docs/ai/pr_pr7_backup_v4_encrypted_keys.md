# PR Draft — PR-7: Backup v4 + optional encrypted API keys + safe import rollback

## Title

Backup v4: optional encrypted API keys + safe import rollback

## Summary

This PR enhances manual backup/restore (Export & Import) by:

- exporting a **v4 backup ZIP** with `manifest.json`
- optionally including AI API keys **encrypted** (password-based)
- adding an import confirmation dialog
- adding a **rollback-safe import** procedure using `.bak.<timestamp>` backups

## Motivation / Background

The existing Export/Import flow is already close to “manual iCloud Drive backup” (Files picker can access iCloud). However:

- users need an explicit and safe way to migrate AI credentials across Apple devices
- import is a destructive operation; failure mid-restore can leave the app in a half-restored state

We address both problems while keeping WebDAV policy intact (WebDAV never syncs API keys).

## Scope

### Changes

1. Backup ZIP versioning:
   - export filename suffix: `-v4.zip`
   - add `manifest.json` at ZIP root

2. Encrypted API key inclusion (optional):
   - export dialog toggle: “Include API key (encrypted)”
   - password prompt (enter + confirm)
   - import reads manifest; prompts for password; decrypts and restores api keys

3. Safety:
   - `anx_shared_prefs.json` (prefs backup) **never contains** plain `api_key`
   - prefs restore **never overwrites/clears** local `api_key`
   - only encrypted manifest can restore api keys

4. Import reliability:
   - pre-import confirmation (“will overwrite local data”)
   - in-place backup (rename) + rollback on failure

## Crypto design

- KDF: PBKDF2-HMAC-SHA256
  - 150000 iterations
  - 16-byte random salt
- Cipher: AES-256-GCM
  - 12-byte random nonce
  - 16-byte tag

Implementation uses `package:cryptography`.

## Backup format (v4)

`manifest.json` example:

```json
{
  "schemaVersion": 4,
  "createdAt": 1730000000000,
  "containsEncryptedApiKeys": true,
  "encryptedApiKeys": {
    "kdf": {
      "alg": "PBKDF2-HMAC-SHA256",
      "saltB64": "...",
      "iterations": 150000
    },
    "encryption": {
      "alg": "AES-256-GCM",
      "nonceB64": "..."
    },
    "cipherTextB64": "..."
  }
}
```

Plain prefs backup remains `anx_shared_prefs.json`.

## Implementation details

- UI / flow:
  - `lib/page/settings_page/sync.dart`
    - export dialog + manifest generation
    - import confirmation
    - decrypt+apply api keys
    - rollback-safe restore (rename `.bak.<timestamp>`)

- Prefs security:
  - `lib/config/shared_preference_provider.dart`
    - backup: strip `api_key` from `aiConfig_*`
    - restore: preserve existing `api_key`

- Crypto:
  - `lib/utils/crypto/backup_crypto.dart`

- Unit tests:
  - `test/service/backup_crypto_test.dart`

## Testing

Manual:

1) Export v4 without encrypted keys → Import:
   - app restores files/db/prefs
   - local api keys remain unchanged

2) Export v4 with encrypted keys → Import:
   - correct password: api keys restored
   - wrong password: show error; api keys not modified
   - skip: api keys not modified

3) Failure rollback:
   - use a corrupted ZIP or remove a directory from ZIP
   - import should rollback using `.bak.<timestamp>` (no half-restored state)

Unit:

- `flutter test test/service/backup_crypto_test.dart`

## Backward compatibility

- Importing legacy v3 ZIPs: still supported (no `manifest.json`)
- Exported v4 ZIPs:
  - older clients may ignore `manifest.json` and restore remaining content
  - encrypted keys won’t be restored on older versions (expected)

## Risks / Notes

- Password is not recoverable; UX copy must warn users.
- Encrypted key restore is best-effort; do not block importing the rest of the backup.

## Rollback

- Export/import remains optional. Users can continue using legacy behavior.
- In case of import errors, rollback restores prior state.
