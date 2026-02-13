# AI Panel UX / Config / Sync — Design Notes

> Maintainer note (fork): this folder documents the UX/config improvements planned for the Anx Reader AI chat panel, with a strong focus on iPad split-panel ergonomics.

## Scope

- iPad AI panel (dock split view): resize via touch + persist size
- iPad: optional iPhone-style bottom sheet (resizable)
- iPad: dock side switch (left/right) and gesture conflict mitigation with TOC drawer
- AI chat: font scale control
- AI chat input: configurable quick prompts chips
- Increase user prompt max length (target 20,000 chars)
- WebDAV sync of AI settings (excluding API keys)
- Manual backup/restore via Files/iCloud Drive (directional overwrite) with optional encrypted API key

## PR Stack / Status (fork)

> Branches (top = newest):

- PR-5: `feat/ai-quick-prompts-config` — configurable input quick prompts + prompt max length 20k
- PR-4: `feat/ai-chat-font-scale` — font scale slider (markdown + input)
- PR-3: `feat/ipad-ai-panel-mode-dock-side` — iPad panel mode (dock/bottomSheet) + dock side left/right
- PR-2: `feat/ai-bottom-sheet-resizable` — resizable bottom sheet + snap points + persist height
- PR-1: `feat/ipad-ai-panel-resize-persist` — dock resize handle (16px) + persist width/height

## Documents

- [AI panel UX tech design](./ai_panel_ux_tech_design.md)
- [AI settings sync (WebDAV) tech design](./ai_settings_sync_webdav.md)
- [Backup/restore (Files/iCloud) tech design](./backup_restore_icloud.md)
- [Test plan](./test_plan.md)
