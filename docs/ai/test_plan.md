# AI Panel / Provider Center / Streaming — Test Plan

## Devices / Platforms

- iPadOS (>=600 width, e.g. iPad 11")
- iOS iPhone (<600 width)
- Android tablet/phone (optional)
- Desktop (optional)

---

## 1) Reading-page AI panel UX

### Dock mode (iPad)

- [ ] Drag divider adjusts width/height smoothly
- [ ] 16px+ hit target works with finger
- [ ] Width/height persists after leaving/returning reading page
- [ ] Clamp works (min/max)
- [ ] Dock-left: drawer edge swipe disabled; TOC button still opens drawer

### Bottom-sheet mode (iPhone + iPad optional)

- [ ] Opens expanded by default on reading page
- [ ] Can minimize to bar (0.12)
- [ ] Snap points work (0.12/0.35/0.6/0.9/0.95)
- [ ] Minimize/expand does not cause layout assertions

### Streaming continuity (root-cause acceptance)

- [ ] Start generation → minimize → keep reading (scroll/flip pages) → expand → generation continued
- [ ] Start generation → close the sheet (X) → keep reading → reopen AI → final result exists
- [ ] Start generation → background/foreground app → generation does not crash (behavior may depend on OS; at minimum no asserts)
- [ ] Stop button cancels immediately

---

## 2) Chat UX / Conversation tree v2

- [ ] Variant switcher works (left/right) for assistant groups
- [ ] Edit a prior user message and regenerate creates a new branch (old preserved)
- [ ] Switch back to old variant restores previous subtree
- [ ] Reading page rollback behaves same as non-reading chat

---

## 3) Provider Center

- [ ] Provider list shows built-ins + custom providers
- [ ] Enable/disable provider works
- [ ] Apply provider updates in-chat provider immediately
- [ ] In-chat provider + model switch persists

---

## 4) Thinking / Tools display

- [ ] Gemini includeThoughts=ON shows Thinking section
- [ ] OpenAI-compatible backend returning `reasoning_content` shows Thinking section
- [ ] OpenAI-compatible backend **without** `reasoning_content`: no Thinking section (no prompt-based fallback)
- [ ] thinkingMode=off does NOT request thinking, but if backend still returns reasoning_content it is displayed
- [ ] Tools timeline renders and collapses/expands

---

## 5) Config / Sync / Backup

### Quick prompts

- [ ] Defaults shown when no custom list
- [ ] Custom list shows enabled chips only
- [ ] Editor supports add/edit/delete/reorder
- [ ] Reset clears custom list
- [ ] User prompt editor maxLength = 20000

### WebDAV AI settings sync

- [ ] Upload/download `anx/config/ai_settings.json`
- [ ] Does not sync `api_key`
- [ ] Conflict resolution uses `updatedAt` newer-wins

### Backup/Restore

- [ ] Export/import via Files works on iOS
- [ ] Clear warning about overwrite (pre-import confirmation)
- [ ] Optional encrypted api_key flow (password prompt)
- [ ] Rollback on failure (rename `.bak.<ts>` restore)
- [ ] Unit: `flutter test test/service/backup_crypto_test.dart`
