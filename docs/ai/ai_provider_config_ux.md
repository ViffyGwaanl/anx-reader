# AI Provider Center / Provider Configuration UX (Cherry-inspired, Flutter-native)

## 0. Status

**Implemented (fork).**

This doc is no longer just a proposal; it documents the current Provider Center architecture + the remaining planned enhancements.

> License note: Cherry Studio App is AGPL-3.0, Anx Reader is MIT. We only reuse UX ideas/patterns, no code.

---

## 1. Current State (fork)

### 1.1 Information architecture

- Settings top-level: “AI Provider Center” (parallel to AI settings)
- Pages:
  - Provider list page
  - Provider detail/edit page

Key code:

- Provider Center UI:
  - `lib/page/settings_page/ai_provider_center/ai_provider_center_page.dart`
  - `lib/page/settings_page/ai_provider_center/ai_provider_detail_page.dart`
- Provider meta model:
  - `lib/models/ai_provider_meta.dart`
- Storage:
  - `lib/config/shared_preference_provider.dart`

### 1.2 Storage model (security split)

We store **non-secret provider metadata** separately from **secret config**:

- Provider metas (non-secret): `aiProvidersV1`
  - name/type/enabled/logo/createdAt/updatedAt
- Per-provider config (may include secrets locally): `aiConfig_<providerId>`
  - URL/baseUrl/model/headers/etc
  - `api_key` is stored locally, but:
    - NOT synced via WebDAV
    - NOT included in plaintext backups
    - only included in manual backup when encrypted
- Models cache (ephemeral, excluded from backups): `aiModelsCacheV1_<providerId>`

### 1.3 Runtime mapping

- `Prefs().selectedAiService` stores the **provider id** (built-in id or custom uuid)
- At runtime we map provider meta.type → stable LangChain registry id:
  - OpenAI-compatible → `openai`
  - Anthropic → `claude`
  - Gemini → `gemini`

---

## 2. What users can do

- Manage multiple providers (built-in + custom)
- Enable/disable providers
- Select current provider
- Switch provider/model in chat

---

## 3. Planned enhancements

### 3.1 Advanced provider fields UI

- headers JSON editor
- temperature/top_p/max_tokens
- clearer URL normalization guidance (baseUrl vs endpoint)

### 3.2 “Thinking” UX per provider

- OpenAI-compatible: optional “thinking summary” mode when `reasoning_content` is not provided
- Gemini: includeThoughts toggle is supported; ensure default ON per preference

### 3.3 Sync policy extensions

- Continue to exclude `api_key`
- Evaluate whether headers should sync by default (risk: headers may contain secrets)

---

## 4. Testing / Acceptance

- Editing fields is stable (no cursor jump)
- Apply selected provider affects chat immediately
- WebDAV sync: url/model/prompts sync; `api_key` unchanged
- Backups: plaintext excludes api_key; encrypted import restores api_key only with correct password
