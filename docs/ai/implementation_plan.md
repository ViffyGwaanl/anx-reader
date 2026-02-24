# Implementation Plan (AI stack on fork)

This file tracks what is implemented in the fork and what remains, written as an engineering checklist.

> Primary integration branch: `feat/ai-all-in-one`

---

## Completed (high level)

### UX

- [x] iPad dock AI panel: resize + persist width/height
- [x] iPad: dock side switch (left/right) + gesture conflict mitigation with TOC drawer
- [x] iPad: panel mode setting (dock vs bottom sheet)
- [x] Bottom sheet: resizable/minimizable with snap points; reading page opens expanded
- [x] AI chat font scale
- [x] Configurable input quick prompts
- [x] Prompt editor maxLength → 20,000

### Config / Sync / Backup

- [x] WebDAV sync of AI settings snapshot (`anx/config/ai_settings.json`)
  - whole-file timestamp newer-wins
  - **exclude api_key**
- [x] Manual backup/restore via Files/iCloud
  - v4 zip + manifest
  - optional encrypted API key inclusion (password-based)
  - rollback-safe import

### Provider Center + Cherry-inspired chat UX (Flutter-native)

- [x] Provider Center top-level entry + CRUD
- [x] In-chat provider + model switch
- [x] Thinking level selector + Gemini includeThoughts support
- [x] Thinking/Answer/Tools collapsible sections
- [x] Editable history + regenerate from any user turn
- [x] Per-turn variants switcher
- [x] Conversation tree v2 persistence (`conversationV2`) + rollback

### OpenAI-compatible reasoning display

- [x] Map `reasoning_content` / `reasoning` to Thinking section when provided by backend.

---

## Root-cause fix: provider-managed streaming (DONE)

### Problem statement

- UI-owned `StreamSubscription` is fragile: minimizing a sheet, swapping scroll controllers, or route rebuilds can interrupt streaming.

### Implementation

- [x] Move chat streaming ownership into `aiChatProvider` (keepAlive)
  - `startStreaming(...)` runs generation and updates provider `state` per chunk
  - `cancelStreaming()` cancels generation
  - `aiChatStreamingProvider` exposes streaming status for UI
- [x] Update `AiChatStream` to be “render-only”
  - no widget-owned streaming controller/subscription
  - send/regen/edit call provider methods
- [x] Refactor agent/tool code paths to accept Riverpod core `Ref` (provider-friendly)

### Acceptance criteria

- [ ] Reading page: minimize bottom sheet → generation continues (no interruption)
- [ ] Close the sheet (not exit reading page) → generation continues
- [ ] Stop button cancels immediately
- [ ] No crashes/assertions during rapid minimize/expand

---

## Next work (planned)

### A) OpenAI-compatible “thinking” (provider-only)

Background: many OpenAI-compatible providers do not return `reasoning_content`.

- [ ] Do NOT add prompt-based thinking fallback. If provider returns nothing, show nothing.
- [ ] Ensure `reasoning_content`/`reasoning` is preserved end-to-end and rendered as Thinking.
- [ ] thinkingMode=off: do not request reasoning; but if backend still returns reasoning_content, display it.
- [ ] Add unit tests for streaming parsing (metadata reasoning_content/reasoning).
- [ ] Update docs: `ai_thinking_openai_provider_only_zh.md`

### B) Provider Center stability / iPad navigation

- [ ] Re-test `_dependents.isEmpty` assertion under rapid navigation
- [ ] Remove any remaining redundant `Prefs().initPrefs()` patterns if still present

### C) Conversation tree v2 test hardening

- [ ] Add widget test: edit+regen creates branch, then switch variant back and assert previous subtree restores

### D) iOS install / TestFlight polish

- [ ] Add a short “install checklist” section to docs for common signing/entitlements issues
- [ ] Capture known Xcode error signatures and fixes

---

## Engineering constraints (important)

- License: Cherry Studio App is AGPL-3.0, Anx Reader is MIT → UX inspiration only, no code reuse.
- Generated files are gitignored → always run build_runner + l10n generation when switching branches.
