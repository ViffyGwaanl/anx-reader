# Manual Backup/Restore via Files / iCloud Drive — Tech Design (PR-7)

## 0. Background

Anx Reader already has **Export/Import** in `Settings → Sync`:

- Export creates a ZIP (`AnxReader-Backup-YYYY-M-D-v3.zip`) containing:
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

Keep existing v3 layout but add:

- `manifest.json`

Example:

```json
{
  "schemaVersion": 4,
  "createdAt": 1730000000000,
  "containsEncryptedApiKey": true,
  "kdf": {
    "alg": "PBKDF2-HMAC-SHA256",
    "saltB64": "...",
    "iterations": 150000
  },
  "encryption": {
    "alg": "AES-256-GCM",
    "nonceB64": "..."
  },
  "encryptedApiKeyB64": "..."
}
```

Notes:
- Only store api key if user explicitly enables.
- Keep `anx_shared_prefs.json` but *remove* plain api key keys from it.

## 4. Crypto Details

- Use `package:crypto` for PBKDF2 (or implement using HMAC-SHA256)
- AES-GCM:
  - Prefer a vetted package if already in deps; otherwise consider adding one.
  - If adding deps is not desired, defer encryption to PR-7b.

## 5. Safe Restore Procedure

1. Validate ZIP structure and manifest.
2. Extract to temp dir.
3. Close DB and stop readers (`DBHelper.close()` etc.)
4. Copy files to staging/backup old local dirs (or rename old to `.bak`).
5. Replace DB:
   - remove WAL/SHM
   - copy new DB
   - reopen DB
6. Apply prefs backup map.
7. If encrypted api key included and password ok, apply key.
8. If any step fails: rollback using `.bak`.

## 6. Testing

- iOS: export to iCloud Drive; import from iCloud Drive
- Wrong password behavior
- Partial/corrupt ZIP handling
- Large library performance

