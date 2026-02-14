# AI Panel UX / Config / Sync — Design Notes

> Maintainer note (fork): this folder documents the UX/config improvements planned for the Anx Reader AI chat panel, with a strong focus on iPad split-panel ergonomics.

## Scope

### Done / Implemented (fork)

- iPad AI panel (dock split view): resize via touch + persist size
- iPad: optional iPhone-style bottom sheet (now fixed large size; legacy resizable implementation exists)
- iPad: dock side switch (left/right) and gesture conflict mitigation with TOC drawer
- AI chat: font scale control
- AI chat input: configurable quick prompts chips
- Increase user prompt max length (target 20,000 chars)
- WebDAV sync of AI settings (excluding API keys)
- Manual backup/restore via Files/iCloud Drive (directional overwrite) with optional encrypted API key

### Planned / Next (fork)

- AI provider configuration UX redesign (Cherry-style UX, Flutter-native reimplementation)
- AI translation improvements:
  - split prompts for selection-translation vs full-text translation (full-text should output *clean translation only*)
  - PDF translation UX hardening (text-layer limitations)
- PDF AI improvements:
  - outline-based “chapter” extraction (page-range) when outline exists
  - fallback page-window context when outline missing
  - optional OCR via MinerU for scanned PDFs (cache + AI tool fallback)
- “Ask about the whole book” quality improvements:
  - keyword search + snippet aggregation (Phase 1)
  - optional embeddings + rerank (Phase 2, larger scope)

## PR Stack / Status (fork)

> Branches (top = newest). Note that some PRs may have a “work branch” and a “squashed branch” for upstream review.
> 
> Additional context: we checked recent work history in `memory/2026-02-13.md` (PR-1..5) and the repo docs branches.

- PR-8: `feat/ui-fixes`
  - AI chat font scale UI: use a stable dialog (avoid sheet-on-sheet auto-dismiss)
  - iOS/iPad bottom-sheet AI: **fixed large height** (remove hard-to-control resize)
  - Reading page: swipe up from the lower-middle area to open AI bottom sheet
  - Fix 1px red `bottom overflowed by 1.00 pixels` on bookshelf cards
  - iOS build metadata: Runner `CURRENT_PROJECT_VERSION` follows `$(FLUTTER_BUILD_NUMBER)`
- PR-7: `feat/backup-restore-encrypted-api-key-squashed`
  - Backup v4 ZIP + `manifest.json`
  - Optional encrypted API key inclusion (password-based)
  - Import confirmation + safe rollback via `.bak.<timestamp>`
- PR-6: `feat/ai-settings-webdav-sync`
  - WebDAV sync of `anx/config/ai_settings.json`
  - Whole-file timestamp newer-wins; **api_key excluded**
- PR-5: `feat/ai-quick-prompts-config` — configurable input quick prompts + prompt max length 20k
- PR-4: `feat/ai-chat-font-scale` — font scale slider (markdown + input)
- PR-3: `feat/ipad-ai-panel-mode-dock-side` — iPad panel mode (dock/bottomSheet) + dock side left/right
- PR-2: `feat/ai-bottom-sheet-resizable` — (superseded in PR-8) resizable bottom sheet + snap points + persist height
- PR-1: `feat/ipad-ai-panel-resize-persist` — dock resize handle (16px) + persist width/height

## Roadmap (planned)

> These are proposed next PRs/branches. Names may change.

- PR-9 (planned): AI provider configuration UX refactor
  - Cherry-style UX, Flutter-native implementation (no code reuse)
  - advanced fields: headers/temperature/top_p/max_tokens
  - optional: multiple OpenAI-compatible providers (custom entries)
- PR-10 (planned): AI translation UX hardening
  - split prompts: selection translate vs full-text translate
  - PDF translation guidance / safe fallback
- PR-11 (planned): PDF “chapter” extraction improvements for AI tools
  - outline-based page-range chapter content
  - fallback page-window content when outline missing
- PR-12 (planned): MinerU OCR integration for scanned PDFs
  - cache + status tracking + AI tool fallback
- PR-13 (planned): whole-book Q&A quality improvements
  - keyword search + snippet aggregation (Phase 1)
  - optional embeddings + rerank (Phase 2)

## Documents

- [AI panel UX tech design](./ai_panel_ux_tech_design.md)
- [AI settings sync (WebDAV) tech design](./ai_settings_sync_webdav.md)
- [Backup/restore (Files/iCloud) tech design](./backup_restore_icloud.md)
- [AI provider config UX redesign](./ai_provider_config_ux.md)
- [PDF AI chaptering & OCR (MinerU) design](./pdf_ai_chaptering_and_ocr.md)
- [AI translation design notes](./ai_translation_design.md)
- [iOS TestFlight build notes](./ios_testflight_build.md)
- [Test plan](./test_plan.md)
- [Implementation plan](./implementation_plan.md)
- [PR-6 draft](./pr_pr6_webdav_ai_settings.md)
- [PR-7 draft](./pr_pr7_backup_v4_encrypted_keys.md)
- [Release/Migration notes](./release_notes_migration_ai_sync_backup.md)
