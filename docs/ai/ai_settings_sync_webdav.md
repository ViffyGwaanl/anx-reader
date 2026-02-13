# AI Settings Sync via WebDAV — Tech Design (PR-6)

## 0. Background

Anx Reader already supports WebDAV sync for:

- database backup/restore (DB replacement)
- book files / covers / other assets (via `syncFiles()`)

We want AI-related configuration to be **portable across devices**, but with strict security rules:

- ✅ Sync model/url/headers/prompts/settings
- ❌ Do **NOT** sync API keys via WebDAV

## 1. Goals

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

### Strategy

- Download remote file if exists.
- Compare `updatedAt`:
  - if remote newer → apply remote into local prefs
  - if local newer → upload local
  - if equal → no-op

### Why timestamp

- Simple and predictable.
- Matches Anx Reader's current “replace DB” style.

### Optional future enhancement

- Field-level merge (e.g., merge userPrompts by id), but defer unless needed.

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
  - in `syncFiles()`:
    - upload local ai_settings.json
    - download remote ai_settings.json

Ordering recommendation:

- Download first, possibly apply to local
- Then upload local if local wins

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

