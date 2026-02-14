# Implementation Plan (PR-6 / PR-7)

## PR-6 — WebDAV Sync of AI Settings (no API key)

### Work breakdown

1. **Schema + serializer**
   - [ ] Add `lib/service/sync/ai_settings_sync.dart`
   - [ ] Implement `buildLocalAiSettingsJson()`
   - [ ] Implement `applyAiSettingsJson()`
   - Acceptance: round-trip serialize/deserialize works; api_key excluded.

2. **WebDAV file transport integration**
   - [ ] Add remote path `anx/config/ai_settings.json`
   - [ ] Extend `lib/providers/sync.dart` `sync()` to upload/download (do not depend on book list)
   - [ ] Whole-file `updatedAt` conflict resolution (Phase 1)

3. **Migration / Backward compatibility**
   - [ ] Missing/invalid JSON: log + skip
   - [ ] Unknown schemaVersion: skip

4. **Testing**
   - [ ] A→B sync: model/url/prompts/ui prefs arrive
   - [ ] api_key untouched on B
   - [ ] conflict: newer wins

### Risks

- Storing headers may include secrets → default to **not syncing headers** unless explicitly marked safe (optional enhancement).

---

## PR-7 — Manual Backup/Restore Enhancements (Files/iCloud)

### Work breakdown

1. **Clarify UX copy**
   - [ ] Update Settings labels (export/import wording)
   - [ ] Add explicit overwrite confirmation on import

2. **Package versioning**
   - [ ] Add `manifest.json` to exported ZIP (schemaVersion=4)
   - [ ] Ensure importer still supports legacy v3 (no manifest)

3. **Optional encrypted API key**
   - [ ] Add UI toggle + password prompts
   - [ ] Implement PBKDF2 + AES-GCM
   - [ ] Store encrypted blob in manifest
   - [ ] Import decrypt + apply

4. **Safe restore**
   - [ ] Staging + rollback
   - [ ] WAL/SHM cleanup for DB

5. **Testing**
   - [ ] iOS Files: iCloud Drive export/import
   - [ ] wrong password
   - [ ] corrupt zip

### Risks

- Crypto implementation mistakes → prefer vetted dependency; add test vectors.
- iCloud file provider deadlocks on some versions → ensure operations are async + timeouts + user feedback.

