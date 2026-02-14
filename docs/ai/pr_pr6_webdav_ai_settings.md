# PR Draft — PR-6: WebDAV sync of AI settings (no API key)

## Title

Sync(WebDAV): add ai_settings.json snapshot sync (timestamp newer-wins; no api_key)

## Summary

This PR adds a **WebDAV-synced AI settings snapshot** to Anx Reader so that AI configuration and prompts can be shared across devices.

Security policy:

- **API keys are never synced** via WebDAV.

## Motivation / Background

Users often configure AI providers (base URL, model, prompt templates, UI preferences) on multiple devices. Today this is manual and error-prone.

Anx Reader already has WebDAV sync for the database and files; we extend that pipeline with a lightweight config file.

## Scope

### Included in sync

- selected AI service id
- per-service settings (e.g. url/model/headers) **excluding** `api_key`
- prompt template overrides (`AiPrompts`)
- user custom prompts
- input quick prompts
- AI UI prefs:
  - iPad panel mode (dock/bottomSheet)
  - dock side (left/right)
  - panel position (right/bottom)
  - dock width/height
  - bottom sheet size
  - font scale

### Excluded from sync

- `api_key` and any other secrets

## Design

- Remote path: `anx/config/ai_settings.json`
- Merge strategy (Phase 1): **whole-file snapshot** + `updatedAt` **newer-wins**
- Local timestamp: `Prefs().aiSettingsUpdatedAt`
  - bumped when **syncable** AI settings change
  - not bumped by `api_key` changes

## Implementation details

- Serializer/applier:
  - `lib/service/sync/ai_settings_sync.dart`
    - `buildLocalAiSettingsJson()`
    - `applyAiSettingsJson()`

- WebDAV integration:
  - `lib/providers/sync.dart`
    - add `syncAiSettings()`
    - call it from main `sync()` flow (independent of library/book list)

Security:

- Serialization removes `api_key`.
- Applying remote config preserves the local `api_key` per service.

## Testing

Manual test matrix:

1. Device A: set AI url/model/prompt overrides/quick prompts → run WebDAV sync.
2. Device B: run WebDAV sync → settings should match A.
3. Verify `api_key` on B remains unchanged.
4. Conflict test:
   - A changes a syncable field; B changes a syncable field.
   - Ensure the snapshot with newer `updatedAt` wins.

## Risks / Notes

- Syncing custom headers may carry secrets. Current behavior treats headers as syncable values. If this proves risky, we should add an allowlist or “safe headers” mechanism.

## Rollback

- Removing/ignoring `anx/config/ai_settings.json` will simply revert to device-local settings.
- Older clients will ignore unknown files and continue syncing DB/files.
