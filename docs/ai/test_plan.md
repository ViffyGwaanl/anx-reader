# AI Panel / Sync / Backup — Test Plan

## Devices / Platforms

- iPadOS (>=600 width, e.g. iPad 11")
- iOS iPhone (<600 width)
- Android tablet/phone
- Desktop (optional)

## PR-1 Dock Resize

- [ ] Drag divider adjusts width/height smoothly
- [ ] 16px hit target works with finger
- [ ] Width/height persists after leaving/returning reading page
- [ ] Clamp works (min/max)

## PR-2 Bottom Sheet (legacy resizable)

> 注意：PR-8 已将 bottom sheet 收敛为 fixed large height（取消难用的拖拽调大小）。
> 若需要回归验证旧实现，可在 PR-2 分支单独验证。

- [ ] （可选）Drag handle changes height
- [ ] （可选）Snap points: 0.35/0.6/0.9/0.95
- [ ] （可选）Reopen remembers last size

## PR-3 iPad Panel Mode + Dock Side

- [ ] dock-right default unchanged
- [ ] dock-left order correct
- [ ] dock-left disables drawer edge swipe
- [ ] TOC button still opens drawer
- [ ] iPad bottomSheet mode forces modal sheet

## PR-4 Font Scale

- [ ] Slider updates markdown + input
- [ ] Persisted between opens
- [ ] Reset returns to 1.0
- [ ] UI does not auto-dismiss (especially when AI chat is inside a bottom sheet)

## PR-5 Quick Prompts Config

- [ ] Defaults shown when no custom list
- [ ] Custom list shows enabled chips only
- [ ] Editor supports add/edit/delete/reorder
- [ ] Reset clears custom list
- [ ] User prompt editor maxLength = 20000

## PR-6 WebDAV AI settings sync

- [ ] Upload/download ai_settings.json
- [ ] Does not sync api_key
- [ ] Conflict resolution uses updatedAt

## PR-7 Backup/Restore enhancements

- [ ] Export/import via Files works on iOS
- [ ] Clear warning about overwrite (pre-import confirmation)
- [ ] Optional encrypted api_key flow (password prompt)
- [ ] Rollback on failure (rename `.bak.<ts>` restore)
- [ ] Unit: `flutter test test/service/backup_crypto_test.dart`

## PR-8 Reading/AI UX hotfix

- [ ] Bookshelf page: no red `bottom overflowed by 1.00 pixels` warnings
- [ ] Bottom sheet: opens at large fixed height (~95%), swipe-down dismiss works
- [ ] Reading page: swipe up from lower-middle region opens AI bottom sheet
- [ ] Font scale: dialog stays open; slider works; persisted

## PR-9 AI provider configuration UX

- [ ] Editing is stable (no cursor jumps while typing)
- [ ] Basic fields work: url/baseUrl, model, api_key (hide/show)
- [ ] Test button reports actionable errors (401/404/model-not-found/network)
- [ ] Advanced fields (if implemented): headers/temperature/top_p/max_tokens persisted

## PR-10 AI translation hardening

- [ ] Selection translation: detailed (glossary/notes allowed)
- [ ] Full-text translation: translation-only (no extra analysis blocks)
- [ ] Long paragraphs are chunked or capped to reduce failure rate
- [ ] PDF: safe fallback behavior (selection preferred)

## PR-11 PDF AI chaptering

- [ ] PDF with outline: chapter content returns multi-page range
- [ ] PDF without outline: current chapter uses page-window context

## PR-12 MinerU OCR (scanned PDFs)

- [ ] OCR job can be started and cached
- [ ] After OCR, AI chapter/page tools return meaningful text
- [ ] No repeated OCR runs once cached

