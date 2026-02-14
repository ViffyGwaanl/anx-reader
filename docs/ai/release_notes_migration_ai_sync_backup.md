# Release Notes / Migration Notes — AI sync & backup

This note summarizes user-visible behavior changes introduced by PR-6 (WebDAV AI settings sync), PR-7 (Backup v4 + optional encrypted API keys), and PR-8 (Reading/AI UX hotfix).

## PR-6 — WebDAV AI settings sync (no API key)

### What users get

- AI configuration (url/model/prompts/UI prefs) can be synced via WebDAV.
- This reduces repetitive setup across devices.

### Security policy

- **API keys are not synced** via WebDAV.

### Merge semantics

- Phase 1: whole-file snapshot `updatedAt` newer-wins.
- If two devices change settings, the snapshot with newer timestamp overwrites the other.

### Troubleshooting

- If you see “model not found” after a sync, it usually means a newer snapshot overwrote your url/model pair. Reconfigure the desired provider and sync again.

## PR-7 — Manual backup/restore v4 (Files/iCloud) + optional encrypted API keys

### What users get

- Export creates a `-v4.zip` backup including `manifest.json`.
- Optionally include API keys **encrypted** with a password.
- Import shows a warning confirmation and performs rollback-safe restore.

### Security policy

- Plain prefs backup file `anx_shared_prefs.json` **never contains** `api_key`.
- Importing a backup **never overwrites/clears** existing local API keys.
- API keys are only restored when:
  - the backup was created with encrypted API keys enabled, and
  - the correct password is provided during import.

### Password recovery

- Password cannot be recovered. If forgotten, encrypted API keys cannot be restored.

### Backward compatibility

- Importing older v3 backups remains supported.
- Older app versions importing v4 backups:
  - may restore files/db/prefs
  - will ignore/skip encrypted API key restoration (expected)

### Failure recovery

- Import creates `.bak.<timestamp>` backups and rolls back if any step fails.

## PR-8 — Reading/AI UX hotfix

### What users get

- AI font scale popup is stable (no auto-dismiss while trying to adjust).
- Bottom sheet AI chat opens at a large fixed height (~95%) to reduce resize frustration.
- In bottom-sheet mode, swipe up from the lower-middle of the reading page to open AI (no need to open the menu first).
- Bookshelf layout avoids 1px overflow warnings on some devices.

## Recommended user guidance

- Use WebDAV sync for day-to-day config sync.
- Use v4 backup export/import for device migration and offline safety.
- Do not paste API keys into chat logs; treat leaked keys as compromised and rotate them.
