# AI Settings Sync via WebDAV — Tech Design (PR-6)

## 0. Background

Anx Reader already supports WebDAV sync for:

- database backup/restore (DB replacement)
- book files / covers / other assets (via `syncFiles()`)

We want AI-related configuration to be **portable across devices**, but with strict security rules:

- ✅ Sync model/url/headers/prompts/settings
- ❌ Do **NOT** sync API keys via WebDAV

## 1. Implementation Status

- Implemented in fork branch: `feat/ai-settings-webdav-sync`
- Key files:
  - `lib/service/sync/ai_settings_sync.dart` (schema v1 serializer + applier)
  - `lib/providers/sync.dart` (`syncAiSettings()` called from the main sync flow)
- Merge strategy: Phase 1 whole-file `updatedAt` newer-wins

## 2. Goals

1. Sync AI settings across devices using the existing WebDAV infrastructure.
2. Preserve backward compatibility (older versions ignore the new config file).
3. Support simple conflict resolution.

## 2. Data to Sync (explicit)

### Include

- Selected AI service id
- Service configs **excluding** `api_key` (keep `url`, `model`, optional headers)
- Prompt templates (`ai_prompts` overrides)
- User custom prompts
- Input quick prompts
- AI panel UI prefs:
  - iPad panel mode, dock side
  - dock width/height
  - bottom sheet initial size
  - font scale

### Exclude

- `api_key`
- tokens / auth secrets

## 3. Storage Format

### Remote path

- `anx/config/ai_settings.json`

### JSON schema (v1)

```json
{
  "schemaVersion": 1,
  "updatedAt": 1730000000000,
  "selectedServiceId": "openai",
  "services": {
    "openai": {
      "url": "...",
      "model": "...",
      "headers": {"X-Foo": "Bar"}
    }
  },
  "prompts": {
    "summaryTheChapter": "...",
    "translate": "..."
  },
  "userPrompts": [
    {"id": "...", "name": "...", "content": "...", "enabled": true}
  ],
  "inputQuickPrompts": [
    {"id": "...", "label": "...", "prompt": "...", "enabled": true, "order": 0}
  ],
  "ui": {
    "aiPadPanelMode": "dock",
    "aiDockSide": "right",
    "aiPanelPosition": "right",
    "aiPanelWidth": 300,
    "aiPanelHeight": 300,
    "aiSheetInitialSize": 0.6,
    "aiChatFontScale": 1.0
  }
}
```

Notes:
- `updatedAt` uses epoch millis.
- Unknown keys should be ignored.

## 4. Merge / Conflict Resolution

### Strategy (Phase 1 — chosen)

**Whole-file snapshot** + timestamp resolution.

- Download remote file if exists.
- Compare `updatedAt`:
  - if remote newer → apply remote into local prefs (overwrite local snapshot)
  - if local newer → upload local snapshot (overwrite remote)
  - if equal → no-op

This is the most predictable behavior and lowest implementation risk for the first iteration.

Implementation detail:

- Local timestamp is tracked in `Prefs().aiSettingsUpdatedAt`.
- It is bumped when **syncable AI settings** change (service url/model/headers, prompts, quick prompts, UI prefs), but **not** when `api_key` changes.

### Why timestamp

- Simple and predictable.
- Matches Anx Reader's current “replace DB” style.

### Optional future enhancement (Phase 2)

- Field-level merge (e.g., merge userPrompts / quickPrompts by id)
- Deletion propagation (tombstones)
- Per-item updatedAt

**Custom providers / advanced fields** (planned):

- Support multiple OpenAI-compatible providers (custom entries).
- Sync non-secret fields for custom providers (url/model/headers/params).
- Continue to exclude api_key from WebDAV sync.

Defer until we see real conflict pain in the wild.

## 5. Implementation Plan

### 5.1 Create a serializer layer

Add a small module:

- `lib/service/sync/ai_settings_sync.dart`
  - `buildLocalAiSettingsJson()`
  - `applyAiSettingsJson(Map)`

This isolates schema evolution from sync transport.

### 5.2 Hook into WebDAV sync

Modify:

- `lib/providers/sync.dart`
  - add `syncAiSettings()` and call it from the main `sync()` flow (after DB sync; before/independent of book file sync)

Ordering recommendation:

- Download remote `ai_settings.json` first (if present)
- Compare `updatedAt`
- Apply remote if it wins; otherwise upload local snapshot

Rationale:

- AI settings sync must **not depend on the book list**. Even if the library is empty, AI config should still sync.

### 5.3 Backward compatibility

- If file missing: skip.
- If JSON invalid: log + skip.
- If schemaVersion unknown: skip.

## 6. Security Considerations

- Ensure `api_key` is removed before serialization.
- Consider redaction in logs (do not print headers that may contain secrets).

## 7. Testing

- Fresh device A: configure model/url/prompts → sync
- Device B: sync → settings applied; api_key untouched
- Conflict: change on both devices, newer wins

