# AI Panel UX / Config / Sync — Design & Implementation Notes

> Maintainer note (fork): This folder documents the AI-related UX/config/sync improvements for the Anx Reader fork, with a strong focus on iPad reading ergonomics and “Cherry-style” provider/chat UX.

## Scope

### Implemented (fork, `feat/ai-all-in-one`)

#### Reading-page AI panel UX (iPad/iPhone)

- iPad dock split panel: **touch-friendly resize** + **persist** width/height
- iPad: panel mode setting (dock vs bottom sheet)
- iPad: dock side switch (left/right) + TOC drawer gesture mitigation
- iPhone/iPad bottom-sheet mode:
  - `DraggableScrollableSheet` with snap points
  - can **minimize** to a small bar (keep reading)
  - open defaults to expanded on reading page
- Streaming UX:
  - **minimize instead of dismiss** (supports “keep generating while reading”)
  - open does **not** auto-scroll to bottom
  - streaming auto-scroll only when user is pinned near bottom

#### Chat UX (Cherry-inspired, Flutter-native)

- Provider Center (top-level settings entry)
  - built-in providers + custom providers
  - in-chat provider/model switching
- “Thinking level” (档位) selector (Cherry-style lightbulb UI)
- Gemini thinking support: `includeThoughts` toggle (default ON)
- Thinking/Answer/Tools sections: collapsible display
- Editable chat history + regenerate from any user turn
- Per-turn assistant variants (left/right switch)
- Conversation tree v2 (`conversationV2`) with rollback via per-message variant switcher

#### Config / Sync / Backup

- Configurable input quick prompts chips
- User prompt editor maxLength raised to **20,000**
- WebDAV sync of AI settings snapshot (**excluding api_key**) with timestamp newer-wins
- Files/iCloud manual backup/restore:
  - directional overwrite options
  - optional **encrypted API key** inclusion (password-based)
  - rollback-safe import

#### OpenAI-compatible “thinking content” compatibility

- If an OpenAI-compatible backend returns `reasoning_content` (or `reasoning`) in responses/stream deltas, the fork maps it to the app’s `<think>...</think>` channel so it shows inside the Thinking section.

---

## Other modules (fork)

- [PaperTok (papers feed) — UX + import behavior](../papertok/README.md)

## Architecture Notes (important)

### Provider-managed streaming (root-cause fix)

**Problem:** when streaming is owned by a Widget (`StreamSubscription` in the UI), any UI lifecycle change (bottom sheet minimize/rebuild, scrollController swap, route changes) can interrupt generation.

**Fix:** streaming is moved into `aiChatProvider` (keepAlive) and the UI becomes a pure renderer:

- `aiChatProvider.notifier.startStreaming(...)`
- `aiChatProvider.notifier.cancelStreaming()`
- `aiChatStreamingProvider` exposes streaming state for UI (send/stop button, disabling edits, etc.)

This is the “root-cause” solution for “minimize/close should not interrupt generation”.

### Tooling / agent mode dependency on Riverpod `Ref`

To allow provider-owned agent streaming (reading tools), tool code paths now accept **Riverpod core `Ref`** (not Flutter-only `WidgetRef`).

---

## Branch / PR Stack (fork)

Primary integration branch for local install + iPhone/iPad testing:

- `feat/ai-all-in-one`

This branch includes all AI-related changes (PR-1..7 line + Provider Center/chat UX stack + reading-page UX fixes).

---

## Documents

- [AI 改造：已完成 & 路线图（中文）](./ai_status_roadmap_zh.md)
- [P1：OpenAI-compatible Thinking（仅展示供应商数据，无兜底）（中文）](./ai_thinking_openai_provider_only_zh.md)
- [AI panel UX tech design](./ai_panel_ux_tech_design.md)
- [AI provider config UX (Provider Center)](./ai_provider_config_ux.md)
- [AI settings sync (WebDAV) tech design](./ai_settings_sync_webdav.md)
- [Backup/restore (Files/iCloud) tech design](./backup_restore_icloud.md)
- [PDF AI chaptering & OCR (MinerU) design](./pdf_ai_chaptering_and_ocr.md)
- [AI translation design notes](./ai_translation_design.md)
- [iOS TestFlight build notes](./ios_testflight_build.md)
- [Test plan](./test_plan.md)
- [Implementation plan](./implementation_plan.md)
- [Release/Migration notes](./release_notes_migration_ai_sync_backup.md)

---

## Developer Notes

### Codegen requirements

This repo ignores generated files (e.g. `*.g.dart`, `*.freezed.dart`, `lib/gen/`). After pulling branches/PRs, regenerate:

```bash
flutter pub get
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
```
