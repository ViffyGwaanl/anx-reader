# Manual Backup/Restore via Files / iCloud Drive — Tech Design (PR-7)

## 0. Implementation Status

- Implemented in fork branch: `feat/backup-restore-encrypted-api-key-squashed`
- Adds:
  - v4 backup ZIP with `manifest.json`
  - optional encrypted API keys
  - import confirmation + rollback using `.bak.<timestamp>`

## 1. Background

Anx Reader already has **Export/Import** in `Settings → Sync`:

- Export creates a ZIP (legacy: `...-v3.zip`; fork enhancement: `...-v4.zip`) containing:
  - documents assets (file/cover/font/bgimg)
  - database dir
  - shared prefs backup map (`anx_shared_prefs.json`)
- Import picks a ZIP via `file_picker` and then **overwrites local** data.

This is already close to “manual iCloud backup/restore” on iOS because the Files picker can access iCloud Drive.

## 1. Goals (enhancements)

1. Make the feature iCloud-friendly and explicit in UX copy.
2. Offer **directional overwrite** clarity:
   - Local → iCloud (export)
   - iCloud → Local (import)
3. Optional: include API key **encrypted** (password-based), for Apple-only migration.
4. Safe restore with rollback and WAL cleanup (reuse DB replacement approach).

## 2. UX Design

### Entry

`Settings → Sync → Export & Import`

- Export: “Export backup to Files/iCloud Drive”
- Import: “Import backup from Files/iCloud Drive (overwrite local)”

### Import confirmation

- Show a clear warning:
  - local database and files will be replaced
  - API keys are *not* restored unless user chose encrypted key inclusion

### Encrypted API key option

On Export:

- Toggle: “Include API key (encrypted)”
- If enabled:
  - prompt for password (twice)
  - store `encrypted_api_key` blob in manifest

On Import:

- If manifest indicates encrypted API key:
  - prompt for password
  - decrypt and apply

## 3. Backup Package Format (v4)

Export produces a v4 ZIP (filename suffix `-v4.zip`) and adds:

- `manifest.json` (schemaVersion = 4)

Example (as implemented in the fork):

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

Notes:
- API keys are only stored if the user explicitly enables the option.
- `anx_shared_prefs.json` never contains plain `api_key` entries.

## 4. Crypto Details

Implementation (fork): uses `package:cryptography`.

- KDF: PBKDF2-HMAC-SHA256, 150000 iterations, 16-byte salt
- Cipher: AES-256-GCM, 12-byte nonce, 16-byte tag

## 5. Safe Restore Procedure

1. Validate ZIP structure and manifest.
2. Extract to temp dir.
3. Close DB and stop readers (`DBHelper.close()` etc.)
4. **In-place backup** existing local dirs by renaming to `.bak.<timestamp>` (cheap + same filesystem):
   - documents: `file/ cover/ font/ bgimg`
   - databases dir
5. Copy extracted dirs into the original locations.
6. Reopen DB.
7. Apply prefs backup map.
8. If encrypted api key included and password ok, apply key.
9. If any step fails: rollback by deleting partial new dirs and renaming `.bak.*` back.

Implementation status (fork): this rollback approach is implemented in PR-7 branch.

## 6. Testing

- iOS: export to iCloud Drive; import from iCloud Drive
- Wrong password behavior
- Partial/corrupt ZIP handling
- Large library performance

