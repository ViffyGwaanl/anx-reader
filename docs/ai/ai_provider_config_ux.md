# AI Provider Configuration UX Redesign (Cherry-style, Flutter-native)

## 0. Background / Current State

Anx Reader currently supports multiple AI providers through LangChain chat model wrappers:

- `openai` / `deepseek` / `openrouter` → **OpenAI-compatible** (`ChatOpenAI`)
- `claude` → **Anthropic Messages API** (`ChatAnthropic`)
- `gemini` → **Google Gemini API** (`ChatGoogleGenerativeAI`)

Key code:

- Registry/router: `lib/service/ai/langchain_registry.dart`
- Provider defaults list: `lib/service/ai/ai_services.dart`
- Settings UI (current): `lib/page/settings_page/ai.dart`

### Current UX pain points

- The settings page creates `TextEditingController` inside `build()`, causing unstable editing and cursor jumps.
- Provider config is a flat key/value list (`url`, `api_key`, `model`) with no guidance for OpenAI-compatible edge cases.
- No good structure for “advanced” config: headers / temperature / top_p / tokens.
- Not designed for managing multiple OpenAI-compatible endpoints (e.g. multiple gateways).

## 1. Goals

1. Make provider configuration **easy and reliable** (no cursor jump, clear field ordering).
2. Provide a **Cherry-style information architecture**:
   - provider list (cards)
   - provider detail editor
   - enable/disable
   - test connection
   - apply selected provider
3. Support OpenAI-compatible real-world usage:
   - custom headers (JSON)
   - temperature / top_p / max_tokens (and Gemini max_output_tokens)
4. Keep security rules unchanged:
   - WebDAV sync must **NOT** include `api_key`
   - backups must **NOT** include plaintext `api_key` unless encrypted

## 2. Non-goals

- Do not copy/port code from other projects.
- Do not implement embeddings here (separate roadmap).

## 3. Legal / Licensing note (important)

Cherry Studio App (`https://github.com/CherryHQ/cherry-studio-app`) is licensed under **AGPL-3.0**.

Anx Reader is **MIT**.

Therefore:

- ✅ We may **use Cherry Studio as UX inspiration** (ideas, screenshots, interaction patterns).
- ❌ We must **not copy code** (including “small” snippets) into this repo.

## 4. Proposed UX

### 4.1 Provider list page

Each provider card shows:

- Logo + name
- Provider type badge:
  - OpenAI-compatible
  - Anthropic
  - Gemini
- Enabled toggle
- Selected indicator
- Quick actions:
  - Test
  - Edit

### 4.2 Provider editor page

**Basic fields (ordered):**

- Name (display only; optional for custom providers)
- API base URL / endpoint
- Model
- API key (hide/show)

**Advanced fields (collapsible):**

- Headers (JSON map)
- Temperature
- Top-p
- Max tokens / Max output tokens

**Actions:**

- Save
- Apply (set as selected)
- Test
- Reset
- Delete (custom providers only)

## 5. Data model & storage

### 5.1 Phase 1 (minimal change)

- Keep current storage keys:
  - `Prefs().selectedAiService`
  - `Prefs().getAiConfig(identifier)` and `Prefs().saveAiConfig(identifier, map)`

- Improve UI only.

### 5.2 Phase 2 (custom providers)

Add the ability to create multiple OpenAI-compatible providers.

Options:

- (A) Store custom providers in `SharedPreferences` as a JSON list (recommended first).
- (B) Migrate to a small local DB table (heavier).

Sync impact:

- Update WebDAV sync schema to include custom providers (still excluding `api_key`).

## 6. Testing / Acceptance

- Editing is stable (no cursor jumps, no losing input).
- OpenAI-compatible provider with custom headers can pass Test.
- Applying selected provider affects AI chat immediately.
- WebDAV sync includes URL/model/prompts/UI settings but **does not change local api_key**.

## 7. Implementation plan (proposed PR breakdown)

- PR-9A: Refactor existing settings page controllers & field ordering.
- PR-9B: Add advanced fields UI + persistence.
- PR-9C (optional): Add custom OpenAI-compatible providers + sync schema update.
