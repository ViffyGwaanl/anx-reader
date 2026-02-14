# Implementation Plan (PR-6 / PR-7)

## PR-6 — WebDAV Sync of AI Settings (no API key)

### Work breakdown

Implementation branch: `feat/ai-settings-webdav-sync`

1. **Schema + serializer**
   - [x] Add `lib/service/sync/ai_settings_sync.dart`
   - [x] Implement `buildLocalAiSettingsJson()`
   - [x] Implement `applyAiSettingsJson()`
   - Acceptance: round-trip serialize/deserialize works; api_key excluded.

2. **WebDAV file transport integration**
   - [x] Add remote path `anx/config/ai_settings.json`
   - [x] Extend `lib/providers/sync.dart` `sync()` to upload/download (do not depend on book list)
   - [x] Whole-file `updatedAt` conflict resolution (Phase 1)

3. **Migration / Backward compatibility**
   - [x] Missing/invalid JSON: log + skip
   - [x] Unknown schemaVersion: skip

4. **Testing**
   - [ ] A→B sync: model/url/prompts/ui prefs arrive
   - [ ] api_key untouched on B
   - [ ] conflict: newer wins

### Risks

- Storing headers may include secrets → default to **not syncing headers** unless explicitly marked safe (optional enhancement).

---

## PR-7 — Manual Backup/Restore Enhancements (Files/iCloud)

### Work breakdown

Implementation branch: `feat/backup-restore-encrypted-api-key-squashed`

1. **Clarify UX copy**
   - [ ] Update Settings labels (export/import wording)
   - [x] Add explicit overwrite confirmation on import

2. **Package versioning**
   - [x] Add `manifest.json` to exported ZIP (schemaVersion=4)
   - [x] Ensure importer still supports legacy v3 (no manifest) (best-effort; v3 has no manifest)

3. **Optional encrypted API key**
   - [x] Add UI toggle + password prompts
   - [x] Implement PBKDF2 + AES-GCM
   - [x] Store encrypted blob in manifest
   - [x] Import decrypt + apply

4. **Safe restore**
   - [x] Staging + rollback (rename `.bak.<timestamp>`)
   - [ ] WAL/SHM cleanup for DB (optional)

5. **Testing**
   - [ ] iOS Files: iCloud Drive export/import
   - [x] wrong password (unit test + UI path)
   - [ ] corrupt zip

### Risks

- Crypto implementation mistakes → prefer vetted dependency; add test vectors.
- iCloud file provider deadlocks on some versions → ensure operations are async + timeouts + user feedback.

